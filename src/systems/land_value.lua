-- src/systems/land_value.lua
-- Land value is a pure facade over the pollution field, NOT a field of its own:
-- land_value = clamp(BASE - K_POLLUTION * pollution, MIN, MAX). Because pollution
-- is already diffused, land value needs no diffusion, no cache, no install, and no
-- event subscription -- it is an O(1) read. This is the cleanest expression of
-- "land value is derived from pollution".
--
-- Phase 5 forward-compat: when amenity fields (parks, police) arrive, this becomes
-- BASE + amenities - K*pollution, and THAT second diffused field is the moment to
-- extract a shared DiffusionField. Not before -- 4b has only one diffusion instance.

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
