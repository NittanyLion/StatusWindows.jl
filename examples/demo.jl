# A system monitor, in the spirit of conky.
#
#     julia --project=. examples/demo.jl
#
# Drag the panel with the left mouse button; Escape closes it.
#
# Everything below the Panel/draw! calls is ordinary Julia — none of it is
# part of StatusWindows. Swap it for whatever you actually want on screen.

using StatusWindows

"Fraction of CPU time spent busy since the previous call, averaged over cores."
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

gib(bytes) = bytes / 1024^3

function duration(seconds)
    d, r = divrem(round(Int, seconds), 86400)
    h, r = divrem(r, 3600)
    m, _ = divrem(r, 60)
    d > 0 ? "$(d)d $(h)h" : h > 0 ? "$(h)h $(m)m" : "$(m)m"
end

cpu = cpu_sampler()
history = zeros(Float64, 48)          # one bar per tick, oldest first

panel = Panel(width = 280, height = 300, x = 60, y = 60)

draw!(panel) do c
    load = cpu()
    popfirst!(history)
    push!(history, load)

    used = gib(Sys.total_memory() - Sys.free_memory())
    total = gib(Sys.total_memory())

    heading!(c, "system")
    kv!(c, "host", gethostname())
    kv!(c, "up", duration(Sys.uptime()))
    spacer!(c)

    bar!(c, "cpu", load)
    sparkline!(c, history; lo = 0.0, hi = 1.0)
    spacer!(c)

    bar!(c, "mem", used / total)
    kv!(c, "", string(round(used, digits = 1), " / ",
                      round(total, digits = 1), " GiB"))

    # Sys.loadavg is meaningless on Windows.
    if !Sys.iswindows()
        spacer!(c)
        one, five, fifteen = Sys.loadavg()
        kv!(c, "load", join(round.((one, five, fifteen), digits = 2), "  "))
    end
end

run!(panel; refresh = 1.0)
