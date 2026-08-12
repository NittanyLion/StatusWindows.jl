```@meta
CurrentModule = StatusWindows
```

# StatusWindows

Documentation for [StatusWindows](https://github.com/NittanyLion/StatusWindows.jl).

## Examples

Two runnable scripts live in `examples/`:

* [`showcase.jl`](https://github.com/NittanyLion/StatusWindows.jl/blob/main/examples/showcase.jl)
  — one panel that exercises everything at once: widgets, styling, both math
  paths and file export.

  ```julia
  julia --project=. examples/showcase.jl              # live panel
  julia --project=. examples/showcase.jl out.pdf      # render to a file
  ```

* [`demo.jl`](https://github.com/NittanyLion/StatusWindows.jl/blob/main/examples/demo.jl)
  — a working system monitor built on `Sys.cpu_info`, `Sys.free_memory` and
  friends.

```@index
```

```@autodocs
Modules = [StatusWindows]
```
