# Stackable drawing helpers.
#
# Every widget draws at the canvas cursor and advances it, so a draw
# function reads top-to-bottom. None of this is privileged: `c.cr` is a
# plain Cairo context, so anything Cairo can do belongs here too.

"""
Font ascent, so a widget can turn a cursor position into a text baseline.

Cairo.jl wraps `text_extents` but not `font_extents`, so go to the C
library directly. `cairo_font_extents_t` is five doubles: ascent, descent,
height, max_x_advance, max_y_advance.
"""
function ascent(c::Canvas)
    fe = Vector{Float64}(undef, 5)
    ccall((:cairo_font_extents, Cairo.libcairo), Nothing,
          (Ptr{Nothing}, Ptr{Float64}), c.cr.ptr, fe)
    return fe[1]
end

"Advance of `str` in the current font, i.e. how wide it will draw."
function advance(c::Canvas, str::AbstractString)
    te = Cairo.text_extents(c.cr, String(str))
    return te[5]
end

"""
    at!(c::Canvas, x, y)

Move the drawing cursor. Both coordinates are in logical pixels from the
panel's top-left corner.
"""
at!(c::Canvas, x::Real, y::Real) = (c.x = Float64(x); c.y = Float64(y); c)

"""
    spacer!(c::Canvas, px = c.style.line / 2)

Leave `px` pixels of vertical space.
"""
spacer!(c::Canvas, px::Real = c.style.line / 2) = (c.y += Float64(px); c)

"""
    text!(c::Canvas, str; color, size, bold, align)

Draw one line of text and advance the cursor. `align` is `:left`,
`:right` or `:center`.
"""
function text!(c::Canvas, str::AbstractString;
               color::RGBA = c.style.fg, size::Real = c.style.size,
               bold::Bool = false, align::Symbol = :left)
    st = c.style
    setfont!(c; size = size, bold = bold)
    s = String(str)
    x = if align === :right
        c.w - st.pad - advance(c, s)
    elseif align === :center
        (c.w - advance(c, s)) / 2
    else
        st.pad
    end
    Cairo.move_to(c.cr, x, c.y + ascent(c))
    setcolor!(c.cr, color)
    Cairo.show_text(c.cr, s)
    c.y += max(st.line, size * 1.4)
    return c
end

"""
    heading!(c::Canvas, str)

A section title in the accent colour, underlined by a rule.
"""
function heading!(c::Canvas, str::AbstractString)
    text!(c, uppercase(String(str)); color = c.style.accent, bold = true)
    hrule!(c)
    return c
end

"""
    hrule!(c::Canvas; color = c.style.dim)

A hairline across the panel's content width.
"""
function hrule!(c::Canvas; color::RGBA = c.style.dim)
    st = c.style
    y = round(c.y - st.line / 3) + 0.5     # half-pixel keeps the line crisp
    Cairo.new_path(c.cr)
    Cairo.move_to(c.cr, st.pad, y)
    Cairo.line_to(c.cr, c.w - st.pad, y)
    setcolor!(c.cr, (color[1], color[2], color[3], color[4] * 0.45))
    Cairo.set_line_width(c.cr, 1.0)
    Cairo.stroke(c.cr)
    c.y += 4
    return c
end

"""
    kv!(c::Canvas, key, value; keycolor, valuecolor)

A label on the left and a value flushed right — the workhorse row for a
status panel.
"""
function kv!(c::Canvas, key::AbstractString, value;
             keycolor::RGBA = c.style.dim, valuecolor::RGBA = c.style.fg)
    st = c.style
    setfont!(c)
    base = c.y + ascent(c)
    v = string(value)

    Cairo.move_to(c.cr, st.pad, base)
    setcolor!(c.cr, keycolor)
    Cairo.show_text(c.cr, String(key))

    Cairo.move_to(c.cr, c.w - st.pad - advance(c, v), base)
    setcolor!(c.cr, valuecolor)
    Cairo.show_text(c.cr, v)

    c.y += st.line
    return c
end

"""
    bar!(c::Canvas, label, frac; color, height, showpct)

A labelled progress bar. `frac` is clamped to `0..1`.
"""
function bar!(c::Canvas, label::AbstractString, frac::Real;
              color::RGBA = c.style.accent, height::Real = 6.0,
              showpct::Bool = true)
    st = c.style
    f = clamp(Float64(frac), 0.0, 1.0)
    showpct ? kv!(c, label, string(round(Int, 100f), "%")) :
              text!(c, label; color = st.dim)

    w = content_width(c)
    Cairo.rectangle(c.cr, st.pad, c.y, w, Float64(height))
    setcolor!(c.cr, (st.dim[1], st.dim[2], st.dim[3], 0.22))
    Cairo.fill(c.cr)

    if f > 0
        Cairo.rectangle(c.cr, st.pad, c.y, w * f, Float64(height))
        setcolor!(c.cr, color)
        Cairo.fill(c.cr)
    end

    c.y += height + 8
    return c
end

"""
    sparkline!(c::Canvas, values; height, color, lo, hi)

A filled line chart of `values` across the panel's content width. `lo` and
`hi` fix the vertical scale; by default it tracks the data.
"""
function sparkline!(c::Canvas, values;
                    height::Real = 34.0, color::RGBA = c.style.accent,
                    lo::Union{Nothing,Real} = nothing,
                    hi::Union{Nothing,Real} = nothing)
    v = Float64[float(x) for x in values]
    isempty(v) && return c

    st = c.style
    w  = content_width(c)
    y1 = c.y + height
    vlo = lo === nothing ? minimum(v) : Float64(lo)
    vhi = hi === nothing ? maximum(v) : Float64(hi)
    span = vhi - vlo
    span ≈ 0 && (span = 1.0)

    n = length(v)
    px(i) = st.pad + (n == 1 ? w : w * (i - 1) / (n - 1))
    py(t) = y1 - height * clamp((t - vlo) / span, 0.0, 1.0)

    # Wash under the curve first, then the curve on top of it.
    Cairo.new_path(c.cr)
    Cairo.move_to(c.cr, px(1), y1)
    for i in 1:n
        Cairo.line_to(c.cr, px(i), py(v[i]))
    end
    Cairo.line_to(c.cr, px(n), y1)
    Cairo.close_path(c.cr)
    setcolor!(c.cr, (color[1], color[2], color[3], 0.18))
    Cairo.fill(c.cr)

    Cairo.new_path(c.cr)
    for i in 1:n
        i == 1 ? Cairo.move_to(c.cr, px(i), py(v[i])) :
                 Cairo.line_to(c.cr, px(i), py(v[i]))
    end
    setcolor!(c.cr, color)
    Cairo.set_line_width(c.cr, 1.5)
    Cairo.stroke(c.cr)

    c.y = y1 + 8
    return c
end
