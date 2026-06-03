-- src/systems/demand.lua
-- Each month, recompute residential, commercial, industrial, and agricultural
-- demand from current building counts and write them into world.demand. Growth
-- reads those values to decide what to build. This is one half of the feedback
-- loop (Principle 5).
--
-- The rule is a supply chain: residents chase jobs (com + ind), commerce needs
-- shoppers (res), industry needs commerce. Agricultural demand tracks residential
-- population: farms are needed wherever people live.

local World = require("src.world.world")
local C = require("src.world.constants")

local Demand = {}

local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

-- Pure: building counts -> (residential, commercial, industrial, agricultural
-- demand), each in [-1, 1].
--   residents chase opportunity -> rd rises while res < jobs * JOB_PULL
--   commerce serves homes        -> cd rises while com < res * COM_PER_RES
--   industry supplies shops      -> id rises while ind < com * IND_PER_COM
--   farms feed residents         -> ad rises while agri < res * FARM_PER_RES
-- JOB_PULL > 1 is self-amplifying. BASE_RES seeds the empty city.
function Demand.compute(res, com, ind, agri)
    agri = agri or 0
    local jobs = com + ind
    local rd = clamp(C.DEMAND.BASE_RES + (jobs * C.DEMAND.JOB_PULL - res) * C.DEMAND.SENS, -1, 1)
    local cd = clamp((res * C.DEMAND.COM_PER_RES  - com)  * C.DEMAND.SENS, -1, 1)
    local id = clamp((com * C.DEMAND.IND_PER_COM  - ind)  * C.DEMAND.SENS, -1, 1)
    local ad = clamp((res * C.DEMAND.FARM_PER_RES - agri) * C.DEMAND.SENS, -1, 1)
    return rd, cd, id, ad
end

function Demand.system()
    return {
        interval = C.SIM.SECONDS_PER_MONTH,
        accumulator = 0,
        tick = function(world)
            local res   = World.count_buildings(world, C.ZONE.RESIDENTIAL,  C.BUILD.COMPLETE)
            local com   = World.count_buildings(world, C.ZONE.COMMERCIAL,   C.BUILD.COMPLETE)
            local ind   = World.count_buildings(world, C.ZONE.INDUSTRIAL,   C.BUILD.COMPLETE)
            local agri  = World.count_buildings(world, C.ZONE.AGRICULTURAL, C.BUILD.COMPLETE)
            local rd, cd, id, ad = Demand.compute(res, com, ind, agri)
            world.demand.residential  = rd
            world.demand.commercial   = cd
            world.demand.industrial   = id
            world.demand.agricultural = ad
        end,
    }
end

return Demand
