using StatusWindows
using MathTeXEngine
using StatusWindows: Canvas, content_width, ascent, advance, paint_background!
using Cairo
using Test

# The drawing layer is exercised against a bare Cairo surface: no window, no
# GL context, so this runs on a headless CI machine. Anything that needs a
# real panel lives in examples/demo.jl instead.
function testcanvas(w = 240, h = 400; style = Style())
    buf = zeros(UInt32, w, h)
    surface = Cairo.CairoImageSurface(buf, Cairo.FORMAT_ARGB32; flipxy = false)
    cr = CairoContext(surface)
    return buf, surface, Canvas(cr, style, w, h)
end

painted(buf) = count(!=(0), buf)

@testset "StatusWindows.jl" begin

    @testset "surface layout" begin
        # The whole blit path assumes a (width, height) column-major buffer
        # that Cairo writes into directly. flipxy would transpose and copy.
        buf = zeros(UInt32, 7, 3)
        s = Cairo.CairoImageSurface(buf, Cairo.FORMAT_ARGB32; flipxy = false)
        @test Cairo.width(s) == 7
        @test Cairo.height(s) == 3
        @test s.data === buf
    end

    @testset "canvas geometry" begin
        _, _, c = testcanvas(240, 400)
        st = c.style
        @test content_width(c) == 240 - 2 * st.pad
        @test (c.x, c.y) == (st.pad, st.pad)
        at!(c, 10, 20)
        @test (c.x, c.y) == (10.0, 20.0)
        spacer!(c, 5)
        @test c.y == 25.0
    end

    @testset "widgets advance the cursor and mark the surface" begin
        buf, _, c = testcanvas()
        for (name, f) in [
            "text"      => c -> text!(c, "hello"),
            "kv"        => c -> kv!(c, "load", "0.42"),
            "heading"   => c -> heading!(c, "system"),
            "bar"       => c -> bar!(c, "cpu", 0.5),
            "sparkline" => c -> sparkline!(c, [1, 4, 2, 8, 5]),
            "hrule"     => c -> hrule!(c),
        ]
            before_y, before_px = c.y, painted(buf)
            f(c)
            @testset "$name" begin
                @test c.y > before_y
                @test painted(buf) > before_px
            end
        end
    end

    @testset "poor man's math" begin
        buf, _, c = testcanvas()

        y, px = c.y, painted(buf)
        poormansmath!(c, "\\sigma^2 = 0.37")
        @test c.y > y
        @test painted(buf) > px

        # Cairo's token table turns commands into Unicode, and _/^ into
        # real Pango sub/superscripts.
        markup = Cairo.tex2pango("x_i^2 + \\alpha", 13.0)
        @test occursin("<sub>", markup)
        @test occursin("<sup>", markup)
        @test occursin("α", markup)
        @test !occursin("\\alpha", markup)

        # Braces group rather than leaking into the output.
        grouped = Cairo.tex2pango("x_{i+1}", 13.0)
        @test occursin("i+1", grouped)
        @test !occursin("{", grouped)

        @test poormansmathwidth(c, "\\sum_{i=1}^n x_i") > poormansmathwidth(c, "x")
        @test poormansmath!(c, "\\infty"; align = :right) === c
        @test poormansmath!(c, "\\mu \\pm 2\\sigma"; align = :center) === c
    end

    @testset "font metrics" begin
        _, _, c = testcanvas()
        StatusWindows.setfont!(c)
        @test ascent(c) > 0
        @test advance(c, "mmmm") > advance(c, "m")
        @test advance(c, "") == 0
    end

    @testset "bar clamps out-of-range fractions" begin
        _, _, c = testcanvas()
        for f in (-1.0, 0.0, 0.5, 1.0, 2.0)
            @test bar!(c, "x", f) === c
        end
    end

    @testset "sparkline edge cases" begin
        _, _, c = testcanvas()
        y = c.y
        @test sparkline!(c, Float64[]) === c
        @test c.y == y                         # empty data draws nothing
        @test sparkline!(c, [3.0]) === c       # single point
        @test sparkline!(c, [2.0, 2.0]) === c  # zero span must not divide by 0
    end

    @testset "background respects style" begin
        # A fully transparent background must leave the buffer untouched.
        buf, surface, c = testcanvas(64, 64; style = Style(bg = (0.0, 0.0, 0.0, 0.0)))
        paint_background!(c.cr, c.style, 64, 64)
        Cairo.finish(surface)
        @test painted(buf) == 0

        buf, surface, c = testcanvas(64, 64; style = Style(bg = (1.0, 0.0, 0.0, 1.0)))
        paint_background!(c.cr, c.style, 64, 64)
        Cairo.finish(surface)
        @test painted(buf) > 0
    end

    @testset "font discovery" begin
        fams = fontfamilies()
        @test !isempty(fams)
        @test issorted(fams)
        @test fams === fontfamilies()          # cached, same object back
        @test !("Nonexistent Font XYZ" in fams)

        # Empty mathfont auto-selects: a known math font when one is
        # installed, otherwise the body font. Both are valid outcomes, so
        # assert the invariant rather than a specific family.
        st = Style()
        chosen = StatusWindows.mathfontof(st)
        @test chosen in StatusWindows.MATH_FONTS ||
              chosen == StatusWindows.fontof(st)

        # An explicitly named font is honoured verbatim...
        @test StatusWindows.mathfontof(Style(mathfont = "DejaVu Sans")) == "DejaVu Sans"
        # ...but a missing one warns rather than silently substituting.
        @test_logs (:warn, r"not installed") StatusWindows.mathfontof(
            Style(mathfont = "Nonexistent Font XYZ"))
    end

    @testset "body font selection" begin
        # The default is empty and resolves per platform, so that one Style
        # renders on Linux, macOS and Windows without naming a font only one
        # of them ships.
        @test Style().font == ""
        # Installed or not, the result is always one of the candidates.
        @test StatusWindows.fontof(Style()) in StatusWindows.BODY_FONTS

        # On this machine at least one candidate should really be installed.
        @test any(in(fontfamilies()), StatusWindows.BODY_FONTS)

        # Same request-vs-preference rule as the math font.
        @test StatusWindows.fontof(Style(font = "DejaVu Sans")) == "DejaVu Sans"
        @test_logs (:warn, r"not installed") StatusWindows.fontof(
            Style(font = "Nonexistent Body Font XYZ"))
    end

    @testset "render to file" begin
        content = c -> (heading!(c, "report"); kv!(c, "n", 1024); bar!(c, "cpu", 0.4))

        mktempdir() do dir
            for ext in ("pdf", "svg", "png")
                path = joinpath(dir, "panel." * ext)
                @test render(content, path; width = 300, height = 200) == path
                @test filesize(path) > 0
            end

            # PDF keeps live text rather than outlining it.
            pdf = read(joinpath(dir, "panel.pdf"), String)
            @test startswith(pdf, "%PDF")

            svg = read(joinpath(dir, "panel.svg"), String)
            @test occursin("<svg", svg)

            @test_throws ArgumentError render(content, joinpath(dir, "x.docx"))
        end
    end

    @testset "printstyle" begin
        ps = printstyle()
        @test ps.bg == (1.0, 1.0, 1.0, 1.0)     # opaque white for paper
        @test ps.fg[1] < 0.5                    # dark ink
        @test ps.radius == 0.0
        @test printstyle(size = 9.0).size == 9.0
    end

    @testset "MathTeXEngine extension" begin
        @test Base.get_extension(StatusWindows, :StatusWindowsMathTeXExt) !== nothing

        buf, _, c = testcanvas()
        y, px = c.y, painted(buf)
        math!(c, raw"\frac{\alpha}{\beta}")
        @test c.y > y
        @test painted(buf) > px

        # Real layout: a fraction is taller than its numerator alone, and a
        # sum with limits is taller than a bare sigma.
        _, _, c2 = testcanvas()
        tall = let y0 = c2.y; math!(c2, raw"\frac{\alpha}{\beta}"); c2.y - y0 end
        _, _, c3 = testcanvas()
        flat = let y0 = c3.y; math!(c3, raw"\alpha"); c3.y - y0 end
        @test tall > flat

        @test mathwidth(c, raw"\frac{1}{2}") > 0
        @test mathwidth(c, raw"xxxxx") > mathwidth(c, raw"x")
        @test math!(c, raw"\sqrt{x^2}"; align = :right) === c
        @test math!(c, raw"\int_0^\infty"; align = :center) === c
    end

    @testset "Style is constructible and overridable" begin
        s = Style(size = 20.0, fg = (1.0, 0.0, 0.0, 1.0))
        @test s.size == 20.0
        @test s.fg == (1.0, 0.0, 0.0, 1.0)
        @test s.font == Style().font   # untouched fields keep defaults
    end
end
