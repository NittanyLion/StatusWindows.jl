# Colours, fonts and the drawing cursor.

const RGBA = NTuple{4,Float64}

"""
    Style(; kwargs...)

Appearance of a [`Panel`](@ref): colours, font and spacing. Colours are
`(r, g, b, a)` tuples with components in `0..1`.

The defaults are a dark translucent panel with light text. `bg`'s alpha is
what makes the panel see-through, so drop it to `0.0` for the classic conky
look where only the text floats over the wallpaper.
"""
Base.@kwdef struct Style
    font::String        = "DejaVu Sans Mono"
    size::Float64       = 13.0
    fg::RGBA            = (0.88, 0.92, 0.96, 1.0)   # body text
    dim::RGBA           = (0.55, 0.61, 0.70, 1.0)   # labels, rules
    accent::RGBA        = (0.35, 0.80, 0.95, 1.0)   # bars, headings
    warn::RGBA          = (0.95, 0.62, 0.25, 1.0)
    bg::RGBA            = (0.05, 0.06, 0.09, 0.62)  # panel background
    pad::Float64        = 14.0                      # inner margin
    line::Float64       = 19.0                      # baseline-to-baseline
    radius::Float64     = 10.0                      # background corner radius
end

"""
    Canvas

What your draw function receives. Wraps a Cairo context plus the panel's
[`Style`](@ref), and carries a vertical cursor so widgets stack down the
panel without you tracking coordinates.

Fields `w` and `h` are the panel's logical size in pixels; `x` and `y` are
the current cursor. Reach for `c.cr` when you want to drive Cairo directly.
"""
mutable struct Canvas
    cr::CairoContext
    style::Style
    w::Float64
    h::Float64
    x::Float64
    y::Float64
end

Canvas(cr::CairoContext, style::Style, w::Real, h::Real) =
    Canvas(cr, style, Float64(w), Float64(h), style.pad, style.pad)

"Width available between the left and right margins."
content_width(c::Canvas) = c.w - 2 * c.style.pad

"Apply an `RGBA` tuple to the context."
setcolor!(cr::CairoContext, col::RGBA) = set_source_rgba(cr, col...)

"Select the style's font at `size` (defaults to the style's own size)."
function setfont!(c::Canvas; size::Real = c.style.size, bold::Bool = false)
    select_font_face(c.cr, c.style.font, Cairo.FONT_SLANT_NORMAL,
                     bold ? Cairo.FONT_WEIGHT_BOLD : Cairo.FONT_WEIGHT_NORMAL)
    set_font_size(c.cr, Float64(size))
    return c
end
