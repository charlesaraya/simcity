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
