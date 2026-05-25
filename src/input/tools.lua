-- src/input/tools.lua
-- The command layer: translate a selected tool into a world write. This is the
-- only place that maps "what the player picked" to "what changes in the world".
-- It holds no state (the current tool lives in the input layer) and knows
-- nothing about rendering or the bus -- the world writers publish the events.

local World = require("src.world.world")
local C = require("src.world.constants")

local Tools = {}

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
        -- Affordability gate: command layer refuses to build the road
        -- if the city can't afford it.
        if world.treasury < C.ROAD.COST then return false end
        return World.build_road(world, x, y)
    end
    return false
end

return Tools
