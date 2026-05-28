-- src/systems/land_value.lua
-- Land value is derived from pollution = clamp(BASE - K_POLLUTION * pollution, MIN, MAX).

local Pollution = require("src.systems.pollution")
local C = require("src.world.constants")

local LandValue = {}

local function value_for(pollution)
    local v = C.LAND.BASE - C.LAND.K_POLLUTION * pollution
    if v < C.LAND.MIN then return C.LAND.MIN end
    if v > C.LAND.MAX then return C.LAND.MAX end
    return v
end

-- READ: land value at (x, y). A clean tile reads BASE.
function LandValue.at(world, x, y)
    return value_for(Pollution.at(world, x, y))
end

return LandValue
