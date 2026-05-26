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

-- Pure: Monthly net delta.
function Economy.compute(jobs, buildings, plants)
    plants = plants or 0
    return jobs * C.ECON.TAX_RATE
        - buildings * C.ECON.UPKEEP
        - plants * C.PLANT.UPKEEP -- Plants burn fuel each month.
end

-- Pure read: the recurring monthly budget for the HUD.
function Economy.budget(world)
    local income = World.jobs(world) * C.ECON.TAX_RATE
    local expense = World.building_count(world) * C.ECON.UPKEEP
        + World.plant_count(world) * C.PLANT.UPKEEP
    return { income = income, expense = expense, net = income - expense }
end

function Economy.system()
    return {
        interval = C.SIM.SECONDS_PER_MONTH,
        accumulator = 0,
        tick = function(world)
            local net = Economy.compute(
                World.jobs(world), World.building_count(world), World.plant_count(world))
            world.treasury = world.treasury + net
            world.economy.last_net = net
        end,
    }
end

-- The economy's event-driven face: one-time debits for infrastructure. The
-- economy is the only module that writes treasury.
function Economy.install(world)
    Bus.subscribe(C.EVENTS.ROAD_BUILT, function()
        world.treasury = world.treasury - C.ROAD.COST
    end)
    Bus.subscribe(C.EVENTS.TILE_ZONED, function(data)
        world.treasury = world.treasury - C.ZONE_COST[data.zone]
    end)
    Bus.subscribe(C.EVENTS.POWER_LINE_BUILT, function()
        world.treasury = world.treasury - C.POWER_LINE.COST
    end)
    Bus.subscribe(C.EVENTS.PLANT_BUILT, function()
        world.treasury = world.treasury - C.PLANT.COST
    end)
end

return Economy
