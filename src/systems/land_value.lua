-- src/systems/land_value.lua
-- Land value is derived from pollution = clamp(BASE - K_POLLUTION * pollution, MIN, MAX).

local Grid = require("src.world.grid")
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

-- READ: {idx -> land value} for every polluted tile (the ones that differ from
-- BASE). Convenience for the overlay; clean tiles are implicitly BASE.
function LandValue.field(world)
    local out = {}
    for idx, pollution in pairs(world.pollution.field) do
        out[idx] = value_for(pollution)
    end
    return out
end

return LandValue
