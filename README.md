# StatusWindows.jl

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://NittanyLion.github.io/StatusWindows.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://NittanyLion.github.io/StatusWindows.jl/dev/)
[![Build Status](https://github.com/NittanyLion/StatusWindows.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/NittanyLion/StatusWindows.jl/actions/workflows/CI.yml?query=branch%3Amain)
![authored by: JP](authored_by.svg)

A lightweight package to generate borderless, always-on-top desktop panels you fill with your own content (including choosing colors as in the latex svgnames package and full math) — a conky-like window, driven from Julia.

This package is still under development, so please advise of any infelicities.


```julia
using StatusWindows

p = Panel(width = 280, height = 300, x = 60, y = 60)

draw!(p) do c
    heading!(c, "system")
    kv!(c, "host", gethostname())
    bar!(c, "cpu", 0.62)
    sparkline!(c, history; lo = 0.0, hi = 1.0, color = :Tomato)
end

run!(p, refresh = 1.0)
```

See `examples/demo.jl` for a working system monitor built on `Sys.cpu_info`,
`Sys.free_memory` and friends, and `examples/showcase.jl` for one panel that
exercises everything at once — widgets, styling, both math paths and file
export:

```julia
julia --project=. examples/showcase.jl              # live panel
julia --project=. examples/showcase.jl out.pdf      # render to a file
```


## Filling it with your own stuff

`draw!` takes a function of one argument, a `Canvas`. It runs on every tick,
so read your data inside it:

```julia
draw!(p) do c
    heading!(c, "gpu")
    for (i, t) in enumerate(read_gpu_temps())
        bar!(c, "gpu$i", t / 100; color = t > 80 ? c.style.warn : c.style.accent)
    end

    # Anything Cairo can draw:
    Cairo.arc(c.cr, c.w / 2, c.y + 40, 30, 0, 2π)
    Cairo.set_source_rgba(c.cr, 1, 1, 1, 0.3)
    Cairo.stroke(c.cr)
end
```


## Styling

Colors, font and spacing come from `Style`:

```julia
Panel(style = Style(font = "Iosevka", size = 12.0, bg = (0.0, 0.0, 0.0, 0.0)))
```

`font` defaults to empty, which means "the first installed monospaced face
for this platform" — DejaVu Sans Mono on Linux, Menlo on macOS, Consolas on
Windows — so one `Style` renders sensibly everywhere instead of naming a
font that only one system ships. `fontfamilies()` lists what Pango can
actually use here.

A `bg` alpha of `0.0` gives the classic conky look, where only the text
floats over the wallpaper.


## Colors

Anywhere a color is taken, a name works as well as an `(r, g, b, a)` tuple:

```julia
text!(c, "hot";  color = :Crimson)
bar!(c, "cpu", 0.6; color = :DeepSkyBlue)
hrule!(c; color = :DarkSlateGray)
Panel(style = Style(bg = :MidnightBlue, accent = :Gold))
```

The palette is the 151 SVG names from LaTeX xcolor's `svgnames` option, with
xcolor's own values, so a panel and a paper agree on what `Crimson` is.
Names match case-insensitively — `:DeepSkyBlue` and `:deepskyblue` are the
same color — and `colornames()` lists everything. Note that SVG's `:Green`
is the dark `(0, 0.5, 0)`; `:Lime` is the bright one.

Five extra names follow the panel's own theme rather than fixing a color:
`:fg`, `:dim`, `:accent`, `:warn` and `:bg`. Restyle the panel and anything
drawn with `color = :accent` moves with it. `:transparent` draws nothing,
and `fade(:Crimson, 0.3)` is the same color at another opacity.


## Math

`math!` typesets real TeX — fractions, radicals, limits stacked over big
operators:

```julia
using StatusWindows, MathTeXEngine   # both, in either order

draw!(p) do c
    heading!(c, "estimates")
    math!(c, raw"\frac{\alpha}{\beta} + \sqrt{x^2}")
    math!(c, raw"\sum_{i=1}^{n} x_i^2")
    math!(c, raw"\hat{\beta} = (X^TX)^{-1}X^Ty")
end
```

[MathTeXEngine.jl](https://github.com/Kolaru/MathTeXEngine.jl) is a **weak
dependency**: it is not installed with this package, and `math!` does not
exist until you load it — at which point a package extension supplies it.
`mathwidth` gives the pixel width it would need, for laying things out by
hand.

It is also the *portable* path, which is not obvious for the heavier of
two options. MathTeXEngine ships its own fonts and rasterizes through
FreeType, so it bypasses fontconfig entirely and renders identically on a
machine with no math fonts installed at all.

### Without the dependency

`poormansmath!` draws LaTeX-ish notation using nothing but Cairo: `_` and
`^` become real subscripts and superscripts, and a few hundred commands map
to their Unicode characters.

```julia
draw!(p) do c
    poormansmath!(c, "\\sigma^2 = 0.37")
    poormansmath!(c, "\\sum_{i=1}^n x_i \\leq \\infty")
    poormansmath!(c, "p \\ll 0.01"; color = c.style.accent, align = :right)
end
```

The name is a warning. This runs on Pango markup, not a TeX engine, which
sets the ceiling:

* **Works** — sub/superscripts with grouping, Greek, relations, arrows,
  set and logic symbols, most binary operators.
* **Does not** — fractions, radicals, matrices, limits stacked over a big
  operator, or any real math spacing.
* **Fails quietly** — a command outside the table is emitted verbatim, so
  `\hat\beta` draws the literal text `\hat` followed by β. Nothing errors.
  Check with `Cairo.tex2pango(s, size)` if unsure.
* **Depends on the machine** — it asks fontconfig for a math font by name,
  so the same code looks different on a box that has STIX and one that
  does not.

For simple readouts, raw Unicode is often less trouble than markup —
`text!(c, "σ² = 0.37")` needs no escaping, and the Julia REPL's LaTeX
completions (`\sigma<tab>`) type the characters for you.
`poormansmathwidth` is the matching width function.

`poormansmath!` picks its font automatically: the best installed math font
(STIX Two Math, Latin Modern Math, ...), falling back to the panel's body
font when none is present. `Style(mathfont = "...")` overrides that — and
because naming a font is a request rather than a preference, naming one you
do not have warns instead of silently substituting.


## Printing and export

Nothing in the drawing layer knows it is talking to a screen, so the same
content function can be aimed at a file:

```julia
render(p, "panel.pdf")                    # a live panel's content
render("report.svg"; width = 300) do c    # or any draw function
    heading!(c, "report")
    kv!(c, "n", 1024)
end
```

`.pdf`, `.svg` and `.eps`/`.ps` give real vector output with **live,
selectable text** — not a screenshot — and `.png` gives a bitmap. No
window, GL context or display is involved, so this works headless and on
CI. Vector surfaces measure in points, so a 300×220 render is about
4.2×3.1 inches.

`render` defaults to `printstyle()`: white ground, dark ink, square
corners. The on-screen palette is designed to sit on a wallpaper and turns
into an ink-hungry black rectangle on paper.


## Controls

Drag the panel with the left mouse button (`movable = true`, the default);
Escape closes it. Pass `passthrough = true` to let clicks fall through to
whatever is underneath — that also disables dragging.

`start!` runs the panel on a task so the REPL stays usable; `stop!` ends it.


## Machines with no display

A script written for a desktop should not fall over when it lands on a
server. Where there is no display, `Panel` warns once and returns an inert
panel: `draw!`, `run!`, `start!`, `move!` and the rest all accept it and do
nothing, so the script runs to the end and whatever else it does still
happens. `hasdisplay()` is the test, `isactive(p)` reports what you got.

```julia
p = Panel()             # warns on a headless box, throws nowhere
draw!(p) do c
    kv!(c, "load", string(Sys.loadavg()[1]))
end
run!(p)                 # returns immediately if there is no display
```

There is nothing to configure and no environment variable to remember.
`using StatusWindows` touches no window system: GLFW is started by the first
`Panel` that wants one, and if it will not start — no display, a stale
`DISPLAY`, a session that hands out no connection, missing libraries — that
is a warning and an inert panel, not an exception. The whole test suite runs
this way, and so does CI, on a runner with no X server at all.

`JULIA_GLFW_PLATFORM` is still read, and still means what it means to
GLFW.jl: it names the backend to ask for — `x11`, `wayland`, `cocoa`,
`win32` — and `null` forces inert panels even on a machine that does have a
display, which is a way to silence panels in a script you would rather not
edit.

To run real windows on a machine without one, start an Xvfb and point
`DISPLAY` at it.


## Platform notes

These are the sharp edges. They are properties of the window systems, not of
this package.

**Linux / Wayland.** GLFW's Wayland backend cannot position its own windows:
the compositor decides placement and `SetWindowPos` is a silent no-op, so
`x` and `y` would be ignored. `Panel` therefore requests GLFW's **X11**
backend on Linux, which routes through XWayland on a Wayland session and
makes placement work. Pass `force_x11 = false` to opt out — and expect the
panel to land wherever the compositor likes.

**HiDPI.** All geometry — `width`, `height`, `x`, `y`, `move!`, `resize!` —
is in logical pixels, so a panel comes out roughly the same physical size on
a 96 dpi monitor and on a 240 dpi one. `Panel` asks the window system for the
monitor's content scale and draws at full device resolution, so text stays
sharp rather than being magnified. Pass `scale = 1` to work in raw device
pixels, or any other number to pin the factor yourself.

**Transparency** requires a running compositor and is the one feature that
occasionally no-ops on unusual drivers. Design the panel to look right
opaque and treat transparency as a bonus; `Panel(transparent = false)` if
you would rather not depend on it.

**Taskbar.** There is no GLFW hint for "skip taskbar", so on some desktops
the panel shows up in the window list. Hiding it needs per-platform window
manager calls that this package does not make.

**What has actually been tested.** Linux under XWayland: positioning,
rendering, dragging and clean shutdown all verified by hand. CI runs the
suite on Linux (Julia 1.10 through nightly), macOS on Apple Silicon, and
Windows, so the package loads, the Cairo drawing layer works and the body
font resolves on all three.

What CI does *not* prove is that a window appears: the tests deliberately
draw into a bare image surface and never open one. So on macOS and Windows,
whether the panel actually floats, accepts a drag, and honors transparency
and click-through is still unverified. Reports welcome.


## How it works

A panel is a [GLFW](https://www.glfw.org) window with its decorations turned
off. On every tick the whole panel is drawn into a [Cairo](https://cairographics.org)
image surface, which is then handed to the GPU as a single texture and
stretched over one triangle. That keeps the whole thing to two small
dependencies and makes the drawing API just *Cairo* — `c.cr` is a plain
`CairoContext`, so anything Cairo can do, a panel can do.

The widgets (`heading!`, `kv!`, `bar!`, `sparkline!`, `text!`, `hrule!`,
`spacer!`) are conveniences that draw at a cursor and advance it. They are
not privileged; mix them freely with raw Cairo calls.

GLFW is called directly, through the bindings in `src/glfw/` — about two
hundred lines covering the twenty-odd entry points a panel uses, and nothing
else. That is what makes the paragraph above about headless machines true:
the package decides for itself when GLFW comes up and what happens when it
will not. Those bindings were written by borrowing from
[GLFW.jl](https://github.com/JuliaGL/GLFW.jl), which is the reference for
calling this library from Julia; `src/glfw/NOTICE.md` records what came from
where, and its MIT license. The library itself still arrives as a binary
from `GLFW_jll`, unchanged.


## Installation

```julia
using Pkg
Pkg.add("StatusWindows")
```

## Disclaimer

This package was written with significant assistance from Claude.

