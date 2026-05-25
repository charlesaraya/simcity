-- src/systems/economy.lua
-- The city budget, as a pure observer. Each month it taxes JOBS (commerce and
-- industry -- where economic activity happens; residents are not taxed) and
-- pays flat upkeep on every completed building, then moves world.treasury by the
-- net. It GATES NOTHING -- zoning and growth never ask whether there's money.
-- Treasury is a score and a feedback signal, not yet a constraint.
--
-- This system is the test of Phase 1's decoupling bet: it subscribes to no
-- events and is referenced by nothing it observes. It reads world state by
-- scanning (like demand), and is registered in the runner additively. Adding it
-- required ZERO edits to demand, growth, zoning, or the world writers.

local World = require("src.world.world")
local Bus = require("src.bus")
local C = require("src.world.constants")

local Economy = {}

-- Pure: total jobs and building count -> monthly net delta. Jobs are the tax
-- base; every building costs flat upkeep. May be negative (a jobless,
-- residential-heavy city); the system applies it without clamping (debt is
-- allowed).
function Economy.compute(jobs, buildings)
    return jobs * C.ECON.TAX_RATE - buildings * C.ECON.UPKEEP
end

function Economy.system()
    return {
        interval = C.SIM.SECONDS_PER_MONTH,
        accumulator = 0,
        tick = function(world)
            local net = Economy.compute(World.jobs(world), World.building_count(world))
            world.treasury = world.treasury + net
            world.economy.last_net = net
        end,
    }
end

-- The economy's event-driven face: a one-time road expense. Keeping the debit
-- here (not in the world writer or the input layer) preserves the invariant that
-- the economy is the only module that writes treasury.
function Economy.install(world)
    Bus.subscribe(C.EVENTS.ROAD_BUILT, function()
        world.treasury = world.treasury - C.ROAD.COST
    end)
end

return Economy
