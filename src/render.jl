# Drawing a panel to a file instead of to the screen.
#
# Nothing in the widget layer knows it is talking to a window, so pointing
# the same content function at a PDF or SVG surface is all it takes. The
# result is real vector output with live text, not a screenshot, and it
# needs no window, GL context or display -- so it also works on CI.

"""
    printstyle(; kwargs...) -> Style

A [`Style`](@ref) for paper: white ground, dark ink, square corners.

The on-screen default is a dark translucent panel designed to sit on a
wallpaper; on paper that is an ink-hungry black rectangle, and the
transparency flattens to white anyway. Keyword arguments override
individual fields as usual.
"""
printstyle(; kwargs...) = Style(;
    bg     = (1.00, 1.00, 1.00, 1.00),
    fg     = (0.10, 0.12, 0.15, 1.00),
    dim    = (0.42, 0.45, 0.50, 1.00),
    accent = (0.00, 0.35, 0.60, 1.00),
    warn   = (0.70, 0.35, 0.05, 1.00),
    radius = 0.0,
    kwargs...)

"""
    render(content, path; width, height, style) -> path
    render(p::Panel, path; width, height, style) -> path

Draw to a file. The format comes from the extension: `.pdf`, `.svg`,
`.eps`/`.ps` give vector output with selectable text, `.png` gives a
bitmap.

```julia
render(p, "panel.pdf")                       # a live panel's content
render("panel.svg"; width = 300) do c        # or any draw function
    heading!(c, "report")
    kv!(c, "n", 1024)
end
```

Vector surfaces measure in points (1/72 inch), so a 300×220 render is
about 4.2×3.1 inches on paper. Defaults to [`printstyle`](@ref) rather
than the panel's own dark palette; pass `style` to override.
"""
function render(content, path::AbstractString;
                width::Real = 300, height::Real = 220,
                style::Style = printstyle())
    ext = lowercase(splitext(path)[2])
    surface = if ext == ".pdf"
        Cairo.CairoPDFSurface(path, width, height)
    elseif ext == ".svg"
        Cairo.CairoSVGSurface(path, width, height)
    elseif ext in (".eps", ".ps")
        Cairo.CairoEPSSurface(path, width, height)
    elseif ext == ".png"
        Cairo.CairoARGBSurface(width, height)
    else
        throw(ArgumentError("""
            StatusWindows: cannot render "$ext". Use .pdf, .svg, .eps, .ps \
            or .png."""))
    end

    cr = CairoContext(surface)
    paint_background!(cr, style, width, height)
    content(Canvas(cr, style, width, height))

    # Raster surfaces need an explicit write; vector ones flush on finish.
    ext == ".png" && Cairo.write_to_png(surface, path)
    Cairo.finish(surface)
    return path
end

function render(p::Panel, path::AbstractString;
                width::Real = p.w, height::Real = p.h,
                style::Style = printstyle())
    p.content === nothing &&
        throw(ArgumentError("StatusWindows: this panel has no content; call draw! first"))
    return render(p.content, path; width = width, height = height, style = style)
end
