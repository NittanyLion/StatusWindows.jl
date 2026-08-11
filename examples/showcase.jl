# Everything the package does, in one panel.
#
#     julia --project=. examples/showcase.jl              # live panel
#     julia --project=. examples/showcase.jl out.pdf      # render to a file
#
# Drag the panel with the left mouse button; Escape closes it.
#
# MathTeXEngine is optional. Load it and the panel draws real TeX layout;
# leave it out and the same panel falls back to Pango notation. That is the
# package extension doing its job -- nothing here needs to change.

using StatusWindows

const HAS_TEX = try
    @eval using MathTeXEngine
    true
catch
    false
end

# --- data -------------------------------------------------------------

"Busy fraction since the previous call, averaged over cores."
function cpu_sampler()
    prev = Sys.cpu_info()
    return function ()
        cur = Sys.cpu_info()
        busy = idle = 0.0
        for (a, b) in zip(prev, cur)
            busy += (b.cpu_times!user - a.cpu_times!user) +
                    (b.cpu_times!nice - a.cpu_times!nice) +
                    (b.cpu_times!sys  - a.cpu_times!sys)  +
                    (b.cpu_times!irq  - a.cpu_times!irq)
            idle += b.cpu_times!idle - a.cpu_times!idle
        end
        prev = cur
        total = busy + idle
        return total > 0 ? busy / total : 0.0
    end
end

function uptime_str(seconds)
    d, r = divrem(round(Int, seconds), 86400)
    h, m = divrem(r ÷ 60, 60)
    d > 0 ? "$(d)d $(h)h" : h > 0 ? "$(h)h $(m)m" : "$(m)m"
end

gib(bytes) = round(bytes / 1024^3, digits = 1)

# --- content ----------------------------------------------------------

cpu = cpu_sampler()
history = zeros(Float64, 48)      # one sample per tick, oldest first

function content(c)
    load = cpu()
    popfirst!(history); push!(history, load)
    used, total = gib(Sys.total_memory() - Sys.free_memory()), gib(Sys.total_memory())

    heading!(c, "system")
    kv!(c, "host", gethostname())
    kv!(c, "up", uptime_str(Sys.uptime()))
    spacer!(c)

    bar!(c, "cpu", load)
    sparkline!(c, history; lo = 0.0, hi = 1.0)
    bar!(c, "mem", used / total)
    kv!(c, "", "$used / $total GiB")
    spacer!(c)

    heading!(c, "math")
    # math! is always available: Pango markup, panel's own font.
    math!(c, "\\sigma^2 = 0.37   \\mu \\pm 2\\sigma")
    if HAS_TEX
        # texmath! needs MathTeXEngine -- real fractions and limits.
        texmath!(c, raw"\hat{\beta} = (X^TX)^{-1}X^Ty")
        texmath!(c, raw"\sum_{i=1}^{n} \frac{x_i}{\sigma}"; color = c.style.accent)
    else
        math!(c, "\\sum_{i=1}^n x_i / \\sigma"; color = c.style.accent)
        text!(c, "(load MathTeXEngine for real TeX)"; color = c.style.dim, size = 10)
    end
end

# --- run or render ----------------------------------------------------

const W, H = 300, 430

if isempty(ARGS)
    panel = Panel(width = W, height = H, x = 60, y = 60)
    draw!(content, panel)
    run!(panel; refresh = 1.0)
else
    # The sampler reports the delta between two calls, and a file gets one
    # frame, so collect a short trace first or the sparkline draws flat.
    for _ in 1:12
        popfirst!(history); push!(history, cpu())
        sleep(0.05)
    end
    println(render(content, ARGS[1]; width = W, height = H))
end
