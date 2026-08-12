"""
Real TeX math for StatusWindows, loaded when MathTeXEngine is present.

MathTeXEngine parses a formula and hands back positioned elements in em
units with the y axis pointing up. This turns those into pixels: glyphs are
rasterized through FreeType and composited onto the panel's Cairo surface,
and fraction bars come out as plain rectangles.

Going through FreeType rather than fontconfig is what makes this portable —
MathTeXEngine ships its own fonts, so the result does not depend on
anything being installed on the user's machine.
"""
module StatusWindowsMathTeXExt

using StatusWindows
using StatusWindows: Canvas, RGBA
using Cairo
using MathTeXEngine
using MathTeXEngine: TeXChar, HLine
using FreeTypeAbstraction: renderface

"A rasterized glyph and where its top-left corner belongs, in pixels."
struct Glyph
    cov::Matrix{UInt8}   # coverage, (width, height) column-major
    x::Int
    y::Int
end

"A fraction bar or radical rule: x, y, width, height in pixels."
const Rule = NTuple{4,Float64}

"""
    layout(tex, fontsize) -> glyphs, rules, bbox

Rasterize `tex` at `fontsize` pixels per em. Positions come back relative
to the layout origin, which is the baseline of the outermost row; `bbox` is
`(xmin, ymin, xmax, ymax)` over everything actually drawn.
"""
function layout(tex::AbstractString, fontsize::Real)
    glyphs, rules = Glyph[], Rule[]
    xmin = ymin =  Inf
    xmax = ymax = -Inf

    for (elem, pos, scale) in generate_tex_elements(String(tex))
        # MathTeXEngine's y points up, Cairo's points down.
        x = pos[1] * fontsize
        y = -pos[2] * fontsize

        if elem isa TeXChar
            px = max(round(Int, scale * fontsize), 1)
            cov, ext = renderface(elem.font, elem.glyph_id, px)
            isempty(cov) && continue
            # horizontal_bearing is (left, top-above-baseline).
            gx = round(Int, x + ext.horizontal_bearing[1])
            gy = round(Int, y - ext.horizontal_bearing[2])
            push!(glyphs, Glyph(cov, gx, gy))
            w, h = size(cov)
            xmin = min(xmin, gx);     ymin = min(ymin, gy)
            xmax = max(xmax, gx + w); ymax = max(ymax, gy + h)
        else # HLine, centred on its position
            w = elem.width * fontsize
            h = max(elem.thickness * fontsize, 1.0)
            ry = y - h / 2
            push!(rules, (x, ry, w, h))
            xmin = min(xmin, x);     ymin = min(ymin, ry)
            xmax = max(xmax, x + w); ymax = max(ymax, ry + h)
        end
    end

    isfinite(xmin) || return glyphs, rules, (0.0, 0.0, 0.0, 0.0)
    return glyphs, rules, (xmin, ymin, xmax, ymax)
end

"""
Composite one glyph's coverage onto `cr` in `color`.

Cairo wants premultiplied ARGB32, so the colour is scaled by coverage on
the way in rather than leaned on the blender to sort out.
"""
function stamp!(cr::CairoContext, g::Glyph, ox::Int, oy::Int, color::RGBA)
    w, h = size(g.cov)
    r, gr, b, a = color
    argb = Matrix{UInt32}(undef, w, h)
    @inbounds for j in 1:h, i in 1:w
        cov = (g.cov[i, j] / 255) * a
        argb[i, j] = (round(UInt32, cov * 255)      << 24) |
                     (round(UInt32, r  * cov * 255) << 16) |
                     (round(UInt32, gr * cov * 255) <<  8) |
                      round(UInt32, b  * cov * 255)
    end
    surf = Cairo.CairoImageSurface(argb, Cairo.FORMAT_ARGB32; flipxy = false)
    Cairo.set_source_surface(cr, surf, ox + g.x, oy + g.y)
    Cairo.paint(cr)
    return nothing
end

function StatusWindows.math!(c::Canvas, tex::AbstractString;
                             color::RGBA = c.style.fg,
                             size::Real = c.style.size * 1.35,
                             align::Symbol = :left)
    st = c.style
    glyphs, rules, (xmin, ymin, xmax, ymax) = layout(tex, size)
    isempty(glyphs) && isempty(rules) && return c

    w, h = xmax - xmin, ymax - ymin
    left = if align === :right
        c.w - st.pad - w
    elseif align === :center
        (c.w - w) / 2
    else
        st.pad
    end

    # Shift the layout so its ink box starts at (left, c.y).
    ox = round(Int, left - xmin)
    oy = round(Int, c.y  - ymin)

    Cairo.save(c.cr)
    for g in glyphs
        stamp!(c.cr, g, ox, oy, color)
    end
    Cairo.set_source_rgba(c.cr, color...)
    for (rx, ry, rw, rh) in rules
        Cairo.rectangle(c.cr, ox + rx, oy + ry, rw, rh)
        Cairo.fill(c.cr)
    end
    Cairo.restore(c.cr)

    c.y += h + st.line / 3
    return c
end

"""
    mathwidth(c::Canvas, tex; size)

Width in pixels that [`math!`](@ref) would need for `tex`.
"""
function StatusWindows.mathwidth(c::Canvas, tex::AbstractString;
                                 size::Real = c.style.size * 1.35)
    _, _, (xmin, _, xmax, _) = layout(tex, size)
    return xmax - xmin
end

end # module
