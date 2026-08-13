# Every GLFW constant this package hands to the library, and no others.
# The values are GLFW's, transcribed from GLFW.jl's glfw3.jl (see
# NOTICE.md), and have been stable across the 3.x series; they are spelled
# out here so that reading a hint against glfw.org's documentation needs no
# third package.

# Init hints, and the platforms glfwInitHint(PLATFORM, ...) accepts.
const PLATFORM         = 0x00050003
const ANY_PLATFORM     = 0x00060000
const PLATFORM_WIN32   = 0x00060001
const PLATFORM_COCOA   = 0x00060002
const PLATFORM_WAYLAND = 0x00060003
const PLATFORM_X11     = 0x00060004
const PLATFORM_NULL    = 0x00060005

# Window hints.
const RESIZABLE               = 0x00020003
const VISIBLE                 = 0x00020004
const DECORATED               = 0x00020005
const FLOATING                = 0x00020007
const TRANSPARENT_FRAMEBUFFER = 0x0002000A
const FOCUS_ON_SHOW           = 0x0002000C
const MOUSE_PASSTHROUGH       = 0x0002000D   # GLFW 3.4 and later
const SCALE_TO_MONITOR        = 0x0002200C

# Context hints. The panel asks for core 3.3 with forward compatibility,
# which is the most macOS will give and is available everywhere else.
const CONTEXT_VERSION_MAJOR = 0x00022002
const CONTEXT_VERSION_MINOR = 0x00022003
const OPENGL_FORWARD_COMPAT = 0x00022006
const OPENGL_PROFILE        = 0x00022008
const OPENGL_CORE_PROFILE   = 0x00032001

# Input. The callbacks below pass keys, buttons and actions through as the
# raw C values, so these are what to compare against.
const RELEASE           = Cint(0)
const PRESS             = Cint(1)
const KEY_ESCAPE        = Cint(256)
const MOUSE_BUTTON_LEFT = Cint(0)
