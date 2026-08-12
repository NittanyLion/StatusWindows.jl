# The window itself: creation, the redraw tick, and the event loop.

# GLFW 3.4 has GLFW_MOUSE_PASSTHROUGH but GLFW.jl does not export the
# constant, so spell it out. Only consulted when `passthrough = true`.
const MOUSE_PASSTHROUGH = 0x0002000D

"""
    Panel(; kwargs...)

An undecorated, always-on-top window you fill with your own drawing.

Keyword arguments:

  * `width`, `height` — panel size in logical pixels.
  * `x`, `y` — position of the top-left corner on the desktop, in the same
    logical pixels.
  * `scale` — how many device pixels go to a logical one. `:auto` asks the
    window system, which is what makes the panel come out the same physical
    size on a 96 dpi monitor and on a 240 dpi one; pass a number to pin it.
  * `transparent` — request a transparent framebuffer, so the panel blends
    with the wallpaper. Needs a compositor; see the README for caveats.
  * `ontop` — keep the panel above other windows.
  * `decorated` — draw a title bar. Off by default; turn it on while
    debugging placement.
  * `movable` — drag the panel with the left mouse button.
  * `passthrough` — let clicks fall through to whatever is underneath.
    Implies the panel cannot be dragged.
  * `style` — a [`Style`](@ref) controlling colors, font and spacing.
  * `force_x11` — on Linux, force GLFW's X11 backend. GLFW's Wayland
    backend cannot position its own windows (the compositor decides, and
    `SetWindowPos` is a silent no-op), so this is what makes `x` and `y`
    mean anything under a Wayland session. Ignored if `DISPLAY` is unset.

Give it content with [`draw!`](@ref), then start it with [`run!`](@ref).

On a machine with no display — a server, a CI runner — there is nothing to
put a window on, so `Panel` warns once and hands back an inert panel instead
of failing. Every method on one does nothing, which lets a script written
for a desktop run unchanged where there is no desktop. [`hasdisplay`](@ref)
is the test it uses and [`isactive`](@ref) reports what you got. To produce
output on such a machine, use [`render`](@ref), which never needs a window.
"""
mutable struct Panel
    window::GLFW.Window
    style::Style
    buf::Matrix{UInt32}
    surface::Cairo.CairoSurface
    tex::GLuint
    prog::GLuint
    vao::GLuint
    w::Int              # logical size
    h::Int
    fbw::Int            # framebuffer size (differs from logical on HiDPI)
    fbh::Int
    scale::Float64      # device pixels per logical pixel, for size and position
    content::Union{Nothing,Function}
    running::Bool
    task::Union{Nothing,Task}
    dragging::Bool
    dragx::Float64
    dragy::Float64
end

# GLFW.jl returns small structs from the size/position getters; unpack
# them without caring which field names this version happens to use.
_pair(v) = hasproperty(v, :width)  ? (Int(v.width), Int(v.height)) :
           hasproperty(v, :x)      ? (Int(v.x), Int(v.y)) :
                                     (Int(v[1]), Int(v[2]))

"""
    hasdisplay() -> Bool

Whether this process could actually put a window on a screen.

On Linux that means an X or Wayland session is reachable. macOS and Windows
have a window server whenever a user session does, and offer nothing as
cheap to test, so they answer `true` and let window creation be the judge.
"""
hasdisplay() = !Sys.islinux() ||
               haskey(ENV, "DISPLAY") || haskey(ENV, "WAYLAND_DISPLAY")

# GLFW.Window wraps a Ptr but defines no == against one, so comparing the
# window itself to C_NULL is always true. Reach for the handle.
"Whether `p` owns a real window, as opposed to being an inert stand-in."
isactive(p::Panel) = p.window.handle != C_NULL

# A panel with no window behind it. Every operation on one is a no-op, so a
# script written for a desktop still runs start to finish on a server.
function inertpanel(style::Style, w::Integer, h::Integer)
    buf = zeros(UInt32, 1, 1)
    surface = Cairo.CairoImageSurface(buf, Cairo.FORMAT_ARGB32; flipxy = false)
    return Panel(GLFW.Window(C_NULL), style, buf, surface, 0, 0, 0,
                 Int(w), Int(h), 1, 1, 1.0, nothing, false, nothing,
                 false, 0.0, 0.0)
end

function init_glfw!(force_x11::Bool)
    if force_x11 && Sys.islinux() && haskey(ENV, "DISPLAY")
        # Must happen before GLFW.Init; harmless if GLFW is already up, in
        # which case the platform has been chosen and we live with it.
        try
            GLFW.InitHint(GLFW.PLATFORM, GLFW.PLATFORM_X11)
        catch err
            @debug "StatusWindows: could not request the X11 backend" err
        end
    end
    GLFW.Init()
    return nothing
end

function Panel(; width::Integer = 300, height::Integer = 220,
                 x::Integer = 40, y::Integer = 40,
                 transparent::Bool = true, ontop::Bool = true,
                 decorated::Bool = false, movable::Bool = true,
                 passthrough::Bool = false, style::Style = Style(),
                 title::AbstractString = "StatusWindows",
                 scale::Union{Symbol,Real} = :auto,
                 force_x11::Bool = true)

    scale isa Symbol && scale !== :auto &&
        throw(ArgumentError("StatusWindows: scale must be :auto or a number"))

    # Cocoa insists that windows are created and polled on the main thread.
    # `start!` uses @async, which is sticky and stays on whatever thread made
    # the panel, so the only way to get this wrong is Threads.@spawn -- say so
    # here rather than letting AppKit abort the process.
    Sys.isapple() && Threads.threadid() != 1 && error("""
        StatusWindows: on macOS a Panel must be created on thread 1, but this \
        is thread $(Threads.threadid()). Create it on the main thread; `start!` \
        will keep its redraw loop there.""")

    if !hasdisplay()
        @warn """StatusWindows: no display, so this panel will do nothing. \
                 Use render(...) to write a .pdf, .svg or .png instead, which \
                 needs no window.""" maxlog=1
        return inertpanel(style, width, height)
    end

    init_glfw!(force_x11)
    GLFW.DefaultWindowHints()
    # Core 3.3 with forward compatibility is the profile macOS will give us,
    # and it is available everywhere else too.
    GLFW.WindowHint(GLFW.CONTEXT_VERSION_MAJOR, 3)
    GLFW.WindowHint(GLFW.CONTEXT_VERSION_MINOR, 3)
    GLFW.WindowHint(GLFW.OPENGL_PROFILE, GLFW.OPENGL_CORE_PROFILE)
    GLFW.WindowHint(GLFW.OPENGL_FORWARD_COMPAT, 1)
    GLFW.WindowHint(GLFW.DECORATED, decorated)
    GLFW.WindowHint(GLFW.FLOATING, ontop)
    GLFW.WindowHint(GLFW.RESIZABLE, 0)
    GLFW.WindowHint(GLFW.FOCUS_ON_SHOW, 0)
    GLFW.WindowHint(GLFW.TRANSPARENT_FRAMEBUFFER, transparent)
    passthrough && GLFW.WindowHint(MOUSE_PASSTHROUGH, 1)
    # Create hidden so the panel never flashes at the wrong spot.
    GLFW.WindowHint(GLFW.VISIBLE, 0)
    # X11 and Windows size windows in device pixels, so a 280-pixel panel is
    # thumbnail-sized on a 240 dpi screen; this hint multiplies the requested
    # size by the monitor's content scale. On macOS and Wayland, where window
    # sizes are already logical, it is a no-op -- there the same factor shows
    # up in the framebuffer size instead. Either way `winscale` below picks up
    # whatever actually happened.
    scale === :auto && GLFW.WindowHint(GLFW.SCALE_TO_MONITOR, 1)

    reqw, reqh = Int(width), Int(height)
    pixw, pixh = scale === :auto ? (reqw, reqh) :
                 (round(Int, reqw * scale), round(Int, reqh * scale))
    window = GLFW.CreateWindow(pixw, pixh, String(title))
    if window.handle == C_NULL
        # A display the window system admits to having but cannot draw on --
        # a locked-down session, a remote runner. Degrade the same way.
        @warn "StatusWindows: could not create a window; this panel will do \
               nothing." maxlog=1
        return inertpanel(style, width, height)
    end

    winscale = max(_pair(GLFW.GetWindowSize(window))[1] / reqw, eps())
    GLFW.SetWindowPos(window, round(Int, x * winscale), round(Int, y * winscale))
    GLFW.MakeContextCurrent(window)
    GLFW.SwapInterval(1)

    prog = build_program()
    tex  = build_texture()
    vao_ref = Ref{GLuint}(0)          # core profile requires a bound VAO
    glGenVertexArrays(1, vao_ref)
    glBindVertexArray(vao_ref[])

    buf = zeros(UInt32, 1, 1)
    surface = Cairo.CairoImageSurface(buf, Cairo.FORMAT_ARGB32; flipxy = false)

    p = Panel(window, style, buf, surface, tex, prog, vao_ref[],
              reqw, reqh, 0, 0, winscale, nothing, false, nothing,
              false, 0.0, 0.0)

    GLFW.SetKeyCallback(window, (_, key, _, action, _) -> begin
        if key == GLFW.KEY_ESCAPE && action == GLFW.PRESS
            stop!(p)
        end
    end)

    if movable && !passthrough
        GLFW.SetMouseButtonCallback(window, (win, button, action, _) -> begin
            if button == GLFW.MOUSE_BUTTON_LEFT
                if action == GLFW.PRESS
                    cx, cy = GLFW.GetCursorPos(win)
                    p.dragging, p.dragx, p.dragy = true, cx, cy
                elseif action == GLFW.RELEASE
                    p.dragging = false
                end
            end
        end)
        GLFW.SetCursorPosCallback(window, (win, cx, cy) -> begin
            if p.dragging
                wx, wy = _pair(GLFW.GetWindowPos(win))
                GLFW.SetWindowPos(win, round(Int, wx + cx - p.dragx),
                                       round(Int, wy + cy - p.dragy))
            end
        end)
    end

    ensure_surface!(p)
    GLFW.ShowWindow(window)
    return p
end

"""
    draw!(f, p::Panel)

Register `f` as the panel's content. It is called on every tick with a
[`Canvas`](@ref), and whatever it draws becomes the panel.

```julia
draw!(p) do c
    heading!(c, "SYSTEM")
    kv!(c, "load", string(Sys.loadavg()[1]))
end
```
"""
function draw!(f::Function, p::Panel)
    p.content = f
    return p
end

"Reallocate the Cairo surface when the framebuffer size changes."
function ensure_surface!(p::Panel)
    fbw, fbh = _pair(GLFW.GetFramebufferSize(p.window))
    fbw, fbh = max(fbw, 1), max(fbh, 1)
    if (fbw, fbh) != (p.fbw, p.fbh)
        p.fbw, p.fbh = fbw, fbh
        p.buf = zeros(UInt32, fbw, fbh)
        p.surface = Cairo.CairoImageSurface(p.buf, Cairo.FORMAT_ARGB32;
                                            flipxy = false)
    end
    return nothing
end

"Wipe the surface to fully transparent, then lay down the panel background."
function paint_background!(cr::CairoContext, st::Style, w::Real, h::Real)
    Cairo.save(cr)
    Cairo.set_operator(cr, Cairo.OPERATOR_SOURCE)
    Cairo.set_source_rgba(cr, 0.0, 0.0, 0.0, 0.0)
    Cairo.paint(cr)
    Cairo.restore(cr)

    st.bg[4] > 0 || return nothing
    r = st.radius
    Cairo.new_path(cr)
    Cairo.arc(cr, w - r, r,     r, -π/2, 0)
    Cairo.arc(cr, w - r, h - r, r, 0,    π/2)
    Cairo.arc(cr, r,     h - r, r, π/2,  π)
    Cairo.arc(cr, r,     r,     r, π,    3π/2)
    Cairo.close_path(cr)
    setcolor!(cr, st.bg)
    Cairo.fill(cr)
    return nothing
end

"""
    refresh!(p::Panel)

Redraw the panel once, immediately. [`run!`](@ref) calls this on a timer;
call it yourself if you drive the loop.
"""
function refresh!(p::Panel)
    isactive(p) || return p
    GLFW.MakeContextCurrent(p.window)
    ensure_surface!(p)

    cr = CairoContext(p.surface)
    # Draw in logical pixels; the surface is framebuffer-sized so text stays
    # sharp on HiDPI displays.
    Cairo.scale(cr, p.fbw / p.w, p.fbh / p.h)
    paint_background!(cr, p.style, p.w, p.h)
    if p.content !== nothing
        c = Canvas(cr, p.style, p.w, p.h)
        Base.invokelatest(p.content, c)
    end
    Cairo.destroy(cr)
    ccall((:cairo_surface_flush, Cairo.libcairo), Nothing, (Ptr{Nothing},),
          p.surface.ptr)

    upload!(p.tex, p.buf)
    blit(p.prog, p.vao, p.tex, p.fbw, p.fbh)
    GLFW.SwapBuffers(p.window)
    return p
end

"""
    run!(p::Panel; refresh = 1.0)

Block, redrawing every `refresh` seconds until the panel is closed or
[`stop!`](@ref) is called. Escape closes the panel.
"""
function run!(p::Panel; refresh::Real = 1.0)
    isactive(p) || return nothing
    p.running = true
    last = -Inf
    try
        while p.running && !GLFW.WindowShouldClose(p.window)
            t = time()
            if t - last >= refresh
                refresh!(p)
                last = t
            end
            GLFW.PollEvents()
            sleep(0.02)     # keeps drag latency low without busy-waiting
        end
    finally
        close(p)
    end
    return nothing
end

"""
    start!(p::Panel; refresh = 1.0)

Like [`run!`](@ref) but on a task, so the REPL stays usable. Stop it with
[`stop!`](@ref).
"""
function start!(p::Panel; refresh::Real = 1.0)
    isactive(p) || return p
    p.task = @async run!(p; refresh = refresh)
    return p
end

"Ask the panel's loop to finish; the window closes on the next tick."
stop!(p::Panel) = (p.running = false; p)

"Move the panel's top-left corner to `(x, y)`, in logical pixels."
function move!(p::Panel, x::Integer, y::Integer)
    isactive(p) || return p
    GLFW.SetWindowPos(p.window, round(Int, x * p.scale),
                                round(Int, y * p.scale))
    return p
end

function Base.resize!(p::Panel, w::Integer, h::Integer)
    p.w, p.h = Int(w), Int(h)
    isactive(p) || return p
    GLFW.SetWindowSize(p.window, round(Int, w * p.scale),
                                 round(Int, h * p.scale))
    return p
end

function Base.close(p::Panel)
    p.running = false
    if isactive(p) && GLFW.WindowShouldClose(p.window) !== nothing
        try
            GLFW.MakeContextCurrent(p.window)
            glDeleteTextures(1, Ref(p.tex))
            glDeleteVertexArrays(1, Ref(p.vao))
            glDeleteProgram(p.prog)
        catch err
            @debug "StatusWindows: GL teardown failed" err
        end
        GLFW.DestroyWindow(p.window)
    end
    return nothing
end

Base.show(io::IO, p::Panel) =
    print(io, "Panel(", p.w, "×", p.h,
          isactive(p) ? (p.running ? ", running" : "") : ", inert", ")")
