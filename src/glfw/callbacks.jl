# Letting GLFW call back into Julia. The arrangement is GLFW.jl's, from its
# src/callback.jl, with the code-generating macros written out; see
# NOTICE.md.
#
# Two things have to hold for that to be safe. The closure must still be
# alive whenever C reaches for it, which is what the registry below is for:
# GLFW only ever holds the pointer to a wrapper defined here, and the Julia
# function it forwards to is kept alive by a global. And no exception may
# escape into the C frame that called us, which would abort the process, so
# every call goes through the try in `dispatch`.

mutable struct WindowCallbacks
    key::Union{Nothing,Function}
    mousebutton::Union{Nothing,Function}
    cursorpos::Union{Nothing,Function}
end
WindowCallbacks() = WindowCallbacks(nothing, nothing, nothing)

const REGISTRY = Dict{Ptr{Cvoid},WindowCallbacks}()

register!(window::Window) = (REGISTRY[window.handle] = WindowCallbacks(); nothing)
unregister!(window::Window) = (delete!(REGISTRY, window.handle); nothing)
callbacks(window::Window) = get!(WindowCallbacks, REGISTRY, window.handle)

function dispatch(handle::Ptr{Cvoid}, which::Symbol, args...)
    cbs = get(REGISTRY, handle, nothing)
    cbs === nothing && return nothing
    f = getfield(cbs, which)
    f === nothing && return nothing
    try
        f(Window(handle), args...)
    catch err
        @error "StatusWindows: a GLFW callback threw; dropping the event" exception =
            (err, catch_backtrace())
    end
    return nothing
end

# The C-side wrappers. These are what GLFW gets a pointer to; the arguments
# are passed on raw, so callers compare against the constants above rather
# than an enum.
_keycallback(handle::Ptr{Cvoid}, key::Cint, scancode::Cint, action::Cint,
             mods::Cint) = dispatch(handle, :key, key, scancode, action, mods)

_mousebuttoncallback(handle::Ptr{Cvoid}, button::Cint, action::Cint,
                     mods::Cint) = dispatch(handle, :mousebutton, button,
                                            action, mods)

_cursorposcallback(handle::Ptr{Cvoid}, x::Cdouble, y::Cdouble) =
    dispatch(handle, :cursorpos, x, y)

"""
    SetKeyCallback(window, f)

Call `f(window, key, scancode, action, mods)` on every key event, or pass
`nothing` to stop listening.
"""
function SetKeyCallback(window::Window, f::Union{Function,Nothing})
    require_main_thread()
    callbacks(window).key = f
    # @cfunction is evaluated here rather than cached in a global: the
    # pointer it yields is a code address, which does not survive being
    # baked into a precompiled image.
    ptr = f === nothing ? C_NULL :
          @cfunction(_keycallback, Cvoid, (Ptr{Cvoid}, Cint, Cint, Cint, Cint))
    ccall((:glfwSetKeyCallback, libglfw), Ptr{Cvoid}, (Window, Ptr{Cvoid}),
          window, ptr)
    return nothing
end

"""
    SetMouseButtonCallback(window, f)

Call `f(window, button, action, mods)` on every mouse button event, or pass
`nothing` to stop listening.
"""
function SetMouseButtonCallback(window::Window, f::Union{Function,Nothing})
    require_main_thread()
    callbacks(window).mousebutton = f
    ptr = f === nothing ? C_NULL :
          @cfunction(_mousebuttoncallback, Cvoid, (Ptr{Cvoid}, Cint, Cint, Cint))
    ccall((:glfwSetMouseButtonCallback, libglfw), Ptr{Cvoid},
          (Window, Ptr{Cvoid}), window, ptr)
    return nothing
end

"""
    SetCursorPosCallback(window, f)

Call `f(window, x, y)` whenever the cursor moves over the window, or pass
`nothing` to stop listening.
"""
function SetCursorPosCallback(window::Window, f::Union{Function,Nothing})
    require_main_thread()
    callbacks(window).cursorpos = f
    ptr = f === nothing ? C_NULL :
          @cfunction(_cursorposcallback, Cvoid, (Ptr{Cvoid}, Cdouble, Cdouble))
    ccall((:glfwSetCursorPosCallback, libglfw), Ptr{Cvoid},
          (Window, Ptr{Cvoid}), window, ptr)
    return nothing
end
