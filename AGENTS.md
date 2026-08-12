# Working on StatusWindows.jl

Borderless always-on-top desktop panels: a GLFW window with no decorations,
a Cairo image surface drawn in Julia, uploaded to a GL texture each tick.

## Things that will bite you

**GLFW initializes when it is loaded, not when you use it.** `GLFW.jl`'s own
`__init__` calls `glfwInit()` and throws if it fails, so merely running
`using StatusWindows` needs a display. Nothing in this package can catch
that. CI starts Xvfb before any Julia runs; see `.github/workflows/CI.yml`.

**The test suite must stay headless.** Tests draw into a bare Cairo image
surface — no window, no GL context (`test/runtests.jl`, `testcanvas`).
Anything that needs a real panel belongs in `examples/demo.jl`, which CI
does not run. Do not add a test that opens a window.

**There is no `test/Project.toml`.** Test dependencies come from
`[targets] test` in the top-level `Project.toml`. Creating one silently
changes how tests resolve; if a stray `test/Project.toml` appears, delete it.

**Documenter cannot `@ref` across packages.** A `[`Cairo.tex2pango`](@ref)`
fails the docs build with "no docstring found for binding". Use a plain code
span for anything defined outside this module. `docs/src/index.md` is a bare
`@autodocs` over the whole module, so every docstring is rendered, exported
or not — and every `@ref` in one has to resolve.

**macOS needs the main thread.** Cocoa requires window creation and event
polling on thread 1. `start!` uses `@async`, which is sticky and stays put,
so only `Threads.@spawn` can break it; `Panel` guards against that.

## The two math APIs

Deliberately named against intuition:

- `math!` / `mathwidth` — real TeX via MathTeXEngine, in
  `ext/StatusWindowsMathTeXExt.jl`. A **weak dependency**: these throw a
  helpful error until the user loads MathTeXEngine. Rasterizes its own
  bundled fonts through FreeType, so it bypasses fontconfig and looks the
  same everywhere.
- `poormansmath!` / `poormansmathwidth` — Pango markup, no extra dependency,
  no fractions or radicals, and the result depends on what fonts the machine
  has.

Do not "simplify" by merging them; the point is that one is free and one is
correct.

## Colors

`src/colors.jl` is **generated, not written**. It is the 151 SVG names from
LaTeX xcolor's `svgnames` option, parsed out of `svgnam.def` in a TeX Live
tree so a panel and a paper agree on what Crimson is. Do not hand-edit
entries; regenerate from that file if xcolor ever changes.

Anything user-facing that takes a color should accept `ColorLike` and pass
it through `rgba(style, color)` rather than demanding a tuple. The style
names — `:fg`, `:dim`, `:accent`, `:warn`, `:bg` — only resolve when a
`Style` is in hand, which is why `Style(fg = :accent)` throws.

## Fonts

Never hardcode a family name. Body text goes through `fontof(style)` and
math through `mathfontof(style)`, which resolve `BODY_FONTS` / `MATH_FONTS`
against what fontconfig actually has. An empty `Style.font` means "pick the
best installed"; a name the user typed is a request, so a missing one warns
once rather than silently substituting.

## Headless behavior

`hasdisplay()` decides whether a real window is possible. When it is not,
`Panel` warns once and returns an inert panel whose methods all no-op, so a
script written for a desktop still runs on a server. `render(...)` to
`.pdf`/`.svg`/`.png` never needs a window and works regardless.

## Conventions

- American spelling in code, comments, docstrings and prose.
- Comments explain *why*, not what; match the density already there.
- Every exported function has a docstring, since `@autodocs` publishes it.
- Run `julia --project=. -e 'using Pkg; Pkg.test()'` and, for anything
  touching a docstring, `julia --project=docs docs/make.jl`.
