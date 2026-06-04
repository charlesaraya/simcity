-- src/input/tools.lua
-- The command layer: translate a selected tool into a world write. This is the
-- only place that maps "what the player picked" to "what changes in the world".
-- It holds no state (the current tool lives in the input layer) and knows
-- nothing about rendering or the bus -- the world writers publish the events.

local World = require("src.world.world")
local Drag = require("src.input.drag")
local C = require("src.world.constants")

local Tools = {}

-- Which zone each zone tool paints.
-- Shared by the single-tile and rectangle paths.
local ZONE_OF = {
    [C.TOOL.ZONE_RES]  = C.ZONE.RESIDENTIAL,
    [C.TOOL.ZONE_COM]  = C.ZONE.COMMERCIAL,
    [C.TOOL.ZONE_IND]  = C.ZONE.INDUSTRIAL,
    [C.TOOL.ZONE_AGRI] = C.ZONE.AGRICULTURAL,
}

-- Apply `tool` to tile (x, y). Returns whatever the underlying writer returns
-- (true on a real change, false on no-op / out of bounds).
function Tools.apply(tool, world, x, y)
    if tool == C.TOOL.BULLDOZE then
        return World.bulldoze(world, x, y)
    elseif tool == C.TOOL.ZONE_RES then
        return World.zone_tile(world, x, y, C.ZONE.RESIDENTIAL)
    elseif tool == C.TOOL.ZONE_COM then
        return World.zone_tile(world, x, y, C.ZONE.COMMERCIAL)
    elseif tool == C.TOOL.ZONE_IND then
        return World.zone_tile(world, x, y, C.ZONE.INDUSTRIAL)
    elseif tool == C.TOOL.ROAD then
        if world.treasury - C.ROAD.COST < C.ECON.DEBT_CEILING then return false end
        return World.build_road(world, x, y)
    elseif tool == C.TOOL.POWER_LINE then
        if world.treasury - C.POWER_LINE.COST < C.ECON.DEBT_CEILING then return false end
        return World.build_power_line(world, x, y)
    elseif tool == C.TOOL.PLANT then
        return Tools.apply_plant(world, x, y)
    elseif tool == C.TOOL.MINE then
        if world.treasury - C.IRON_MINE.COST < C.ECON.DEBT_CEILING then return false end
        return World.build_mine(world, x, y)
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

-- Commit a dragged power-line run, all-or-nothing. Reuses the road run's validity
-- (lines and roads share the same obstacles); only the price differs. Existing
-- conductors in the run are passed over by build_power_line.
function Tools.apply_line_run(world, run)
    if not (Drag.road_run_valid(world, run) and Drag.power_line_affordable(world, run)) then
        return false
    end
    for _, t in ipairs(run) do
        World.build_power_line(world, t.x, t.y)
    end
    return true
end

-- Commit a dragged zone rectangle. Zoning is free; cost is charged later when
-- growth starts each building.
function Tools.apply_rect(tool, world, tiles)
    local zone = ZONE_OF[tool]
    if not zone then return false end
    for _, t in ipairs(tiles) do
        World.zone_tile(world, t.x, t.y, zone)
    end
    return true
end

-- Commit a dragged freight rail run, all-or-nothing: only if the run is valid
-- AND the whole new-tile cost is affordable. Existing rail is passed over.
function Tools.apply_rail_run(world, run)
    if not (Drag.rail_run_valid(world, run) and Drag.rail_affordable(world, run)) then
        return false
    end
    for _, t in ipairs(run) do
        World.build_rail(world, t.x, t.y)
    end
    return true
end

-- Place a 2x2 power plant anchored at (x, y), all-or-nothing: only if the whole
-- footprint is clear grass AND the flat plant cost is affordable.
function Tools.apply_plant(world, x, y)
    if not (Drag.plant_footprint_valid(world, x, y) and Drag.plant_affordable(world)) then
        return false
    end
    return World.build_plant(world, x, y)
end

-- Place a 2×2 freight station anchored at (x, y): footprint must be clear grass,
-- station must be adjacent to BOTH a rail tile and a road tile, and treasury
-- must cover the cost.
function Tools.apply_station(world, x, y)
    if not (Drag.station_footprint_valid(world, x, y) and Drag.station_affordable(world)) then
        return false
    end
    return World.build_station(world, x, y)
end

-- Place a 2×2 hospital anchored at (x, y): footprint must be clear grass,
-- hospital must be road-adjacent, and treasury must cover the cost.
function Tools.apply_hospital(world, x, y)
    if not (Drag.hospital_footprint_valid(world, x, y) and Drag.hospital_affordable(world)) then
        return false
    end
    return World.build_hospital(world, x, y)
end

-- Place a 1×1 medical centre: tile must be plain grass, road-adjacent,
-- and treasury must cover the cost.
function Tools.apply_med_center(world, x, y)
    if not (Drag.med_center_valid(world, x, y) and Drag.med_center_affordable(world)) then
        return false
    end
    return World.build_med_center(world, x, y)
end

return Tools
