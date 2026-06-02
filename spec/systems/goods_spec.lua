-- spec/systems/goods_spec.lua
-- Goods system: typed-goods supply/demand/inventory accounting (Phase 5 step 2).
-- Mines (step 3) are not wired here; supply_rate returns {} until then.

local Goods = require("src.systems.goods")
local World = require("src.world.world")
local Bus   = require("src.bus")
local C     = require("src.world.constants")

local function build_ind(w, x, y)
    World.zone_tile(w, x, y, C.ZONE.INDUSTRIAL)
    World.start_building(w, x, y)
    World.complete_building(w, x, y)
end

describe("Goods", function()
    before_each(function() Bus.clear() end)

    describe("supply_rate", function()
        it("returns empty table when no mines exist", function()
            local w = World.new(1)
            assert.are.same({}, Goods.supply_rate(w))
        end)

        it("returns RAW_MATERIALS production for each placed mine", function()
            local w = World.new(1)
            local deposits = World.deposit_tiles(w)
            World.build_mine(w, deposits[1].x, deposits[1].y)
            local s = Goods.supply_rate(w)
            assert.are.equal(C.IRON_MINE.PRODUCTION, s[C.GOODS.RAW_MATERIALS])
        end)

        it("accumulates supply across multiple mines", function()
            local w = World.new(1)
            local deposits = World.deposit_tiles(w)
            World.build_mine(w, deposits[1].x, deposits[1].y)
            if #deposits >= 2 then
                World.build_mine(w, deposits[2].x, deposits[2].y)
                local s = Goods.supply_rate(w)
                assert.are.equal(2 * C.IRON_MINE.PRODUCTION, s[C.GOODS.RAW_MATERIALS])
            end
        end)
    end)

    describe("demand_rate", function()
        it("returns empty table for a city with no industrial buildings", function()
            local w = World.new(1)
            assert.are.same({}, Goods.demand_rate(w))
        end)

        it("sums RAW_MATERIALS demand across completed IND buildings", function()
            local w = World.new(1)
            build_ind(w, 30, 30)
            build_ind(w, 31, 30)
            local d = Goods.demand_rate(w)
            assert.are.equal(2 * C.IND_DEMAND[C.GOODS.RAW_MATERIALS],
                d[C.GOODS.RAW_MATERIALS])
        end)

        it("ignores under-construction IND buildings", function()
            local w = World.new(1)
            World.zone_tile(w, 30, 30, C.ZONE.INDUSTRIAL)
            World.start_building(w, 30, 30) -- constructing, not complete
            assert.are.same({}, Goods.demand_rate(w))
        end)

        it("ignores residential and commercial buildings", function()
            local w = World.new(1)
            World.zone_tile(w, 20, 20, C.ZONE.RESIDENTIAL)
            World.start_building(w, 20, 20)
            World.complete_building(w, 20, 20)
            World.zone_tile(w, 21, 20, C.ZONE.COMMERCIAL)
            World.start_building(w, 21, 20)
            World.complete_building(w, 21, 20)
            assert.are.same({}, Goods.demand_rate(w))
        end)
    end)

    describe("efficiency", function()
        it("returns 1 when demand is zero (no bottleneck)", function()
            local w = World.new(1)
            assert.are.equal(1, Goods.efficiency(w, C.GOODS.RAW_MATERIALS))
        end)

        it("returns 0 when demand > 0 and inventory is empty", function()
            local w = World.new(1)
            build_ind(w, 30, 30)
            -- Run one tick so demand is registered.
            Goods.system().tick(w)
            -- Inventory starts at 0, supply = 0 -> still 0.
            assert.are.equal(0, Goods.efficiency(w, C.GOODS.RAW_MATERIALS))
        end)

        it("returns 1 when inventory >= BUFFER_MONTHS * demand", function()
            local w = World.new(1)
            build_ind(w, 30, 30)
            Goods.system().tick(w)
            local dem = w.goods.demand[C.GOODS.RAW_MATERIALS] or 0
            w.goods.inventory[C.GOODS.RAW_MATERIALS] = dem * C.GOODS_TUNE.BUFFER_MONTHS
            assert.are.equal(1, Goods.efficiency(w, C.GOODS.RAW_MATERIALS))
        end)

        it("returns partial value when partially stocked", function()
            local w = World.new(1)
            build_ind(w, 30, 30)
            Goods.system().tick(w)
            local dem = w.goods.demand[C.GOODS.RAW_MATERIALS] or 0
            -- Half the buffer stocked => efficiency = 0.5.
            w.goods.inventory[C.GOODS.RAW_MATERIALS] =
                dem * C.GOODS_TUNE.BUFFER_MONTHS * 0.5
            local eff = Goods.efficiency(w, C.GOODS.RAW_MATERIALS)
            assert.is_true(math.abs(eff - 0.5) < 0.001)
        end)
    end)

    describe("system tick", function()
        it("updates world.goods.supply and demand each tick", function()
            local w = World.new(1)
            build_ind(w, 30, 30)
            Goods.system().tick(w)
            assert.are.same({}, w.goods.supply)
            assert.are.equal(C.IND_DEMAND[C.GOODS.RAW_MATERIALS],
                w.goods.demand[C.GOODS.RAW_MATERIALS])
        end)

        it("depletes inventory when demand exceeds supply", function()
            local w = World.new(1)
            build_ind(w, 30, 30)
            w.goods.inventory[C.GOODS.RAW_MATERIALS] = 10
            Goods.system().tick(w)
            local expected = math.max(0,
                10 - C.IND_DEMAND[C.GOODS.RAW_MATERIALS])
            assert.are.equal(expected,
                w.goods.inventory[C.GOODS.RAW_MATERIALS])
        end)

        it("clamps inventory to 0 (no negative stockpile)", function()
            local w = World.new(1)
            build_ind(w, 30, 30)
            -- inventory starts at 0; demand will push it negative without clamp
            Goods.system().tick(w)
            assert.are.equal(0, w.goods.inventory[C.GOODS.RAW_MATERIALS])
        end)

        it("clamps inventory to MAX_INVENTORY (no overflow)", function()
            local w = World.new(1)
            -- Force inventory above cap before tick.
            w.goods.inventory[C.GOODS.RAW_MATERIALS] = C.GOODS_TUNE.MAX_INVENTORY
            -- No industry -> demand = 0, supply = 0, net = 0: stays at cap.
            Goods.system().tick(w)
            assert.are.equal(C.GOODS_TUNE.MAX_INVENTORY,
                w.goods.inventory[C.GOODS.RAW_MATERIALS])
        end)

        it("mine supplies industry: inventory grows when supply > demand", function()
            local w = World.new(1)
            -- Place one mine (supply = PRODUCTION/month).
            local deposits = World.deposit_tiles(w)
            World.build_mine(w, deposits[1].x, deposits[1].y)
            -- No industry -> demand = 0; all supply goes to inventory.
            Goods.system().tick(w)
            assert.are.equal(C.IRON_MINE.PRODUCTION,
                w.goods.inventory[C.GOODS.RAW_MATERIALS])
        end)
    end)
end)
