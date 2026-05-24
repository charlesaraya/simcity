-- src/systems/economy.lua
-- The city budget, as a pure observer. Each month it collects tax from every
-- occupant (residents + workers) and pays upkeep on every completed building,
-- then moves world.treasury by the net. It GATES NOTHING -- zoning and growth
-- never ask whether there's money. Treasury is a score and a feedback signal,
-- not yet a constraint.
--
-- This system is the test of Phase 1's decoupling bet: it subscribes to no
-- events and is referenced by nothing it observes. It reads world state by
-- scanning (like demand), and is registered in the runner additively. Adding it
-- required ZERO edits to demand, growth, zoning, or the world writers.

local World = require("src.world.world")
local C = require("src.world.constants")

local Economy = {}

-- Pure: occupants and building count -> monthly net delta. May be negative; the
-- system applies it without clamping (debt is allowed).
function Economy.compute(pop, jobs, buildings)
    return (pop + jobs) * C.ECON.TAX_RATE - buildings * C.ECON.UPKEEP
end

function Economy.system()
    return {
        interval = C.SIM.SECONDS_PER_MONTH,
        accumulator = 0,
        tick = function(world)
            local net = Economy.compute(
                World.population(world),
                World.jobs(world),
                World.building_count(world)
            )
            world.treasury = world.treasury + net
            world.economy.last_net = net
        end,
    }
end

return Economy
