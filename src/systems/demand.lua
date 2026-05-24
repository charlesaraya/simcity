-- src/systems/demand.lua
-- Each month, recompute residential and commercial demand from current building
-- counts and write them into world.demand. Growth reads those values to decide
-- what to build. This is one half of the feedback loop (Principle 5).
--
-- The rule (blueprint, deliberately trivial for Phase 1):
--   residential demand rises when commerce outnumbers housing,
--   commercial demand rises when housing outnumbers commerce,
-- plus a residential baseline so an empty city has somewhere to start.

local World = require("src.world.world")
local C = require("src.world.constants")

local Demand = {}

local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

-- Pure: building counts -> (residential demand, commercial demand), each [-1,1].
function Demand.compute(res, com)
    local rd = clamp(C.DEMAND.BASE_RES + (com - res) * C.DEMAND.SENS, -1, 1)
    local cd = clamp((res - com) * C.DEMAND.SENS, -1, 1)
    return rd, cd
end

function Demand.system()
    return {
        interval = C.SIM.SECONDS_PER_MONTH,
        accumulator = 0,
        tick = function(world)
            local res = World.count_buildings(world, C.ZONE.RESIDENTIAL, C.BUILD.COMPLETE)
            local com = World.count_buildings(world, C.ZONE.COMMERCIAL, C.BUILD.COMPLETE)
            local rd, cd = Demand.compute(res, com)
            world.demand.residential = rd
            world.demand.commercial = cd
        end,
    }
end

return Demand
