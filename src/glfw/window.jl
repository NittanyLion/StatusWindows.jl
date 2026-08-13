# Windows: creation, geometry, the GL context, and the event pump.

"""
    Window

A GLFW window handle. `Window(C_NULL)` is the null handle GLFW returns when
creation fails, and is what an inert panel carries.
"""
struct Window
    handle::Ptr{Cvoid}
end

Base.show(io::IO, w::Window) =
    print(io, "GLFW.Window(", w.handle == C_NULL ? "null" : repr(w.handle), ")")

"Reset every window hint to its default. Call before setting your own."
DefaultWindowHints() = ccall((:glfwDefaultWindowHints, libglfw), Cvoid, ())

"Set one window hint, which applies to the next window created."
WindowHint(hint::Integer, value::Integer) =
    ccall((:glfwWindowHint, libglfw), Cvoid, (Cint, Cint), hint, value)

"""
    CreateWindow(width, height, title) -> Window

Create a window with the hints currently set. The size is in whatever units
the platform measures windows in — device pixels on X11 and Windows,
logical ones on macOS and Wayland. Returns the null `Window` on failure
rather than throwing; `lasterror()` says why.
"""
function CreateWindow(width::Integer, height::Integer, title::AbstractString)
    require_main_thread()
    window = ccall((:glfwCreateWindow, libglfw), Window,
                   (Cint, Cint, Cstring, Ptr{Cvoid}, Ptr{Cvoid}),
                   width, height, String(title), C_NULL, C_NULL)
    if window.handle == C_NULL
        LASTERROR[] = takeerror()
    else
        register!(window)
    end
    return window
end

function DestroyWindow(window::Window)
    require_main_thread()
    # Drop the Julia callbacks first: GLFW may still pump events while it
    # tears the window down, and there is nothing left for them to do.
    unregister!(window)
    ccall((:glfwDestroyWindow, libglfw), Cvoid, (Window,), window)
    return nothing
end

ShowWindow(window::Window) =
    (require_main_thread();
     ccall((:glfwShowWindow, libglfw), Cvoid, (Window,), window))

"Whether the user has asked to close the window (the close button, Alt-F4)."
WindowShouldClose(window::Window) =
    ccall((:glfwWindowShouldClose, libglfw), Cint, (Window,), window) != 0

"Position of the window's top-left corner on the desktop, as `(x, y)`."
function GetWindowPos(window::Window)
    x, y = Ref{Cint}(), Ref{Cint}()
    ccall((:glfwGetWindowPos, libglfw), Cvoid, (Window, Ref{Cint}, Ref{Cint}),
          window, x, y)
    return (Int(x[]), Int(y[]))
end

SetWindowPos(window::Window, x::Integer, y::Integer) =
    ccall((:glfwSetWindowPos, libglfw), Cvoid, (Window, Cint, Cint), window, x, y)

"Size of the window, as `(width, height)`, in the platform's window units."
function GetWindowSize(window::Window)
    w, h = Ref{Cint}(), Ref{Cint}()
    ccall((:glfwGetWindowSize, libglfw), Cvoid, (Window, Ref{Cint}, Ref{Cint}),
          window, w, h)
    return (Int(w[]), Int(h[]))
end

SetWindowSize(window::Window, width::Integer, height::Integer) =
    ccall((:glfwSetWindowSize, libglfw), Cvoid, (Window, Cint, Cint),
          window, width, height)

"""
    GetFramebufferSize(window) -> (width, height)

Size of the drawing surface in device pixels. On a HiDPI display this is a
multiple of the window size, which is why the panel allocates its Cairo
surface from this and not from the window.
"""
function GetFramebufferSize(window::Window)
    w, h = Ref{Cint}(), Ref{Cint}()
    ccall((:glfwGetFramebufferSize, libglfw), Cvoid,
          (Window, Ref{Cint}, Ref{Cint}), window, w, h)
    return (Int(w[]), Int(h[]))
end

"Cursor position relative to the window's top-left corner, as `(x, y)`."
function GetCursorPos(window::Window)
    x, y = Ref{Cdouble}(), Ref{Cdouble}()
    ccall((:glfwGetCursorPos, libglfw), Cvoid,
          (Window, Ref{Cdouble}, Ref{Cdouble}), window, x, y)
    return (x[], y[])
end

"Process pending events, firing any callbacks they trigger."
PollEvents() = (require_main_thread();
                ccall((:glfwPollEvents, libglfw), Cvoid, ()))

MakeContextCurrent(window::Window) =
    ccall((:glfwMakeContextCurrent, libglfw), Cvoid, (Window,), window)

SwapBuffers(window::Window) =
    ccall((:glfwSwapBuffers, libglfw), Cvoid, (Window,), window)

"Frames to wait between buffer swaps; 1 is vsync."
SwapInterval(interval::Integer) =
    ccall((:glfwSwapInterval, libglfw), Cvoid, (Cint,), interval)
