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

    @testset "colors" begin
        # The table is xcolor's svgnames verbatim, so spot-check against
        # values taken from svgnam.def rather than from this package.
        @test length(StatusWindows.SVG_COLORS) == 151
        @test rgba(:Crimson) == (0.864, 0.08, 0.235, 1.0)
        @test rgba(:AliceBlue) == (0.94, 0.972, 1.0, 1.0)
        @test rgba(:YellowGreen) == (0.604, 0.804, 0.196, 1.0)
        # SVG's Green is the dark one; Lime is the bright one.
        @test rgba(:Green) == (0.0, 0.5, 0.0, 1.0)
        @test rgba(:Lime) == (0.0, 1.0, 0.0, 1.0)

        # Case folds, so xcolor's spelling and a lowercase one agree.
        @test rgba(:DarkSlateGray) == rgba(:darkslategray) == rgba(:dArKsLaTeGrAy)
        @test rgba(:Grey) == rgba(:Gray)          # both spellings are svgnames

        # Tuples pass through; a bare triple gains an opaque alpha.
        @test rgba((0.1, 0.2, 0.3, 0.4)) == (0.1, 0.2, 0.3, 0.4)
        @test rgba((0.1, 0.2, 0.3)) == (0.1, 0.2, 0.3, 1.0)
        @test rgba(:transparent) == rgba(:none) == (0.0, 0.0, 0.0, 0.0)
        @test fade(:Crimson, 0.25) == (0.864, 0.08, 0.235, 0.25)

        # Style names resolve against the style in hand, not a fixed color.
        st = Style(accent = :Tomato, warn = :Gold)
        @test rgba(st, :accent) == rgba(:Tomato)
        @test rgba(st, :warn) == rgba(:Gold)
        @test rgba(st, :fg) == st.fg
        @test rgba(st, :Crimson) == rgba(:Crimson)   # falls through to SVG
        @test fade(st, :accent, 0.5) == (rgba(:Tomato)[1:3]..., 0.5)

        # ...but not while the style is still being built, where they cannot.
        @test_throws ArgumentError Style(fg = :accent)
        @test_throws ArgumentError rgba(:NotAColorAtAll)

        @test length(colornames()) == 151 + length(StatusWindows.STYLE_COLORS) + 2
        @test :DeepSkyBlue in colornames()
        @test allunique(colornames())
    end

    @testset "widgets accept color names" begin
        # Every color keyword has to take a name, not just a tuple, and the
        # name has to actually change what lands on the surface.
        for (name, f) in [
            "text"      => (c, col) -> text!(c, "hello"; color = col),
            "kv key"    => (c, col) -> kv!(c, "k", "v"; keycolor = col),
            "kv value"  => (c, col) -> kv!(c, "k", "v"; valuecolor = col),
            "bar"       => (c, col) -> bar!(c, "cpu", 0.6; color = col),
            "sparkline" => (c, col) -> sparkline!(c, [1, 5, 2, 6]; color = col),
            "hrule"     => (c, col) -> hrule!(c; color = col),
            "math"      => (c, col) -> poormansmath!(c, "x^2"; color = col),
        ]
            @testset "$name" begin
                red, _, cr = testcanvas()
                blue, _, cb = testcanvas()
                f(cr, :Red)
                f(cb, :Blue)
                @test painted(red) > 0
                @test red != blue          # the name reached the pixels
                # A name and its tuple must be indistinguishable.
                tup, _, ct = testcanvas()
                f(ct, rgba(:Red))
                @test tup == red
            end
        end

        # :accent follows the style rather than pinning a color.
        a, _, ca = testcanvas(; style = Style(accent = :Tomato))
        b, _, cb = testcanvas(; style = Style(accent = :Tomato))
        text!(ca, "x"; color = :accent)
        text!(cb, "x"; color = :Tomato)
        @test a == b
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

        # An explicitly named font is honored verbatim...
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

    @testset "headless panels are inert" begin
        # hasdisplay only inspects the environment on Linux; elsewhere it
        # defers to window creation and always answers true.
        if Sys.islinux()
            @test withenv(hasdisplay, "DISPLAY" => nothing,
                          "WAYLAND_DISPLAY" => nothing) == false
            @test withenv(hasdisplay, "DISPLAY" => ":0") == true
            @test withenv(hasdisplay, "DISPLAY" => nothing,
                          "WAYLAND_DISPLAY" => "wayland-0") == true
        else
            @test hasdisplay()
        end

        # JULIA_GLFW_PLATFORM=null is the promise that no display is needed;
        # it overrides everything, even a session that has one.
        @test withenv(hasdisplay, "JULIA_GLFW_PLATFORM" => "null") == false

        # Every method has to survive a panel with no window behind it,
        # because that is the whole point: a desktop script runs to the end
        # on a server instead of stopping at the first call.
        p = StatusWindows.inertpanel(Style(), 300, 220)
        @test !isactive(p)
        @test occursin("inert", sprint(show, p))
        @test draw!(c -> text!(c, "never drawn"), p) === p
        @test refresh!(p) === p
        @test run!(p) === nothing
        @test start!(p) === p
        @test p.task === nothing         # no redraw task was ever spawned
        @test stop!(p) === p
        @test move!(p, 10, 10) === p
        @test resize!(p, 100, 100) === p
        @test (p.w, p.h) == (100, 100)   # bookkeeping still updates
        @test close(p) === nothing

        # Constructing one through the public API warns rather than throwing.
        # Clear the platform override: the warning names it when it is set,
        # so leaving it in the environment would change the message.
        if Sys.islinux()
            withenv("DISPLAY" => nothing, "WAYLAND_DISPLAY" => nothing,
                    "JULIA_GLFW_PLATFORM" => nothing) do
                q = @test_logs (:warn, r"no display") Panel()
                @test !isactive(q)
            end
        end

        # When the null platform is the reason, the warning says so rather
        # than claiming there is no display -- which on a desktop would be
        # both false and unhelpful.
        withenv("DISPLAY" => ":0", "JULIA_GLFW_PLATFORM" => "null") do
            q = @test_logs (:warn, r"JULIA_GLFW_PLATFORM=null") Panel()
            @test !isactive(q)
        end
    end

    @testset "GLFW bindings" begin
        G = StatusWindows.GLFW

        # The reason this binding exists: loading the package must not bring
        # a window system up. If this fails, `using StatusWindows` has gone
        # back to needing a display and nothing below matters.
        @test !G.isinitialized()

        # Transcribed from GLFW's header via GLFW.jl; a typo here would be a
        # hint silently applied to the wrong property.
        @test G.PLATFORM == 0x00050003
        @test G.PLATFORM_X11 == 0x00060004
        @test G.DECORATED == 0x00020005
        @test G.FLOATING == 0x00020007
        @test G.TRANSPARENT_FRAMEBUFFER == 0x0002000A
        @test G.MOUSE_PASSTHROUGH == 0x0002000D
        @test G.SCALE_TO_MONITOR == 0x0002200C
        @test G.OPENGL_CORE_PROFILE == 0x00032001
        @test (G.RELEASE, G.PRESS) == (0, 1)
        @test G.KEY_ESCAPE == 256

        @test G.platformcode("x11") == G.PLATFORM_X11
        @test G.platformcode("wayland") == G.PLATFORM_WAYLAND
        @test G.platformcode("null") == G.PLATFORM_NULL
        @test G.platformcode("nonsense") == G.ANY_PLATFORM

        # An explicit request beats force_x11; without one, X11 is asked for
        # only on a Linux box that has an X display to ask about.
        withenv("JULIA_GLFW_PLATFORM" => "wayland") do
            @test StatusWindows.platformchoice(true) == G.PLATFORM_WAYLAND
        end
        withenv("JULIA_GLFW_PLATFORM" => nothing, "DISPLAY" => ":0") do
            @test StatusWindows.platformchoice(true) ==
                  (Sys.islinux() ? G.PLATFORM_X11 : G.ANY_PLATFORM)
            @test StatusWindows.platformchoice(false) == G.ANY_PLATFORM
        end
        withenv("JULIA_GLFW_PLATFORM" => nothing, "DISPLAY" => nothing) do
            @test StatusWindows.platformchoice(true) == G.ANY_PLATFORM
        end

        # The callback registry, exercised on a handle no window owns: this
        # is the Julia half of the path GLFW drives, and it needs no display.
        handle = Ptr{Cvoid}(UInt(0xbeef))
        window = G.Window(handle)
        @test occursin("beef", sprint(show, window))
        @test occursin("null", sprint(show, G.Window(C_NULL)))

        seen = Any[]
        G.register!(window)
        G.callbacks(window).key = (win, args...) -> push!(seen, (win, args))
        G.dispatch(handle, :key, Cint(65), Cint(0), G.PRESS, Cint(0))
        @test length(seen) == 1
        @test seen[1][1] == window
        @test seen[1][2] == (65, 0, 1, 0)

        # Callbacks that were never set, and events for windows that are
        # gone, have to be quiet rather than throwing: GLFW is calling, and
        # an exception reaching it would abort the process.
        @test G.dispatch(handle, :cursorpos, 1.0, 2.0) === nothing
        G.callbacks(window).key = (_...) -> error("boom")
        @test_logs (:error, r"callback threw") G.dispatch(handle, :key, Cint(1),
                                                          Cint(0), G.PRESS, Cint(0))
        G.unregister!(window)
        @test G.dispatch(handle, :key, Cint(1), Cint(0), G.PRESS, Cint(0)) === nothing
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
