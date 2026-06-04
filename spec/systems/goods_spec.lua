-- spec/systems/goods_spec.lua
-- Goods system: typed-goods supply/demand/inventory accounting (Phase 5).
-- Step 5: supply_rate gates mine output on freight connectivity.

local Goods = require("src.systems.goods")
local Rails = require("src.systems.rails")
local World = require("src.world.world")
local Bus   = require("src.bus")
local C     = require("src.world.constants")

-- Place a rail tile on the first valid cardinal neighbor of (x, y) and
-- return its coords. Used to wire freight connectivity in supply_rate tests.
local function place_adjacent_rail(w, x, y)
    for _, d in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do
        local rx, ry = x + d[1], y + d[2]
        if World.build_rail(w, rx, ry) then return rx, ry end
    end
    error("no valid rail neighbor for (" .. x .. "," .. y .. ")")
end

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

        it("returns empty table for a mine with no freight connectivity", function()
            local w = World.new(1)
            local deposits = World.deposit_tiles(w)
            World.build_mine(w, deposits[1].x, deposits[1].y)
            -- No rail adjacent, no station: freight.bridged is empty.
            assert.are.same({}, Goods.supply_rate(w))
        end)

        it("returns RAW_MATERIALS production for a mine with freight connectivity", function()
            local w = World.new(1)
            local deposits = World.deposit_tiles(w)
            local d = deposits[1]
            World.build_mine(w, d.x, d.y)
            local rx, ry = place_adjacent_rail(w, d.x, d.y)
            Rails.install(w)
            local cid = Rails.tile_component(w, rx, ry)
            w.freight.bridged[cid] = true
            local s = Goods.supply_rate(w)
            assert.are.equal(C.IRON_MINE.PRODUCTION, s[C.GOODS.RAW_MATERIALS])
        end)

        it("whole cluster contributes when only one mine tile touches bridged rail", function()
            -- A 4-connected mine cluster shares freight access: one rail neighbour
            -- on any member tile makes the entire cluster productive.
            local w = World.new(1)
            local deposits = World.deposit_tiles(w)
            local dirs = {{1,0},{-1,0},{0,1},{0,-1}}
            local dep_map = {}
            for _, d in ipairs(deposits) do dep_map[d.x..","..d.y] = d end
            -- Find any two 4-connected deposit tiles.
            local d1, d2
            for _, da in ipairs(deposits) do
                for _, dir in ipairs(dirs) do
                    local key = (da.x+dir[1])..",".. (da.y+dir[2])
                    if dep_map[key] then d1, d2 = da, dep_map[key]; break end
                end
                if d1 then break end
            end
            if not d1 then return end -- seed has no adjacent pair; skip
            World.build_mine(w, d1.x, d1.y)
            World.build_mine(w, d2.x, d2.y)
            -- Place rail adjacent to d1 only, on a non-deposit tile.
            local rx, ry
            for _, dir in ipairs(dirs) do
                local nx, ny = d1.x+dir[1], d1.y+dir[2]
                if not dep_map[nx..","..ny] and World.build_rail(w, nx, ny) then
                    rx, ry = nx, ny; break
                end
            end
            if not rx then return end -- couldn't wire rail; skip
            Rails.install(w)
            local cid = Rails.tile_component(w, rx, ry)
            w.freight.bridged[cid] = true
            -- Both mines contribute because the cluster shares the single rail link.
            local s = Goods.supply_rate(w)
            assert.are.equal(2 * C.IRON_MINE.PRODUCTION, s[C.GOODS.RAW_MATERIALS])
        end)

        it("accumulates supply across multiple bridged mines", function()
            local w = World.new(1)
            local deposits = World.deposit_tiles(w)
            if #deposits < 2 then return end  -- guard: needs at least 2 deposit tiles
            local d1, d2 = deposits[1], deposits[2]
            World.build_mine(w, d1.x, d1.y)
            World.build_mine(w, d2.x, d2.y)
            -- Wire both mines to rail; they may share a component if deposits are adjacent.
            local rx1, ry1 = place_adjacent_rail(w, d1.x, d1.y)
            local rx2, ry2 = place_adjacent_rail(w, d2.x, d2.y)
            Rails.install(w)
            local cid1 = Rails.tile_component(w, rx1, ry1)
            local cid2 = Rails.tile_component(w, rx2, ry2)
            w.freight.bridged[cid1] = true
            if cid2 then w.freight.bridged[cid2] = true end
            local s = Goods.supply_rate(w)
            assert.are.equal(2 * C.IRON_MINE.PRODUCTION, s[C.GOODS.RAW_MATERIALS])
        end)
    end)

    describe("supply_rate (food)", function()
        local function build_agri(w, x, y)
            World.zone_tile(w, x, y, C.ZONE.AGRICULTURAL)
            World.start_building(w, x, y)
            World.complete_building(w, x, y)
        end

        it("returns zero food when no agricultural buildings exist", function()
            local w = World.new(1)
            assert.is_nil(Goods.supply_rate(w)[C.GOODS.FOOD])
        end)

        it("produces food proportional to tile fertility", function()
            local w = World.new(1)
            build_agri(w, 30, 30)
            -- Manually set fertility to a known value for exact assertion.
            local tile = w.grid.tiles[w.grid.width * 29 + 30]
            tile.fertility = 1.0
            local s = Goods.supply_rate(w)
            assert.are.equal(C.FARM.PRODUCTION, s[C.GOODS.FOOD])
        end)

        it("scales food output with fertility < 1", function()
            local w = World.new(1)
            build_agri(w, 30, 30)
            local tile = w.grid.tiles[w.grid.width * 29 + 30]
            tile.fertility = 0.5
            local s = Goods.supply_rate(w)
            local expected = C.FARM.PRODUCTION * 0.5
            assert.is_true(math.abs(s[C.GOODS.FOOD] - expected) < 0.001)
        end)

        it("zero fertility farm produces no food", function()
            local w = World.new(1)
            build_agri(w, 30, 30)
            local tile = w.grid.tiles[w.grid.width * 29 + 30]
            tile.fertility = 0
            local s = Goods.supply_rate(w)
            assert.are.equal(0, s[C.GOODS.FOOD] or 0)
        end)

        it("accumulates food across multiple farms", function()
            local w = World.new(1)
            build_agri(w, 30, 30)
            build_agri(w, 31, 30)
            local t1 = w.grid.tiles[w.grid.width * 29 + 30]
            local t2 = w.grid.tiles[w.grid.width * 29 + 31]
            t1.fertility = 1.0
            t2.fertility = 1.0
            local s = Goods.supply_rate(w)
            assert.are.equal(2 * C.FARM.PRODUCTION, s[C.GOODS.FOOD])
        end)
    end)

    describe("demand_rate", function()
        it("returns empty table for a city with no industrial buildings", function()
            local w = World.new(1)
            assert.are.same({}, Goods.demand_rate(w))
        end)

        it("returns empty table for a city with no buildings", function()
            local w = World.new(1)
            assert.are.same({}, Goods.demand_rate(w))
        end)

        it("sums FOOD demand across completed residential buildings", function()
            local w = World.new(1)
            World.zone_tile(w, 20, 20, C.ZONE.RESIDENTIAL)
            World.start_building(w, 20, 20)
            World.complete_building(w, 20, 20)
            World.zone_tile(w, 21, 20, C.ZONE.RESIDENTIAL)
            World.start_building(w, 21, 20)
            World.complete_building(w, 21, 20)
            local d = Goods.demand_rate(w)
            assert.are.equal(2 * C.RES_DEMAND[C.GOODS.FOOD], d[C.GOODS.FOOD])
        end)

        it("ignores under-construction residential buildings", function()
            local w = World.new(1)
            World.zone_tile(w, 20, 20, C.ZONE.RESIDENTIAL)
            World.start_building(w, 20, 20)  -- constructing, not complete
            assert.is_nil(Goods.demand_rate(w)[C.GOODS.FOOD])
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

        it("residential demands food; commercial demands processed goods", function()
            local w = World.new(1)
            World.zone_tile(w, 20, 20, C.ZONE.RESIDENTIAL)
            World.start_building(w, 20, 20)
            World.complete_building(w, 20, 20)
            World.zone_tile(w, 21, 20, C.ZONE.COMMERCIAL)
            World.start_building(w, 21, 20)
            World.complete_building(w, 21, 20)
            local d = Goods.demand_rate(w)
            assert.are.equal(C.RES_DEMAND[C.GOODS.FOOD], d[C.GOODS.FOOD])
            assert.are.equal(C.COM_DEMAND[C.GOODS.PROCESSED_GOODS], d[C.GOODS.PROCESSED_GOODS])
            assert.is_nil(d[C.GOODS.RAW_MATERIALS])
        end)

        it("sums PROCESSED_GOODS demand across completed COM buildings", function()
            local w = World.new(1)
            World.zone_tile(w, 20, 20, C.ZONE.COMMERCIAL)
            World.start_building(w, 20, 20)
            World.complete_building(w, 20, 20)
            World.zone_tile(w, 21, 20, C.ZONE.COMMERCIAL)
            World.start_building(w, 21, 20)
            World.complete_building(w, 21, 20)
            local d = Goods.demand_rate(w)
            assert.are.equal(2 * C.COM_DEMAND[C.GOODS.PROCESSED_GOODS],
                d[C.GOODS.PROCESSED_GOODS])
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
            -- First tick: raw_eff = 1 (no prior demand record) → full IND production.
            assert.are.equal(C.IND_DEMAND[C.GOODS.RAW_MATERIALS],
                w.goods.demand[C.GOODS.RAW_MATERIALS])
            assert.are.equal(C.IND_PRODUCTION,
                w.goods.supply[C.GOODS.PROCESSED_GOODS])
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

        it("mine supplies industry: inventory grows when supply > demand (with freight)", function()
            local w = World.new(1)
            local deposits = World.deposit_tiles(w)
            local d = deposits[1]
            World.build_mine(w, d.x, d.y)
            -- Wire freight connectivity so supply_rate counts this mine.
            local rx, ry = place_adjacent_rail(w, d.x, d.y)
            Rails.install(w)
            local cid = Rails.tile_component(w, rx, ry)
            w.freight.bridged[cid] = true
            -- No industry -> demand = 0; all supply goes to inventory.
            Goods.system().tick(w)
            assert.are.equal(C.IRON_MINE.PRODUCTION,
                w.goods.inventory[C.GOODS.RAW_MATERIALS])
        end)
    end)

    describe("supply_rate (processed goods)", function()
        it("IND produces PROCESSED_GOODS at full rate when raw materials are available", function()
            local w = World.new(1)
            build_ind(w, 30, 30)
            -- Pre-load raw materials so efficiency = 1.
            w.goods.demand[C.GOODS.RAW_MATERIALS] = C.IND_DEMAND[C.GOODS.RAW_MATERIALS]
            w.goods.inventory[C.GOODS.RAW_MATERIALS] =
                C.IND_DEMAND[C.GOODS.RAW_MATERIALS] * C.GOODS_TUNE.BUFFER_MONTHS
            local s = Goods.supply_rate(w)
            assert.are.equal(C.IND_PRODUCTION, s[C.GOODS.PROCESSED_GOODS])
        end)

        it("IND produces zero PROCESSED_GOODS when raw materials efficiency is zero", function()
            local w = World.new(1)
            build_ind(w, 30, 30)
            -- Force raw_eff = 0: demand > 0, inventory = 0.
            w.goods.demand[C.GOODS.RAW_MATERIALS] = 10
            w.goods.inventory[C.GOODS.RAW_MATERIALS] = 0
            local s = Goods.supply_rate(w)
            local produced = s[C.GOODS.PROCESSED_GOODS] or 0
            assert.are.equal(0, produced)
        end)

        it("scales proportionally with raw materials efficiency", function()
            local w = World.new(1)
            build_ind(w, 30, 30)
            -- Set raw_eff = 0.5: half buffer stocked.
            local dem = C.IND_DEMAND[C.GOODS.RAW_MATERIALS]
            w.goods.demand[C.GOODS.RAW_MATERIALS] = dem
            w.goods.inventory[C.GOODS.RAW_MATERIALS] = dem * C.GOODS_TUNE.BUFFER_MONTHS * 0.5
            local s = Goods.supply_rate(w)
            local expected = C.IND_PRODUCTION * 0.5
            assert.is_true(math.abs((s[C.GOODS.PROCESSED_GOODS] or 0) - expected) < 0.001)
        end)

        it("under-construction IND buildings contribute nothing", function()
            local w = World.new(1)
            World.zone_tile(w, 30, 30, C.ZONE.INDUSTRIAL)
            World.start_building(w, 30, 30)
            local s = Goods.supply_rate(w)
            assert.is_nil(s[C.GOODS.PROCESSED_GOODS])
        end)
    end)

    describe("supply_rate (medicine)", function()
        it("each hospital anchor produces HOSPITAL.PRODUCTION medicine per month", function()
            local w = World.new(1)
            World.build_road(w, 1, 2)
            World.build_hospital(w, 2, 2)
            local s = Goods.supply_rate(w)
            assert.are.equal(C.HOSPITAL.PRODUCTION, s[C.GOODS.MEDICINE] or 0)
        end)

        it("two hospitals produce twice the medicine", function()
            local w = World.new(1)
            World.build_road(w, 1, 2)
            World.build_hospital(w, 2, 2)
            World.build_road(w, 1, 6)
            World.build_hospital(w, 2, 6)
            local s = Goods.supply_rate(w)
            assert.are.equal(2 * C.HOSPITAL.PRODUCTION, s[C.GOODS.MEDICINE] or 0)
        end)

        it("returns no medicine when no hospital exists", function()
            local w = World.new(1)
            local s = Goods.supply_rate(w)
            assert.is_nil(s[C.GOODS.MEDICINE])
        end)
    end)

    describe("demand_rate (medicine)", function()
        it("completed RES buildings demand medicine via C.RES_DEMAND", function()
            local w = World.new(1)
            World.zone_tile(w, 2, 2, C.ZONE.RESIDENTIAL)
            World.start_building(w, 2, 2)
            World.complete_building(w, 2, 2)
            local d = Goods.demand_rate(w)
            assert.are.equal(C.RES_DEMAND[C.GOODS.MEDICINE], d[C.GOODS.MEDICINE])
        end)

        it("sums medicine demand across multiple completed RES buildings", function()
            local w = World.new(1)
            for x = 2, 4 do
                World.zone_tile(w, x, 2, C.ZONE.RESIDENTIAL)
                World.start_building(w, x, 2)
                World.complete_building(w, x, 2)
            end
            local d = Goods.demand_rate(w)
            assert.are.equal(3 * C.RES_DEMAND[C.GOODS.MEDICINE], d[C.GOODS.MEDICINE])
        end)
    end)
end)
