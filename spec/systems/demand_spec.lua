-- spec/systems/demand_spec.lua
-- Demand is pure logic over building counts. The compute() function is tested
-- directly; the system tick is smoke-tested against a built-up world.

local Demand = require("src.systems.demand")
local World = require("src.world.world")
local Bus = require("src.bus")
local C = require("src.world.constants")

describe("Demand", function()
    before_each(function() Bus.clear() end)

    -- compute(res, com, ind) -> residential, commercial, industrial demand.
    -- The supply chain: residents chase jobs (com + ind); commerce needs
    -- shoppers (res); industry needs commerce to sell its goods.
    describe("compute", function()
        it("seeds only residential demand in an empty city", function()
            local rd, cd, id = Demand.compute(0, 0, 0)
            assert.are.equal(C.DEMAND.BASE_RES, rd) -- the single seed
            assert.are.equal(0, cd)
            assert.are.equal(0, id)
        end)

        it("raises residential demand when commercial jobs outnumber housing", function()
            local rd = Demand.compute(0, 5, 0) -- 0 res, 5 com, 0 ind
            assert.is_true(rd > C.DEMAND.BASE_RES)
        end)

        it("raises residential demand when industrial jobs outnumber housing too", function()
            local rd = Demand.compute(0, 0, 5) -- jobs = com + ind, so ind pulls residents
            assert.is_true(rd > C.DEMAND.BASE_RES)
        end)

        it("raises commercial demand when residents outnumber commerce", function()
            local _, cd = Demand.compute(5, 0, 0)
            assert.is_true(cd > 0)
        end)

        it("raises industrial demand when commerce outnumbers industry", function()
            local _, _, id = Demand.compute(0, 5, 0) -- commerce needs goods to sell
            assert.is_true(id > 0)
        end)

        it("clamps all three demands to [-1, 1]", function()
            local rd1, cd1, id1 = Demand.compute(0, 0, 1000)
            local rd2, cd2, id2 = Demand.compute(1000, 0, 0)
            assert.are.equal(1, rd1)  -- jobs flood -> max residential
            assert.are.equal(-1, id1) -- industry outnumbers commerce -> min industrial
            assert.are.equal(-1, rd2) -- housing floods, no jobs -> min residential
            assert.are.equal(1, cd2)  -- residents flood -> max commercial
            assert.is_true(cd1 >= -1 and id2 >= -1)
        end)
    end)

    describe("system", function()
        it("ticks monthly", function()
            assert.are.equal(C.SIM.SECONDS_PER_MONTH, Demand.system().interval)
        end)

        it("writes all three demands into world state from current counts", function()
            local w = World.new(1)
            -- one completed commercial building, no residential, no industrial
            World.zone_tile(w, 1, 1, C.ZONE.COMMERCIAL)
            World.start_building(w, 1, 1)
            World.complete_building(w, 1, 1)

            Demand.system().tick(w)
            local rd, cd, id = Demand.compute(0, 1, 0)
            assert.are.equal(rd, w.demand.residential)
            assert.are.equal(cd, w.demand.commercial)
            assert.are.equal(id, w.demand.industrial)
        end)
    end)
end)
