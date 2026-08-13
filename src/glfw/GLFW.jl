# The slice of the GLFW C API this package uses, bound to the library itself.
#
# Why this exists rather than a dependency on GLFW.jl: that package calls
# glfwInit() from its own __init__ and throws when there is no display, so
# `using StatusWindows` died on a server before a line of this package ran.
# Nothing could catch it from here, and the workaround was an environment
# variable the user had to know about. Here loading the module touches no
# window system at all. GLFW comes up on the first Panel that wants a
# window, and `initialize` reports failure by returning false, which is what
# lets a headless machine get an inert panel instead of a stack trace.
#
# Names and values are GLFW's own, so glfw.org documents them as they stand.
# The Julia-level conveniences GLFW.jl adds -- enums, monitors, joysticks,
# Vulkan, the error callback -- are deliberately absent: what is here is
# what src/panel.jl calls, and adding to it means adding a binding.
#
# The bindings were written by borrowing from GLFW.jl (MIT, copyright (c)
# 2013-2019 The GLFW.jl Authors): the ccall signatures, the callback
# arrangement and the constant values all come from there. NOTICE.md in
# this folder says what came from where and carries the license text.

module GLFW

using GLFW_jll

include("constants.jl")
include("init.jl")
include("window.jl")
include("callbacks.jl")

end # module
