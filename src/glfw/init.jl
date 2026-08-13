# Bringing GLFW up: late, once, and without throwing.

const INITIALIZED = Ref(false)
const LASTERROR = Ref("")

"Whether `glfwInit` has run successfully in this process."
isinitialized() = INITIALIZED[]

"What GLFW said the last time `initialize` failed, or an empty string."
lasterror() = LASTERROR[]

# Cocoa requires that windows are created and events polled on thread 1.
# X11, Wayland and Win32 tolerate other threads, so assert only where
# getting it wrong takes the process down with it.
function require_main_thread()
    if Sys.isapple() && Threads.threadid() != 1
        error("StatusWindows: on macOS GLFW must be used from thread 1, but \
               this is thread $(Threads.threadid()).")
    end
    return nothing
end

# glfwGetError both reports and clears the pending error, so calling it
# leaves the library ready for the next attempt.
function takeerror()
    desc = Ref{Ptr{Cchar}}(C_NULL)
    code = ccall((:glfwGetError, libglfw), Cint, (Ref{Ptr{Cchar}},), desc)
    code == 0 && return ""
    return desc[] == C_NULL ? "GLFW error $code" : unsafe_string(desc[])
end

"Set an init hint. Only has an effect before GLFW is initialized."
InitHint(hint::Integer, value::Integer) =
    ccall((:glfwInitHint, libglfw), Cvoid, (Cint, Cint), hint, value)

"""
    initialize(; platform = ANY_PLATFORM) -> Bool

Bring GLFW up if it is not up already, and say whether it worked.

Returning `false` rather than throwing is the point of this module: a
machine with no display, a session that refuses the connection, or a
library that will not even load all end here, and the caller decides what
to do about it. `lasterror()` says what went wrong.

`platform` names the backend to ask for. It is a preference, not a
requirement — if GLFW cannot give it, this falls back to letting GLFW
choose, since a panel on the wrong backend beats no panel at all.
"""
function initialize(; platform::Integer = ANY_PLATFORM)
    INITIALIZED[] && return true
    require_main_thread()

    ok = tryinit(platform)
    # Asking for X11 on a session that only has Wayland lands here: GLFW
    # refused the backend, not the display, so try again without a demand.
    if !ok && platform != ANY_PLATFORM
        requested = LASTERROR[]
        ok = tryinit(ANY_PLATFORM)
        # Report both: on its own, either half sends the reader after the
        # wrong thing -- the requested backend when the display is what is
        # missing, or the display when only the backend was.
        ok || (LASTERROR[] = requested * "; then any backend: " * LASTERROR[])
    end

    if ok
        INITIALIZED[] = true
        LASTERROR[] = ""
        # Matches GLFW.jl: a process that exits with windows still open
        # should hand them back to the window system.
        atexit(terminate)
    end
    return ok
end

function tryinit(platform::Integer)
    try
        InitHint(PLATFORM, platform)
        if ccall((:glfwInit, libglfw), Cint, ()) != 1
            LASTERROR[] = takeerror()
            return false
        end
        return true
    catch err
        # The library could not be loaded at all; nothing above this can do
        # anything useful with that either, so it is just another failure.
        LASTERROR[] = sprint(showerror, err)
        return false
    end
end

"Shut GLFW down, destroying any windows it still owns. Safe to call twice."
function terminate()
    INITIALIZED[] || return nothing
    INITIALIZED[] = false
    ccall((:glfwTerminate, libglfw), Cvoid, ())
    return nothing
end

"""
    platformcode(name) -> Integer

Translate a `JULIA_GLFW_PLATFORM` value — `"x11"`, `"wayland"`, `"cocoa"`,
`"win32"`, `"null"` — into the constant `initialize` wants. Anything else
means no preference, which is also what GLFW.jl does with the variable.
"""
platformcode(name::AbstractString) =
    name == "win32"   ? PLATFORM_WIN32   :
    name == "cocoa"   ? PLATFORM_COCOA   :
    name == "wayland" ? PLATFORM_WAYLAND :
    name == "x11"     ? PLATFORM_X11     :
    name == "null"    ? PLATFORM_NULL    :
                        ANY_PLATFORM
