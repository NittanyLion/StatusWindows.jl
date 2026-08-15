# Attribution for `src/glfw/`

The bindings in this folder were written by borrowing from
[GLFW.jl](https://github.com/JuliaGL/GLFW.jl), which is the reference for
how the GLFW C API is called from Julia and which this package depended on
until it did not. Some of the code here is a direct simplification of
GLFW.jl's, and all of it was checked against it:

* the `ccall` signatures in `window.jl` and `init.jl` — argument types,
  return types and the `Ref` out-parameter pattern for the getters — follow
  `GLFW.jl/src/glfw3.jl` one for one;
* the callback arrangement in `callbacks.jl` — a C-compatible wrapper
  registered with GLFW, forwarding to a Julia function held alive on the
  Julia side — is GLFW.jl's design from `GLFW.jl/src/callback.jl`, with its
  code-generating macros replaced by three written-out setters;
* the constant values in `constants.jl` were transcribed from
  `GLFW.jl/src/glfw3.jl`, which in turn takes them from GLFW's `glfw3.h`;
* the mapping of `JULIA_GLFW_PLATFORM` onto a backend, in `init.jl`,
  reproduces GLFW.jl's `HandlePlatformSelection` so that the variable keeps
  meaning here what it means there.

What is not borrowed is the initialization policy, which is the reason this
folder exists: GLFW.jl initializes GLFW from its own `__init__` and throws
if that fails, while here it happens on first use and reports failure by
returning `false`.

GLFW.jl is the work of Jay Petacat, Simon Danisch and the other GLFW.jl
authors, and is distributed under the MIT license:

> Copyright (c) 2013-2019 The GLFW.jl Authors
>
> Permission is hereby granted, free of charge, to any person obtaining a
> copy of this software and associated documentation files (the "Software"),
> to deal in the Software without restriction, including without limitation
> the rights to use, copy, modify, merge, publish, distribute, sublicense,
> and/or sell copies of the Software, and to permit persons to whom the
> Software is furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in
> all copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
> THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
> FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
> DEALINGS IN THE SOFTWARE.

The library these bindings call is [GLFW](https://www.glfw.org) itself,
copyright © 2002-2006 Marcus Geelnard and © 2006-2019 Camilla Löwy, under
the zlib/libpng license. It is not vendored here; it arrives as a binary
through `GLFW_jll`, exactly as it did before, and its own license text ships
with that package. The names and numeric values in `constants.jl` come from
its public header.
