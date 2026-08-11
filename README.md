# StatusWindows

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://NittanyLion.github.io/StatusWindows.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://NittanyLion.github.io/StatusWindows.jl/dev/)
[![Build Status](https://github.com/NittanyLion/StatusWindows.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/NittanyLion/StatusWindows.jl/actions/workflows/CI.yml?query=branch%3Amain)

Borderless, always-on-top desktop panels you fill with your own content — a
conky-like window, driven from Julia.

```julia
using StatusWindows

p = Panel(width = 280, height = 300, x = 60, y = 60)

draw!(p) do c
    heading!(c, "system")
    kv!(c, "host", gethostname())
    bar!(c, "cpu", 0.62)
    sparkline!(c, history; lo = 0.0, hi = 1.0)
end

run!(p, refresh = 1.0)
```

See `examples/demo.jl` for a working system monitor built on `Sys.cpu_info`,
`Sys.free_memory` and friends.

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

## Math

`math!` draws LaTeX-ish notation: `_` and `^` become real subscripts and
superscripts, and a few hundred commands map to their Unicode characters.

```julia
draw!(p) do c
    heading!(c, "estimates")
    math!(c, "\\sigma^2 = 0.37")
    math!(c, "\\sum_{i=1}^n x_i \\leq \\infty")
    math!(c, "x_{i+1}^{2n} \\to \\theta")
    math!(c, "p \\ll 0.01"; color = c.style.accent, align = :right)
end
```

This runs on Pango markup, not a TeX engine, which sets the ceiling:

* **Works** — sub/superscripts with grouping, Greek, relations, arrows,
  set and logic symbols, most binary operators.
* **Does not** — fractions, radicals, matrices, limits stacked over a big
  operator, or any real math spacing.
* **Fails quietly** — a command outside the table is emitted verbatim, so
  `\hat\beta` draws the literal text `\hat` followed by β. Nothing errors.
  Check with `Cairo.tex2pango(s, size)` if unsure.

For simple readouts, raw Unicode is often less trouble than markup —
`text!(c, "σ² = 0.37")` needs no escaping, and the Julia REPL's LaTeX
completions (`\sigma<tab>`) type the characters for you. `mathwidth` gives
the pixel width `math!` would need, for laying things out by hand.

`math!` picks its font automatically: the best installed math font
(STIX Two Math, Latin Modern Math, ...), falling back to the panel's body
font when none is present, so it works everywhere and looks better where
it can. `Style(mathfont = "...")` overrides that — and because naming a
font is a request rather than a preference, naming one you do not have
warns instead of silently substituting. `fontfamilies()` lists what Pango
can actually use here.

### Real typesetting

For fractions, radicals and limits stacked over big operators, load
[MathTeXEngine.jl](https://github.com/Kolaru/MathTeXEngine.jl) and use
`texmath!`:

```julia
using StatusWindows, MathTeXEngine   # both, in either order

draw!(p) do c
    texmath!(c, raw"\frac{\alpha}{\beta} + \sqrt{x^2}")
    texmath!(c, raw"\sum_{i=1}^{n} x_i^2")
    texmath!(c, raw"\hat{\beta} = (X^TX)^{-1}X^Ty")
end
```

MathTeXEngine is a **weak dependency**: it is not installed with this
package, and `texmath!` does not exist until you load it — at which point
a package extension supplies it. Nobody pays for a TeX engine to draw
`σ² = 0.37`.

It is also the *more portable* of the two paths, which is not obvious.
MathTeXEngine ships its own fonts and rasterizes through FreeType, so it
bypasses fontconfig entirely and renders identically on a machine with no
math fonts installed. The lightweight Pango path is the one with an
environment dependency. Use `texmath!` when the notation matters or the
machine is unknown, `math!` when you want cheap sub/superscripts in the
panel's own font.

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

Colours, font and spacing come from `Style`:

```julia
Panel(style = Style(font = "Iosevka", size = 12.0, bg = (0.0, 0.0, 0.0, 0.0)))
```

A `bg` alpha of `0.0` gives the classic conky look, where only the text
floats over the wallpaper.

## Controls

Drag the panel with the left mouse button (`movable = true`, the default);
Escape closes it. Pass `passthrough = true` to let clicks fall through to
whatever is underneath — that also disables dragging.

`start!` runs the panel on a task so the REPL stays usable; `stop!` ends it.

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
rendering, dragging and clean shutdown all verified. The GLFW hints and the
GL 3.3 core profile used here are supported on Windows and macOS as well,
and no code path is platform-specific apart from the X11 request above — but
*nobody has run it on those platforms yet*. Reports welcome.

## Installation

```julia
using Pkg
Pkg.develop(path = "path/to/StatusWindows.jl")
```
