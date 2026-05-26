-- spec/input/drag_spec.lua
-- Drag geometry is pure: given start/cursor tile coords (and the world, for the
-- rectangle's road-skipping), produce the set of tiles a drag would affect.
-- Roads paint an axis-only straight run; zones fill a rectangle minus any roads.
-- No love -- tested headless.

local Drag = require("src.input.drag")
local World = require("src.world.world")
local Grid = require("src.world.grid")
local C = require("src.world.constants")

-- "x,y" labels, sorted, for order-stable comparison.
local function labels(tiles)
    local out = {}
    for _, t in ipairs(tiles) do out[#out + 1] = t.x .. "," .. t.y end
    table.sort(out)
    return out
end

describe("Drag.road_run", function()
    it("runs horizontally for a pure horizontal drag", function()
        assert.are.same({ "1,1", "2,1", "3,1", "4,1" }, labels(Drag.road_run(1, 1, 4, 1)))
    end)

    it("runs vertically for a pure vertical drag", function()
        assert.are.same({ "1,1", "1,2", "1,3" }, labels(Drag.road_run(1, 1, 1, 3)))
    end)

    it("picks the dominant axis: horizontal when |dx| > |dy|", function()
        -- (1,1)->(4,2): dx=3 > dy=1, so a horizontal run at y=1, ignoring dy.
        assert.are.same({ "1,1", "2,1", "3,1", "4,1" }, labels(Drag.road_run(1, 1, 4, 2)))
    end)

    it("picks vertical when |dy| > |dx|", function()
        assert.are.same({ "1,1", "1,2", "1,3", "1,4" }, labels(Drag.road_run(1, 1, 2, 4)))
    end)

    it("breaks an axis tie toward horizontal", function()
        assert.are.same({ "1,1", "2,1", "3,1" }, labels(Drag.road_run(1, 1, 3, 3)))
    end)

    it("yields a single tile when start == end", function()
        assert.are.same({ "2,2" }, labels(Drag.road_run(2, 2, 2, 2)))
    end)

    it("handles a reversed drag (cursor left of start)", function()
        local run = Drag.road_run(4, 1, 1, 1)
        assert.are.equal(4, #run)
        assert.are.same({ "1,1", "2,1", "3,1", "4,1" }, labels(run))
    end)
end)

describe("Drag.zone_rect", function()
    it("fills the bounding box", function()
        local w = World.new(1)
        assert.are.equal(6, #Drag.zone_rect(w, 2, 2, 3, 4)) -- 2 wide x 3 tall
    end)

    it("normalizes corners regardless of drag direction", function()
        local w = World.new(1)
        assert.are.same(labels(Drag.zone_rect(w, 3, 4, 2, 2)), labels(Drag.zone_rect(w, 2, 2, 3, 4)))
    end)

    it("skips road tiles inside the box (zoning flows around them)", function()
        local w = World.new(1)
        Grid.get(w.grid, 3, 3).road = true -- one road inside a 2x3 box
        assert.are.equal(5, #Drag.zone_rect(w, 2, 2, 3, 4))
    end)

    it("skips power-line tiles inside the box", function()
        local w = World.new(1)
        World.build_power_line(w, 3, 3) -- one line inside a 2x3 box
        assert.are.equal(5, #Drag.zone_rect(w, 2, 2, 3, 4))
    end)

    it("skips power-plant tiles inside the box (zoning flows around the footprint)", function()
        local w = World.new(1)
        World.build_plant(w, 2, 2) -- 2x2 footprint fills (2,2),(3,2),(2,3),(3,3)
        -- A 3x3 box (2,2)-(4,4) = 9 tiles minus the 4 plant tiles = 5.
        assert.are.equal(5, #Drag.zone_rect(w, 2, 2, 4, 4))
    end)

    it("drops out-of-bounds tiles", function()
        local w = World.new(1)
        -- box partly off the top-left corner: only in-bounds tiles returned.
        local tiles = Drag.zone_rect(w, -1, -1, 2, 2)
        for _, t in ipairs(tiles) do
            assert.is_true(Grid.in_bounds(w.grid, t.x, t.y))
        end
        assert.are.equal(4, #tiles) -- (1,1),(2,1),(1,2),(2,2)
    end)
end)

describe("Drag road validity + cost", function()
    -- A road drag is transparent to existing roads (skipped, free) but blocked
    -- by zones/buildings (whole run invalid). Cost counts only grass tiles.
    describe("road_run_valid", function()
        it("is true for an all-grass run", function()
            local w = World.new(1)
            assert.is_true(Drag.road_run_valid(w, Drag.road_run(2, 2, 5, 2)))
        end)

        it("stays valid when the run crosses, starts, or ends on existing roads", function()
            local w = World.new(1)
            World.build_road(w, 3, 2) -- existing road mid-run
            World.build_road(w, 2, 2) -- existing road at the start
            assert.is_true(Drag.road_run_valid(w, Drag.road_run(2, 2, 5, 2)))
        end)

        it("is invalid if the run crosses a zoned tile", function()
            local w = World.new(1)
            World.zone_tile(w, 3, 2, C.ZONE.RESIDENTIAL)
            assert.is_false(Drag.road_run_valid(w, Drag.road_run(2, 2, 5, 2)))
        end)

        it("is invalid if the run crosses a building", function()
            local w = World.new(1)
            World.start_building(w, 3, 2)
            assert.is_false(Drag.road_run_valid(w, Drag.road_run(2, 2, 5, 2)))
        end)

        it("is invalid if any tile is off-grid", function()
            local w = World.new(1)
            assert.is_false(Drag.road_run_valid(w, Drag.road_run(1, 1, -3, 1)))
        end)

        it("is invalid if the run crosses a power plant (a solid structure)", function()
            local w = World.new(1)
            World.build_plant(w, 3, 2) -- footprint covers (3,2) on the run
            assert.is_false(Drag.road_run_valid(w, Drag.road_run(2, 2, 5, 2)))
        end)

        it("stays valid (transparent) when the run crosses a power line", function()
            local w = World.new(1)
            World.build_power_line(w, 3, 2) -- conductors coexist; the run skips it
            assert.is_true(Drag.road_run_valid(w, Drag.road_run(2, 2, 5, 2)))
        end)
    end)

    describe("road_cost", function()
        it("charges per grass tile in the run", function()
            local w = World.new(1)
            assert.are.equal(4 * C.ROAD.COST, Drag.road_cost(w, Drag.road_run(2, 2, 5, 2)))
        end)

        it("skips existing roads (transparent, not re-charged)", function()
            local w = World.new(1)
            World.build_road(w, 3, 2) -- one existing road in a 4-tile run
            assert.are.equal(3 * C.ROAD.COST, Drag.road_cost(w, Drag.road_run(2, 2, 5, 2)))
        end)

        it("skips existing power lines too (not grass, not built over)", function()
            local w = World.new(1)
            World.build_power_line(w, 3, 2) -- one existing line in a 4-tile run
            assert.are.equal(3 * C.ROAD.COST, Drag.road_cost(w, Drag.road_run(2, 2, 5, 2)))
        end)
    end)

    describe("road_affordable", function()
        it("is true exactly when the treasury covers the grass-tile cost", function()
            local w = World.new(1)
            local run = Drag.road_run(2, 2, 5, 2) -- 4 grass tiles
            w.treasury = 4 * C.ROAD.COST
            assert.is_true(Drag.road_affordable(w, run))
            w.treasury = 4 * C.ROAD.COST - 1
            assert.is_false(Drag.road_affordable(w, run))
        end)
    end)
end)

describe("Drag zone cost", function()
    local RES = C.ZONE.RESIDENTIAL

    it("charges per tile that actually changes zone", function()
        local w = World.new(1)
        local tiles = Drag.zone_rect(w, 2, 2, 3, 3) -- 4 grass tiles
        assert.are.equal(4 * C.ZONE_COST[RES], Drag.zone_cost(w, tiles, RES))
    end)

    it("skips tiles already in the target zone (re-zone is free)", function()
        local w = World.new(1)
        World.zone_tile(w, 2, 2, RES) -- already RES
        local tiles = Drag.zone_rect(w, 2, 2, 3, 3) -- still 4 tiles (no roads)
        assert.are.equal(3 * C.ZONE_COST[RES], Drag.zone_cost(w, tiles, RES))
    end)

    it("zone_affordable reflects the changed-tile cost", function()
        local w = World.new(1)
        local tiles = Drag.zone_rect(w, 2, 2, 3, 3)
        w.treasury = 4 * C.ZONE_COST[RES]
        assert.is_true(Drag.zone_affordable(w, tiles, RES))
        w.treasury = w.treasury - 1
        assert.is_false(Drag.zone_affordable(w, tiles, RES))
    end)
end)

describe("Drag power-line cost", function()
    -- A power line is a road clone: it reuses Drag.road_run for geometry and
    -- Drag.road_run_valid for validity. Only the per-tile price differs, so it
    -- gets its own cost/affordability pair keyed on C.POWER_LINE.COST.
    it("charges POWER_LINE.COST per grass tile in the run", function()
        local w = World.new(1)
        assert.are.equal(4 * C.POWER_LINE.COST, Drag.power_line_cost(w, Drag.road_run(2, 2, 5, 2)))
    end)

    it("skips existing roads and power lines (transparent, not charged)", function()
        local w = World.new(1)
        World.build_road(w, 3, 2)       -- road in the run
        World.build_power_line(w, 4, 2) -- line in the run
        assert.are.equal(2 * C.POWER_LINE.COST, Drag.power_line_cost(w, Drag.road_run(2, 2, 5, 2)))
    end)

    it("power_line_affordable reflects the grass-tile cost", function()
        local w = World.new(1)
        local run = Drag.road_run(2, 2, 5, 2) -- 4 grass tiles
        w.treasury = 4 * C.POWER_LINE.COST
        assert.is_true(Drag.power_line_affordable(w, run))
        w.treasury = w.treasury - 1
        assert.is_false(Drag.power_line_affordable(w, run))
    end)
end)

describe("Drag.plant_footprint", function()
    -- "x,y" labels, sorted, for order-stable comparison (mirrors the road_run helper).
    local function labels(tiles)
        local out = {}
        for _, t in ipairs(tiles) do out[#out + 1] = t.x .. "," .. t.y end
        table.sort(out)
        return out
    end

    it("returns the FOOTPRINT x FOOTPRINT square anchored at (x, y)", function()
        assert.are.same({ "2,2", "2,3", "3,2", "3,3" }, labels(Drag.plant_footprint(2, 2)))
    end)

    describe("plant_footprint_valid", function()
        it("is true on open grass", function()
            local w = World.new(1)
            assert.is_true(Drag.plant_footprint_valid(w, 2, 2))
        end)

        it("is false when the footprint runs off the grid", function()
            local w = World.new(1)
            assert.is_false(Drag.plant_footprint_valid(w, w.grid.width, 2))
            assert.is_false(Drag.plant_footprint_valid(w, 2, w.grid.height))
        end)

        it("is false when any footprint tile is occupied", function()
            local w = World.new(1)
            World.build_road(w, 3, 3) -- one corner of the (2,2) footprint
            assert.is_false(Drag.plant_footprint_valid(w, 2, 2))
        end)
    end)

    describe("plant cost", function()
        it("is the flat PLANT.COST", function()
            assert.are.equal(C.PLANT.COST, Drag.plant_cost())
        end)

        it("plant_affordable reflects the treasury against PLANT.COST", function()
            local w = World.new(1)
            w.treasury = C.PLANT.COST
            assert.is_true(Drag.plant_affordable(w))
            w.treasury = w.treasury - 1
            assert.is_false(Drag.plant_affordable(w))
        end)
    end)
end)
