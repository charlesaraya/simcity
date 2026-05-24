-- src/systems/runner.lua
-- The central simulation loop (Principle 3). Holds every system and, each frame,
-- advances them by sim-dt. Each system is a table:
--   { interval = <sim-seconds>, accumulator = 0, tick = function(world) ... end }
--
-- A system accumulates time and fires once per whole interval. The WHILE loop is
-- the key: a large dt (fast-forward) fires multiple ticks rather than skipping,
-- so 10x speed runs the same ticks 1x would over the same sim-time. That makes
-- fast-forward deterministic and equivalent to real-time play.

local Runner = {}

function Runner.new()
    return { systems = {} }
end

-- Register a system. Returns it so callers can keep a handle. Defaults the
-- accumulator so systems don't have to.
function Runner.add(runner, system)
    system.accumulator = system.accumulator or 0
    runner.systems[#runner.systems + 1] = system
    return system
end

-- Advance all systems by sim_dt (already scaled by game speed upstream).
function Runner.update(runner, sim_dt, world)
    for i = 1, #runner.systems do
        local s = runner.systems[i]
        if s.interval > 0 then
            s.accumulator = s.accumulator + sim_dt
            while s.accumulator >= s.interval do
                s.tick(world)
                s.accumulator = s.accumulator - s.interval
            end
        end
    end
end

return Runner
