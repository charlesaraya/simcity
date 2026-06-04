-- src/systems/economy.lua
-- The city budget, as a pure observer. Each month it taxes JOBS (where economic
-- activity happens) and pays upkeep on buildings and infrastructure, then moves
-- treasury by the net. It GATES NOTHING: zoning and growth never ask whether there's money.
-- Treasury is a score and a feedback signal.
--
-- This system subscribes to no events and is referenced by nothing it observes.
-- It reads world state by scanning (like demand), and is registered in the runner
-- additively. Adding it required ZERO edits to demand, growth, zoning, or the world writers.

local World = require("src.world.world")
local Bus = require("src.bus")
local C = require("src.world.constants")

local Economy = {}

-- Pure: Monthly net delta.
function Economy.compute(jobs, buildings, plants, mines, farms)
    plants = plants or 0
    mines  = mines  or 0
    farms  = farms  or 0
    return jobs * C.ECON.TAX_RATE
        - buildings * C.ECON.UPKEEP
        - plants * C.PLANT.UPKEEP
        - mines * C.IRON_MINE.UPKEEP
        - farms * C.FARM.UPKEEP
end

-- Pure read: the recurring monthly budget for the HUD.
function Economy.budget(world)
    local income  = World.jobs(world) * C.ECON.TAX_RATE
    local expense = World.business_count(world) * C.ECON.UPKEEP
        + World.plant_count(world) * C.PLANT.UPKEEP
        + World.mine_count(world) * C.IRON_MINE.UPKEEP
        + World.farm_count(world) * C.FARM.UPKEEP
    return { income = income, expense = expense, net = income - expense }
end

function Economy.system()
    return {
        interval = C.SIM.SECONDS_PER_MONTH,
        accumulator = 0,
        tick = function(world)
            local net = Economy.compute(
                World.jobs(world), World.business_count(world),
                World.plant_count(world), World.mine_count(world),
                World.farm_count(world))
            world.treasury = world.treasury + net
            world.economy.last_net = net
        end,
    }
end

-- The economy's event-driven face. The economy is the only module that writes treasury.
function Economy.install(world)
    Bus.subscribe(C.EVENTS.ROAD_BUILT, function()
        world.treasury = world.treasury - C.ROAD.COST
    end)

    Bus.subscribe(C.EVENTS.POWER_LINE_BUILT, function()
        world.treasury = world.treasury - C.POWER_LINE.COST
    end)
    Bus.subscribe(C.EVENTS.PLANT_BUILT, function()
        world.treasury = world.treasury - C.PLANT.COST
    end)
    Bus.subscribe(C.EVENTS.MINE_BUILT, function()
        world.treasury = world.treasury - C.IRON_MINE.COST
    end)
    Bus.subscribe(C.EVENTS.RAIL_BUILT, function()
        world.treasury = world.treasury - C.RAIL.COST
    end)
    Bus.subscribe(C.EVENTS.STATION_BUILT, function()
        world.treasury = world.treasury - C.FREIGHT_STATION.COST
    end)
    Bus.subscribe(C.EVENTS.HOSPITAL_BUILT, function()
        world.treasury = world.treasury - C.HOSPITAL.COST
    end)
    Bus.subscribe(C.EVENTS.MED_CENTER_BUILT, function()
        world.treasury = world.treasury - C.MED_CENTER.COST
    end)
end

return Economy
