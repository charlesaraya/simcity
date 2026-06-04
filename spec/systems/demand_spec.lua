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

        it("sizes commerce as a fraction of residents, not 1:1", function()
            -- 4 res, 4 com: under the old 1:1 rule cd would be 0 (balanced).
            -- Now commerce targets only a fraction of residents, so 4 com is an
            -- oversupply -> negative commercial demand.
            local _, cd = Demand.compute(4, 4, 0)
            assert.is_true(cd < 0)
        end)

        it("sizes industry as a fraction of commerce, not 1:1", function()
            local _, _, id = Demand.compute(0, 4, 4) -- 4 ind vs 4 com: oversupplied
            assert.is_true(id < 0)
        end)

        it("holds the 4:2:1 shape: commerce and industry stay balanced at the ratio", function()
            -- At 4 res / 2 com / 1 ind the downstream tiers are neutral:
            -- com = res * COM_PER_RES, ind = com * IND_PER_COM.
            local _, cd, id = Demand.compute(4, 2, 1)
            assert.are.equal(0, cd)
            assert.are.equal(0, id)
        end)

        it("never stalls: residential demand stays positive at the 4:2:1 balance", function()
            -- Job opportunity (JOB_PULL > 1) keeps residents arriving even when the
            -- city is perfectly in ratio -- so there is no fixed point and growth
            -- continues. Old closed-loop model gave rd = 0 here.
            local rd1 = Demand.compute(12, 6, 3)
            local rd2 = Demand.compute(120, 60, 30) -- and at 10x scale
            assert.is_true(rd1 > 0)
            assert.is_true(rd2 > 0)
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

        it("returns zero agricultural demand when there are no residents", function()
            local _, _, _, ad = Demand.compute(0, 0, 0, 0)
            assert.are.equal(0, ad)
        end)

        it("raises agricultural demand when residents outnumber farms", function()
            -- 10 residents, 0 farms: demand should be positive
            local _, _, _, ad = Demand.compute(10, 0, 0, 0)
            assert.is_true(ad > 0)
        end)

        it("lowers agricultural demand as farms catch up to residents", function()
            local _, _, _, ad_low  = Demand.compute(10, 0, 0, 0)
            local _, _, _, ad_high = Demand.compute(10, 0, 0, 4) -- 4 farms serving 10 res
            assert.is_true(ad_high < ad_low)
        end)

        it("clamps agricultural demand to [-1, 1]", function()
            local _, _, _, ad_pos = Demand.compute(1000, 0, 0, 0)
            local _, _, _, ad_neg = Demand.compute(0,    0, 0, 1000)
            assert.are.equal( 1, ad_pos)
            assert.are.equal(-1, ad_neg)
        end)

        it("defaults agri arg to 0 (back-compat)", function()
            local _, _, _, ad = Demand.compute(10, 0, 0)
            local _, _, _, ad2 = Demand.compute(10, 0, 0, 0)
            assert.are.equal(ad, ad2)
        end)

        it("defaults raw_eff to 1 (back-compat)", function()
            local _, _, id1 = Demand.compute(0, 5, 0, 0)
            local _, _, id2 = Demand.compute(0, 5, 0, 0, 1)
            assert.are.equal(id1, id2)
        end)

        it("IND demand is zero when raw_eff is zero (no raw materials)", function()
            -- Commerce present but no raw materials → no point building industry.
            local _, _, id = Demand.compute(0, 5, 0, 0, 0)
            assert.are.equal(0, id)
        end)

        it("IND demand scales proportionally with raw_eff", function()
            local _, _, id_full = Demand.compute(0, 5, 0, 0, 1)
            local _, _, id_half = Demand.compute(0, 5, 0, 0, 0.5)
            assert.is_true(id_full > 0)
            assert.is_true(math.abs(id_half - id_full * 0.5) < 0.001)
        end)

        it("IND oversupply abandon signal unaffected by raw_eff (negative demand stays negative)", function()
            -- More IND than COM needs → negative demand regardless of raw_eff.
            local _, _, id_raw0 = Demand.compute(0, 1, 10, 0, 0)
            local _, _, id_raw1 = Demand.compute(0, 1, 10, 0, 1)
            assert.is_true(id_raw0 < 0)
            assert.is_true(id_raw1 < 0)
        end)
    end)

    describe("system", function()
        it("ticks monthly", function()
            assert.are.equal(C.SIM.SECONDS_PER_MONTH, Demand.system().interval)
        end)

        it("writes all four demands into world state from current counts", function()
            local w = World.new(1)
            -- one completed commercial building, no residential, no industrial
            World.zone_tile(w, 1, 1, C.ZONE.COMMERCIAL)
            World.start_building(w, 1, 1)
            World.complete_building(w, 1, 1)

            Demand.system().tick(w)
            local rd, cd, id, ad = Demand.compute(0, 1, 0, 0)
            assert.are.equal(rd, w.demand.residential)
            assert.are.equal(cd, w.demand.commercial)
            assert.are.equal(id, w.demand.industrial)
            assert.are.equal(ad, w.demand.agricultural)
        end)
    end)
end)
