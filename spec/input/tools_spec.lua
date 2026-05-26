-- spec/input/tools_spec.lua
-- Tools map a selected tool id to the matching world writer. No state, no
-- rendering knowledge -- just dispatch.

local Tools = require("src.input.tools")
local World = require("src.world.world")
local Drag = require("src.input.drag")
local Bus = require("src.bus")
local C = require("src.world.constants")

local function tile_at(w, x, y) return w.grid.tiles[w.grid.width * (y - 1) + x] end

describe("Tools", function()
    before_each(function() Bus.clear() end)

    it("ZONE_RES zones a tile residential", function()
        local w = World.new(1)
        assert.is_true(Tools.apply(C.TOOL.ZONE_RES, w, 2, 2))
        assert.are.equal(C.ZONE.RESIDENTIAL, w.grid.tiles[w.grid.width * 1 + 2].zone)
    end)

    it("ZONE_COM zones a tile commercial", function()
        local w = World.new(1)
        assert.is_true(Tools.apply(C.TOOL.ZONE_COM, w, 2, 2))
        assert.are.equal(C.ZONE.COMMERCIAL, w.grid.tiles[w.grid.width * 1 + 2].zone)
    end)

    it("ZONE_IND zones a tile industrial", function()
        local w = World.new(1)
        assert.is_true(Tools.apply(C.TOOL.ZONE_IND, w, 2, 2))
        assert.are.equal(C.ZONE.INDUSTRIAL, w.grid.tiles[w.grid.width * 1 + 2].zone)
    end)

    it("BULLDOZE clears zone and building", function()
        local w = World.new(1)
        Tools.apply(C.TOOL.ZONE_RES, w, 2, 2)
        World.start_building(w, 2, 2)
        assert.is_true(Tools.apply(C.TOOL.BULLDOZE, w, 2, 2))
        local tile = w.grid.tiles[w.grid.width * 1 + 2]
        assert.are.equal(C.ZONE.NONE, tile.zone)
        assert.is_nil(tile.building)
    end)

    it("returns false for an unknown tool", function()
        local w = World.new(1)
        assert.is_false(Tools.apply(999, w, 2, 2))
    end)

    describe("drag commit (all-or-nothing)", function()
        it("apply_run builds the whole road run when affordable", function()
            local w = World.new(1)
            local run = Drag.road_run(2, 2, 5, 2) -- 4 grass tiles
            assert.is_true(Tools.apply_run(w, run))
            for _, t in ipairs(run) do assert.is_true(tile_at(w, t.x, t.y).road) end
        end)

        it("apply_run builds nothing when unaffordable", function()
            local w = World.new(1)
            w.treasury = 3 * C.ROAD.COST -- need 4
            local run = Drag.road_run(2, 2, 5, 2)
            assert.is_false(Tools.apply_run(w, run))
            for _, t in ipairs(run) do assert.is_nil(tile_at(w, t.x, t.y).road) end
        end)

        it("apply_run builds nothing when the run crosses a zone", function()
            local w = World.new(1)
            World.zone_tile(w, 3, 2, C.ZONE.RESIDENTIAL)
            local run = Drag.road_run(2, 2, 5, 2)
            assert.is_false(Tools.apply_run(w, run))
            assert.is_nil(tile_at(w, 2, 2).road)
        end)

        it("apply_rect zones the whole rectangle when affordable", function()
            local w = World.new(1)
            local tiles = Drag.zone_rect(w, 2, 2, 3, 3)
            assert.is_true(Tools.apply_rect(C.TOOL.ZONE_RES, w, tiles))
            for _, t in ipairs(tiles) do
                assert.are.equal(C.ZONE.RESIDENTIAL, tile_at(w, t.x, t.y).zone)
            end
        end)

        it("apply_rect zones nothing when unaffordable", function()
            local w = World.new(1)
            local tiles = Drag.zone_rect(w, 2, 2, 3, 3) -- 4 tiles
            w.treasury = 3 * C.ZONE_COST[C.ZONE.RESIDENTIAL]
            assert.is_false(Tools.apply_rect(C.TOOL.ZONE_RES, w, tiles))
            assert.are.equal(C.ZONE.NONE, tile_at(w, 2, 2).zone)
        end)

        it("apply_line_run lays the whole power-line run when affordable", function()
            local w = World.new(1)
            local run = Drag.road_run(2, 2, 5, 2) -- 4 grass tiles
            assert.is_true(Tools.apply_line_run(w, run))
            for _, t in ipairs(run) do assert.is_true(tile_at(w, t.x, t.y).power_line) end
        end)

        it("apply_line_run lays nothing when unaffordable", function()
            local w = World.new(1)
            w.treasury = 3 * C.POWER_LINE.COST -- need 4
            local run = Drag.road_run(2, 2, 5, 2)
            assert.is_false(Tools.apply_line_run(w, run))
            for _, t in ipairs(run) do assert.is_nil(tile_at(w, t.x, t.y).power_line) end
        end)

        it("apply_line_run lays nothing when the run crosses a zone", function()
            local w = World.new(1)
            World.zone_tile(w, 3, 2, C.ZONE.RESIDENTIAL)
            local run = Drag.road_run(2, 2, 5, 2)
            assert.is_false(Tools.apply_line_run(w, run))
            assert.is_nil(tile_at(w, 2, 2).power_line)
        end)
    end)

    describe("zoning affordability gate", function()
        local function zoned_spy()
            local box = { called = 0 }
            Bus.subscribe(C.EVENTS.TILE_ZONED, function() box.called = box.called + 1 end)
            return box
        end

        it("zones when the treasury can afford the zone cost", function()
            local w = World.new(1)
            w.treasury = C.ZONE_COST[C.ZONE.COMMERCIAL] -- exactly enough
            assert.is_true(Tools.apply(C.TOOL.ZONE_COM, w, 2, 2))
            assert.are.equal(C.ZONE.COMMERCIAL, w.grid.tiles[w.grid.width * 1 + 2].zone)
        end)

        it("refuses and zones nothing when it can't afford it", function()
            local w = World.new(1)
            w.treasury = C.ZONE_COST[C.ZONE.INDUSTRIAL] - 1
            local spy = zoned_spy()
            assert.is_false(Tools.apply(C.TOOL.ZONE_IND, w, 2, 2))
            assert.are.equal(C.ZONE.NONE, w.grid.tiles[w.grid.width * 1 + 2].zone)
            assert.are.equal(0, spy.called)
        end)

        it("does not itself mutate the treasury (the economy debits)", function()
            local w = World.new(1)
            w.treasury = 500
            Tools.apply(C.TOOL.ZONE_RES, w, 2, 2)
            assert.are.equal(500, w.treasury)
        end)
    end)

    describe("ROAD tool", function()
        local function road_spy()
            local box = { called = 0 }
            Bus.subscribe(C.EVENTS.ROAD_BUILT, function() box.called = box.called + 1 end)
            return box
        end

        it("lays a road when the treasury can afford it", function()
            local w = World.new(1)
            w.treasury = C.ROAD.COST -- exactly enough
            local spy = road_spy()
            assert.is_true(Tools.apply(C.TOOL.ROAD, w, 2, 2))
            assert.is_true(w.grid.tiles[w.grid.width * 1 + 2].road)
            assert.are.equal(1, spy.called)
        end)

        it("refuses and lays nothing when the treasury can't afford it", function()
            local w = World.new(1)
            w.treasury = C.ROAD.COST - 1 -- one short
            local spy = road_spy()
            assert.is_false(Tools.apply(C.TOOL.ROAD, w, 2, 2))
            assert.is_nil(w.grid.tiles[w.grid.width * 1 + 2].road)
            assert.are.equal(0, spy.called)
        end)

        it("does not itself mutate the treasury (the economy debits)", function()
            local w = World.new(1)
            w.treasury = 500
            Tools.apply(C.TOOL.ROAD, w, 2, 2)
            assert.are.equal(500, w.treasury)
        end)
    end)

    describe("POWER_LINE tool", function()
        local function line_spy()
            local box = { called = 0 }
            Bus.subscribe(C.EVENTS.POWER_LINE_BUILT, function() box.called = box.called + 1 end)
            return box
        end

        it("lays a power line when the treasury can afford it", function()
            local w = World.new(1)
            w.treasury = C.POWER_LINE.COST
            local spy = line_spy()
            assert.is_true(Tools.apply(C.TOOL.POWER_LINE, w, 2, 2))
            assert.is_true(tile_at(w, 2, 2).power_line)
            assert.are.equal(1, spy.called)
        end)

        it("refuses and lays nothing when the treasury can't afford it", function()
            local w = World.new(1)
            w.treasury = C.POWER_LINE.COST - 1
            local spy = line_spy()
            assert.is_false(Tools.apply(C.TOOL.POWER_LINE, w, 2, 2))
            assert.is_nil(tile_at(w, 2, 2).power_line)
            assert.are.equal(0, spy.called)
        end)

        it("does not itself mutate the treasury (the economy debits)", function()
            local w = World.new(1)
            w.treasury = 500
            Tools.apply(C.TOOL.POWER_LINE, w, 2, 2)
            assert.are.equal(500, w.treasury)
        end)
    end)

    describe("PLANT tool", function()
        local function plant_spy()
            local box = { called = 0 }
            Bus.subscribe(C.EVENTS.PLANT_BUILT, function() box.called = box.called + 1 end)
            return box
        end

        it("places a 2x2 plant when affordable and the footprint is clear", function()
            local w = World.new(1)
            w.treasury = C.PLANT.COST
            local spy = plant_spy()
            assert.is_true(Tools.apply(C.TOOL.PLANT, w, 2, 2))
            assert.is_truthy(tile_at(w, 2, 2).plant)
            assert.are.equal(1, spy.called)
        end)

        it("refuses and builds nothing when unaffordable", function()
            local w = World.new(1)
            w.treasury = C.PLANT.COST - 1
            local spy = plant_spy()
            assert.is_false(Tools.apply(C.TOOL.PLANT, w, 2, 2))
            assert.is_nil(tile_at(w, 2, 2).plant)
            assert.are.equal(0, spy.called)
        end)

        it("refuses and builds nothing when the footprint is blocked", function()
            local w = World.new(1)
            w.treasury = C.PLANT.COST
            World.build_road(w, 3, 3) -- a corner of the (2,2) footprint
            local spy = plant_spy()
            assert.is_false(Tools.apply(C.TOOL.PLANT, w, 2, 2))
            assert.is_nil(tile_at(w, 2, 2).plant)
            assert.are.equal(0, spy.called)
        end)

        it("does not itself mutate the treasury (the economy debits)", function()
            local w = World.new(1)
            w.treasury = 500
            Tools.apply(C.TOOL.PLANT, w, 2, 2)
            assert.are.equal(500, w.treasury)
        end)
    end)
end)
