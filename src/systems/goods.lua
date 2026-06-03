-- src/systems/goods.lua
-- Typed-goods accounting (Phase 5). Tracks what flows into and out of the
-- city's industrial network each month: supply from extraction buildings,
-- demand from consumers, and the resulting inventory stockpile.
--
-- Does NOT gate any simulation behaviour until Phase 5 step 6 wires
-- Goods.efficiency() into growth.lua. Steps 2–5 build the data layer cleanly;
-- step 6 is the single point that applies it to industrial output.

local Grid  = require("src.world.grid")
local Rails = require("src.systems.rails")
local C     = require("src.world.constants")

local Goods = {}

local SUPPLY_DIRS = {{1,0},{-1,0},{0,1},{0,-1}}

-- Pure: monthly supply rate per good type.
-- A mine contributes only when its 4-connected mine cluster has at least one
-- tile adjacent to a bridged rail component. One rail connection serves the
-- whole deposit cluster — the player needn't run rail past every mine tile.
function Goods.supply_rate(world)
    local bridged = (world.freight and world.freight.bridged) or {}
    local accessible = {}  -- set of mine tile indices that can contribute
    local seen = {}        -- BFS visited set

    Grid.each(world.grid, function(x, y, tile)
        if not tile.mine then return end
        local start = Grid.idx(world.grid, x, y)
        if seen[start] then return end

        -- BFS: collect this mine's connected cluster, check for any bridged rail neighbor.
        local cluster = {}
        local has_access = false
        local q = {{x, y}}
        while #q > 0 do
            local pos = table.remove(q, 1)
            local px, py = pos[1], pos[2]
            local pidx = Grid.idx(world.grid, px, py)
            if not seen[pidx] then
                seen[pidx] = true
                cluster[#cluster + 1] = pidx
                local cid = Rails.adjacent_component(world, px, py)
                if cid and bridged[cid] then has_access = true end
                for _, d in ipairs(SUPPLY_DIRS) do
                    local nx, ny = px + d[1], py + d[2]
                    local nt = Grid.get(world.grid, nx, ny)
                    if nt and nt.mine then
                        local nidx = Grid.idx(world.grid, nx, ny)
                        if not seen[nidx] then q[#q + 1] = {nx, ny} end
                    end
                end
            end
        end

        if has_access then
            for _, cidx in ipairs(cluster) do accessible[cidx] = true end
        end
    end)

    local rates = {}
    for _ in pairs(accessible) do
        rates[C.GOODS.RAW_MATERIALS] =
            (rates[C.GOODS.RAW_MATERIALS] or 0) + C.IRON_MINE.PRODUCTION
    end

    -- Food: completed agricultural buildings produce at a rate scaled by tile fertility.
    Grid.each(world.grid, function(x, y, tile)
        if tile.zone == C.ZONE.AGRICULTURAL
        and tile.building and tile.building.state == C.BUILD.COMPLETE then
            local yield = C.FARM.PRODUCTION * (tile.fertility or 0)
            rates[C.GOODS.FOOD] = (rates[C.GOODS.FOOD] or 0) + yield
        end
    end)

    return rates
end

-- Pure: monthly demand rate per good type, summed across all completed
-- industrial buildings.
function Goods.demand_rate(world)
    local rates = {}
    Grid.each(world.grid, function(_, _, tile)
        if not (tile.building and tile.building.state == C.BUILD.COMPLETE) then return end
        if tile.zone == C.ZONE.INDUSTRIAL then
            for good, amount in pairs(C.IND_DEMAND) do
                rates[good] = (rates[good] or 0) + amount
            end
        elseif tile.zone == C.ZONE.RESIDENTIAL then
            for good, amount in pairs(C.RES_DEMAND) do
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
