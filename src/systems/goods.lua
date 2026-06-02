-- src/systems/goods.lua
-- Typed-goods accounting (Phase 5). Tracks what flows into and out of the
-- city's industrial network each month: supply from extraction buildings,
-- demand from consumers, and the resulting inventory stockpile.
--
-- Does NOT gate any simulation behaviour until Phase 5 step 6 wires
-- Goods.efficiency() into growth.lua. Steps 2–5 build the data layer cleanly;
-- step 6 is the single point that applies it to industrial output.

local Grid = require("src.world.grid")
local C    = require("src.world.constants")

local Goods = {}

-- Pure: monthly supply rate per good type, summed across all producer buildings.
-- Returns a table keyed by C.GOODS.* integers.
-- Iron Mine producers are added in step 3 and extend this scan.
function Goods.supply_rate(world)
    local rates = {}
    Grid.each(world.grid, function(_, _, tile)
        if tile.mine then
            local g = C.GOODS.RAW_MATERIALS
            rates[g] = (rates[g] or 0) + C.IRON_MINE.PRODUCTION
        end
    end)
    return rates
end

-- Pure: monthly demand rate per good type, summed across all completed
-- industrial buildings.
function Goods.demand_rate(world)
    local rates = {}
    Grid.each(world.grid, function(_, _, tile)
        if tile.building
        and tile.building.state == C.BUILD.COMPLETE
        and tile.zone == C.ZONE.INDUSTRIAL then
            for good, amount in pairs(C.IND_DEMAND) do
                rates[good] = (rates[good] or 0) + amount
            end
        end
    end)
    return rates
end

-- Pure: supply-chain efficiency for one good, 0..1.
-- 1 when inventory >= BUFFER_MONTHS * monthly demand (fully stocked).
-- 1 when demand is zero (no bottleneck if nothing is needed).
function Goods.efficiency(world, good)
    local inv = world.goods.inventory[good] or 0
    local dem = world.goods.demand[good] or 0
    if dem == 0 then return 1 end
    local buffer = dem * C.GOODS_TUNE.BUFFER_MONTHS
    return math.min(1, inv / buffer)
end

function Goods.system()
    return {
        interval    = C.SIM.SECONDS_PER_MONTH,
        accumulator = 0,
        tick = function(world)
            local supply = Goods.supply_rate(world)
            local demand = Goods.demand_rate(world)
            world.goods.supply = supply
            world.goods.demand = demand
            -- Advance each good's inventory by net flow; clamp to [0, MAX_INVENTORY].
            for _, good in pairs(C.GOODS) do
                local s   = supply[good] or 0
                local d   = demand[good] or 0
                local inv = (world.goods.inventory[good] or 0) + s - d
                world.goods.inventory[good] =
                    math.max(0, math.min(C.GOODS_TUNE.MAX_INVENTORY, inv))
            end
        end,
    }
end

return Goods
