-- src/systems/freight.lua
-- Freight bridge: a freight station is "bridged" when it is adjacent to BOTH
-- a rail tile AND a road tile. A bridged station marks its rail component(s)
-- in world.freight.bridged so Goods.supply_rate can gate mine output on
-- having a viable export path.
--
-- Derived state (like roads.connected and rails.components): rebuilt whenever
-- any of the relevant tile types changes. No monthly tick — topology only.

local Grid  = require("src.world.grid")
local Rails = require("src.systems.rails")
local Bus   = require("src.bus")
local C     = require("src.world.constants")

local Freight = {}

-- Cardinal-neighbor offsets.
local DIRS = { {0,1},{0,-1},{1,0},{-1,0} }

-- Pure: scan all station anchor tiles, check if each touches both a rail tile
-- and a road tile on its perimeter, and collect the bridged component IDs.
-- Returns a table { [component_id] = true }.
function Freight.compute_bridged(world)
    local bridged = {}
    local n = C.FREIGHT_STATION.FOOTPRINT
    Grid.each(world.grid, function(x, y, tile)
        if not tile.station then return end  -- anchor tiles only
        local has_road = false
        local rail_cids = {}
        for dy = 0, n - 1 do
            for dx = 0, n - 1 do
                local fx, fy = x + dx, y + dy
                for _, d in ipairs(DIRS) do
                    local nx, ny = fx + d[1], fy + d[2]
                    -- Skip tiles that are part of this station's footprint.
                    if not (nx >= x and nx < x + n and ny >= y and ny < y + n) then
                        local t = Grid.get(world.grid, nx, ny)
                        if t then
                            if t.road then has_road = true end
                            if t.rail then
                                local cid = Rails.tile_component(world, nx, ny)
                                if cid then rail_cids[cid] = true end
                            end
                        end
                    end
                end
            end
        end
        if has_road then
            for cid in pairs(rail_cids) do
                bridged[cid] = true
            end
        end
    end)
    return bridged
end

-- Install: seed world.freight (migration guard for old saves), compute initial
-- bridged state, and subscribe to the six events that can change it.
function Freight.install(world)
    if not world.freight then world.freight = {} end
    world.freight.bridged = Freight.compute_bridged(world)

    local function recompute()
        world.freight.bridged = Freight.compute_bridged(world)
    end

    Bus.subscribe(C.EVENTS.STATION_BUILT,    recompute)
    Bus.subscribe(C.EVENTS.STATION_REMOVED,  recompute)
    Bus.subscribe(C.EVENTS.RAIL_BUILT,       recompute)
    Bus.subscribe(C.EVENTS.RAIL_REMOVED,     recompute)
    Bus.subscribe(C.EVENTS.ROAD_BUILT,       recompute)
    Bus.subscribe(C.EVENTS.ROAD_REMOVED,     recompute)
end

-- Query: is the given rail component ID bridged through a freight station?
function Freight.rail_bridged(world, cid)
    return cid ~= nil
        and world.freight ~= nil
        and world.freight.bridged[cid] == true
end

return Freight
