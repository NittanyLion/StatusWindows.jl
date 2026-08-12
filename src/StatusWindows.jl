"""
    StatusWindows

Borderless, always-on-top desktop panels you fill with your own content —
a conky-like window, driven from Julia.

A panel is a GLFW window with no decorations. Each tick the whole panel is
drawn into a Cairo image surface and blitted to the screen as a single
texture, so the drawing API is plain Cairo and the GPU work is one quad.

```julia
using StatusWindows

p = Panel(width = 300, height = 220, x = 40, y = 40)

draw!(p) do c
    heading!(c, "SYSTEM")
    kv!(c, "host", gethostname())
    bar!(c, "cpu", 0.42)
end

run!(p, refresh = 1.0)
```
"""
module StatusWindows

using GLFW
using Cairo
using ModernGL

export Panel, Canvas, Style
export draw!, run!, start!, stop!, refresh!, move!, hasdisplay, isactive
export heading!, text!, kv!, bar!, sparkline!, hrule!, spacer!, at!
export math!, mathwidth, poormansmath!, poormansmathwidth, content_width
export render, printstyle, fontfamilies

include("style.jl")
include("gl.jl")
include("panel.jl")
include("widgets.jl")
include("render.jl")

end # module
