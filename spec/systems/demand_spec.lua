-- spec/systems/demand_spec.lua
-- Demand is pure logic over building counts. The compute() function is tested
-- directly; the system tick is smoke-tested against a built-up world.

local Demand = require("src.systems.demand")
local World = require("src.world.world")
local Bus = require("src.bus")
local C = require("src.world.constants")

describe("Demand", function()
    before_each(function() Bus.clear() end)

    describe("compute", function()
        it("seeds residential demand in an empty city", function()
            local rd, cd = Demand.compute(0, 0)
            assert.are.equal(C.DEMAND.BASE_RES, rd) -- positive, kickstarts growth
            assert.are.equal(0, cd)
        end)

        it("raises residential demand when commerce outnumbers housing", function()
            local rd = Demand.compute(0, 5) -- 0 res, 5 com
            assert.is_true(rd > C.DEMAND.BASE_RES)
        end)

        it("raises commercial demand when housing outnumbers commerce", function()
            local _, cd = Demand.compute(5, 0) -- 5 res, 0 com
            assert.is_true(cd > 0)
        end)

        it("clamps both demands to [-1, 1]", function()
            local rd1, cd1 = Demand.compute(0, 1000)
            local rd2, cd2 = Demand.compute(1000, 0)
            assert.are.equal(1, rd1)
            assert.is_true(cd1 >= -1)
            assert.are.equal(-1, rd2)
            assert.are.equal(1, cd2)
        end)
    end)

    describe("system", function()
        it("ticks monthly", function()
            assert.are.equal(C.SIM.SECONDS_PER_MONTH, Demand.system().interval)
        end)

        it("writes computed demand into world state from current counts", function()
            local w = World.new(1)
            -- one completed commercial building, no residential
            World.zone_tile(w, 1, 1, C.ZONE.COMMERCIAL)
            World.start_building(w, 1, 1)
            World.complete_building(w, 1, 1)

            Demand.system().tick(w)
            local rd, cd = Demand.compute(0, 1)
            assert.are.equal(rd, w.demand.residential)
            assert.are.equal(cd, w.demand.commercial)
        end)
    end)
end)
