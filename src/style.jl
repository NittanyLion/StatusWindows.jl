# Colours, fonts and the drawing cursor.

const RGBA = NTuple{4,Float64}

# --- font discovery -----------------------------------------------------

const _FAMILIES = Ref{Union{Nothing,Vector{String}}}(nothing)
const _WARNED = Set{String}()

"""
    fontfamilies() -> Vector{String}

Every font family Pango can actually use on this machine, sorted.

This is the list that matters for [`math!`](@ref): Pango resolves families
by name through fontconfig, and a name that is not on this list gets
silently substituted rather than raising. Cached after the first call.
"""
function fontfamilies()
    _FAMILIES[] === nothing || return _FAMILIES[]
    fm = ccall((:pango_cairo_font_map_get_default, Cairo.libpangocairo),
               Ptr{Nothing}, ())
    ref = Ref{Ptr{Ptr{Nothing}}}()
    n = Ref{Cint}(0)
    ccall((:pango_font_map_list_families, Cairo.libpango), Nothing,
          (Ptr{Nothing}, Ptr{Ptr{Ptr{Nothing}}}, Ptr{Cint}), fm, ref, n)
    names = String[unsafe_string(ccall((:pango_font_family_get_name, Cairo.libpango),
                                       Cstring, (Ptr{Nothing},), f))
                   for f in unsafe_wrap(Array, ref[], n[])]
    ccall((:g_free, Cairo.libglib), Nothing, (Ptr{Nothing},), ref[])
    return _FAMILIES[] = sort!(names)
end

"""
Math fonts worth using, best first. Whichever is installed wins; if none
are, [`math!`](@ref) falls back to the panel's body font, which still
renders Greek and the common operators.
"""
const MATH_FONTS = ["STIX Two Math", "Latin Modern Math", "TeX Gyre Termes Math",
                    "TeX Gyre Pagella Math", "DejaVu Math TeX Gyre",
                    "Noto Sans Math", "Asana Math"]

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
    mathfont::String    = ""                        # "" selects automatically
    size::Float64       = 13.0
    fg::RGBA            = (0.88, 0.92, 0.96, 1.0)   # body text
    dim::RGBA           = (0.55, 0.61, 0.70, 1.0)   # labels, rules
    accent::RGBA        = (0.95, 0.65, 0.25, 1.0)   # bars, headings
    warn::RGBA          = (0.93, 0.35, 0.22, 1.0)   # must not read as accent
    bg::RGBA            = (0.09, 0.065, 0.04, 0.85) # panel background
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

"""
    mathfontof(st::Style) -> String

Family [`math!`](@ref) should draw with.

An empty `st.mathfont` means "pick the best installed math font, and fall
back to the body font if there is none" — so a machine with STIX gets STIX
and a bare one still works. Naming a font explicitly is a request rather
than a preference, so a missing one warns (once) instead of silently
substituting.
"""
function mathfontof(st::Style)
    if !isempty(st.mathfont)
        if !(st.mathfont in fontfamilies()) && !(st.mathfont in _WARNED)
            push!(_WARNED, st.mathfont)
            @warn """Math font "$(st.mathfont)" is not installed; fontconfig \
                     will substitute something else. See fontfamilies() for \
                     what is available.""" maxlog=1
        end
        return st.mathfont
    end
    fams = fontfamilies()
    for f in MATH_FONTS
        f in fams && return f
    end
    return st.font
end

"Apply an `RGBA` tuple to the context."
setcolor!(cr::CairoContext, col::RGBA) = set_source_rgba(cr, col...)

"Select the style's font at `size` (defaults to the style's own size)."
function setfont!(c::Canvas; size::Real = c.style.size, bold::Bool = false)
    select_font_face(c.cr, c.style.font, Cairo.FONT_SLANT_NORMAL,
                     bold ? Cairo.FONT_WEIGHT_BOLD : Cairo.FONT_WEIGHT_NORMAL)
    set_font_size(c.cr, Float64(size))
    return c
end
