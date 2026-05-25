-- src/systems/demand.lua
-- Each month, recompute residential, commercial, and industrial demand from
-- current building counts and write them into world.demand. Growth reads those
-- values to decide what to build. This is one half of the feedback loop
-- (Principle 5).
--
-- The rule is a supply chain (Phase 2): residents chase jobs (com + ind),
-- commerce needs shoppers (res), industry needs commerce to sell its goods.
-- A single residential baseline seeds the cascade RES -> COM -> IND; industrial
-- jobs feed back into residential demand to close the loop.

local World = require("src.world.world")
local C = require("src.world.constants")

local Demand = {}

local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

-- Pure: building counts -> (residential, commercial, industrial demand), each
-- in [-1, 1]. A supply chain with FRACTIONAL targets downstream so the city settles ~4:2:1:
--   residents chase opportunity -> rd rises while res < jobs * JOB_PULL
--   commerce serves homes        -> cd rises while com < res * COM_PER_RES
--   industry supplies shops      -> id rises while ind < com * IND_PER_COM
-- JOB_PULL > 1 makes the loop self-amplifying: residents always trail job
-- opportunity, so there's no fixed point and the city grows perpetually in
-- ratio. BASE_RES seeds the empty city before any jobs exist.
function Demand.compute(res, com, ind)
    local jobs = com + ind
    local rd = clamp(C.DEMAND.BASE_RES + (jobs * C.DEMAND.JOB_PULL - res) * C.DEMAND.SENS, -1, 1)
    local cd = clamp((res * C.DEMAND.COM_PER_RES - com) * C.DEMAND.SENS, -1, 1)
    local id = clamp((com * C.DEMAND.IND_PER_COM - ind) * C.DEMAND.SENS, -1, 1)
    return rd, cd, id
end

function Demand.system()
    return {
        interval = C.SIM.SECONDS_PER_MONTH,
        accumulator = 0,
        tick = function(world)
            local res = World.count_buildings(world, C.ZONE.RESIDENTIAL, C.BUILD.COMPLETE)
            local com = World.count_buildings(world, C.ZONE.COMMERCIAL, C.BUILD.COMPLETE)
            local ind = World.count_buildings(world, C.ZONE.INDUSTRIAL, C.BUILD.COMPLETE)
            local rd, cd, id = Demand.compute(res, com, ind)
            world.demand.residential = rd
            world.demand.commercial = cd
            world.demand.industrial = id
        end,
    }
end

return Demand
