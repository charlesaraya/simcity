-- src/input/tools.lua
-- The command layer: translate a selected tool into a world write. This is the
-- only place that maps "what the player picked" to "what changes in the world".
-- It holds no state (the current tool lives in the input layer) and knows
-- nothing about rendering or the bus -- the world writers publish the events.

local World = require("src.world.world")
local Drag = require("src.input.drag")
local C = require("src.world.constants")

local Tools = {}

-- Which zone each zone tool paints. Shared by the single-tile and rectangle paths.
local ZONE_OF = {
    [C.TOOL.ZONE_RES] = C.ZONE.RESIDENTIAL,
    [C.TOOL.ZONE_COM] = C.ZONE.COMMERCIAL,
    [C.TOOL.ZONE_IND] = C.ZONE.INDUSTRIAL,
}

-- Affordability gate for zoning, mirroring the road gate.
local function zone_with_cost(world, x, y, zone)
    if world.treasury < C.ZONE_COST[zone] then return false end
    return World.zone_tile(world, x, y, zone)
end

-- Apply `tool` to tile (x, y). Returns whatever the underlying writer returns
-- (true on a real change, false on no-op / out of bounds).
function Tools.apply(tool, world, x, y)
    if tool == C.TOOL.BULLDOZE then
        return World.bulldoze(world, x, y)
    elseif tool == C.TOOL.ZONE_RES then
        return zone_with_cost(world, x, y, C.ZONE.RESIDENTIAL)
    elseif tool == C.TOOL.ZONE_COM then
        return zone_with_cost(world, x, y, C.ZONE.COMMERCIAL)
    elseif tool == C.TOOL.ZONE_IND then
        return zone_with_cost(world, x, y, C.ZONE.INDUSTRIAL)
    elseif tool == C.TOOL.ROAD then
        -- Affordability gate: command layer refuses to build the road
        -- if the city can't afford it.
        if world.treasury < C.ROAD.COST then return false end
        return World.build_road(world, x, y)
    end
    return false
end

-- Commit a dragged road run, all-or-nothing: only if the run is valid (no
-- zone/building crossings) AND the whole grass-tile cost is affordable. Existing
-- roads in the run are passed over by build_road.
function Tools.apply_run(world, run)
    if not (Drag.road_run_valid(world, run) and Drag.road_affordable(world, run)) then
        return false
    end
    for _, t in ipairs(run) do
        World.build_road(world, t.x, t.y)
    end
    return true
end

-- Commit a dragged zone rectangle, all-or-nothing: only if the whole
-- changed-tile cost is affordable. Tiles already in the zone (and roads, already
-- excluded by zone_rect) are no-ops.
function Tools.apply_rect(tool, world, tiles)
    local zone = ZONE_OF[tool]
    if not zone then return false end
    if not Drag.zone_affordable(world, tiles, zone) then return false end
    for _, t in ipairs(tiles) do
        World.zone_tile(world, t.x, t.y, zone)
    end
    return true
end

return Tools
