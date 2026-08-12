# Colors, fonts and the drawing cursor.

const RGBA = NTuple{4,Float64}

# --- font discovery -----------------------------------------------------

const _FAMILIES = Ref{Union{Nothing,Vector{String}}}(nothing)
const _WARNED = Set{String}()

"""
    fontfamilies() -> Vector{String}

Every font family Pango can actually use on this machine, sorted.

This is the list that matters for the body font and for
[`poormansmath!`](@ref): families are resolved by name through fontconfig,
and a name that is not on this list gets silently substituted rather than
raising. Cached after the first call.
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
are, [`poormansmath!`](@ref) falls back to the panel's body font, which
still renders Greek and the common operators.
"""
const MATH_FONTS = ["STIX Two Math", "Latin Modern Math", "TeX Gyre Termes Math",
                    "TeX Gyre Pagella Math", "DejaVu Math TeX Gyre",
                    "Noto Sans Math", "Asana Math"]

"""
Monospaced body fonts worth using, best first, one list per platform.

There is no font every system has, so naming a single default would leave
two platforms out of three rendering in whatever fontconfig felt like
substituting. Each list starts with the face that ships with that system:
DejaVu on Linux, Menlo on macOS (present since 10.6), Consolas on Windows.
"""
const BODY_FONTS = Sys.isapple()   ? ["Menlo", "Monaco", "Courier New"] :
                   Sys.iswindows() ? ["Consolas", "Cascadia Mono", "Courier New"] :
                                     ["DejaVu Sans Mono", "Liberation Mono",
                                      "Noto Sans Mono", "FreeMono"]

"""
    Style(; kwargs...)

Appearance of a [`Panel`](@ref): colors, font and spacing. Colors are
`(r, g, b, a)` tuples with components in `0..1`.

The defaults are a dark translucent panel with light text. `bg`'s alpha is
what makes the panel see-through, so drop it to `0.0` for the classic conky
look where only the text floats over the wallpaper.

`font` and `mathfont` are empty by default, which means "pick the best
installed one" — see [`fontof`](@ref) and [`mathfontof`](@ref).
"""
Base.@kwdef struct Style
    font::String        = ""                        # "" selects automatically
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

# Naming a font explicitly is a request rather than a preference, so a
# missing one warns instead of quietly turning into something else.
function _requested(name::AbstractString, kind::AbstractString)
    if !(name in fontfamilies()) && !(name in _WARNED)
        push!(_WARNED, name)
        @warn """$kind font "$name" is not installed; fontconfig will \
                 substitute something else. See fontfamilies() for what is \
                 available.""" maxlog=1
    end
    return String(name)
end

# First installed candidate, or the head of the list so fontconfig still
# has something to substitute for when the machine has none of them.
function _firstinstalled(candidates)
    fams = fontfamilies()
    for f in candidates
        f in fams && return f
    end
    return first(candidates)
end

"""
    fontof(st::Style) -> String

Family the text widgets should draw with.

An empty `st.font` means "the best installed entry of [`BODY_FONTS`](@ref)",
which is what lets one `Style` look right on Linux, macOS and Windows
without naming a font that only one of them ships.
"""
fontof(st::Style) =
    isempty(st.font) ? _firstinstalled(BODY_FONTS) : _requested(st.font, "Body")

"""
    mathfontof(st::Style) -> String

Family [`poormansmath!`](@ref) should draw with.

An empty `st.mathfont` means "pick the best installed math font, and fall
back to the body font if there is none" — so a machine with STIX gets STIX
and a bare one still works.
"""
function mathfontof(st::Style)
    isempty(st.mathfont) || return _requested(st.mathfont, "Math")
    fams = fontfamilies()
    for f in MATH_FONTS
        f in fams && return f
    end
    return fontof(st)   # no math font at all: the body font still has Greek
end

"Apply an `RGBA` tuple to the context."
setcolor!(cr::CairoContext, col::RGBA) = set_source_rgba(cr, col...)

"Select the style's font at `size` (defaults to the style's own size)."
function setfont!(c::Canvas; size::Real = c.style.size, bold::Bool = false)
    select_font_face(c.cr, fontof(c.style), Cairo.FONT_SLANT_NORMAL,
                     bold ? Cairo.FONT_WEIGHT_BOLD : Cairo.FONT_WEIGHT_NORMAL)
    set_font_size(c.cr, Float64(size))
    return c
end
