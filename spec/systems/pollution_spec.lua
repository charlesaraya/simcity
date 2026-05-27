-- spec/systems/pollution_spec.lua
-- Pollution.compute is pure: given a grid, return {idx -> value}, the diffusion
-- field. Sources are COMPLETED industrial buildings and power plants; each paints
-- tiles within RADIUS with strength * (1 - dist/RADIUS) (linear falloff, Euclidean
-- distance), and overlapping sources add. Tested headless on small hand-built
-- grids -- no love, no ticking.

local Pollution = require("src.systems.pollution")
local World = require("src.world.world")
local Grid = require("src.world.grid")
local Bus = require("src.bus")
local C = require("src.world.constants")

-- Drop a building of `zone` in `state` directly on the grid (no growth mechanics).
local function place_building(grid, x, y, zone, state)
    local t = Grid.get(grid, x, y)
    t.zone = zone
    t.building = { state = state }
end

local function at(field, grid, x, y)
    return field[Grid.idx(grid, x, y)] or 0
end

-- Floats from the falloff: compare with a small tolerance.
local function near(actual, expected)
    assert.is_true(math.abs(actual - expected) < 1e-6,
        ("expected ~%s, got %s"):format(expected, actual))
end

describe("Pollution.compute", function()
    before_each(function() Bus.clear() end)

    it("returns an empty field when there are no sources", function()
        local w = World.new(1)
        assert.are.same({}, Pollution.compute(w.grid))
    end)

    it("pollutes a completed industrial building's own tile at full strength", function()
        local w = World.new(1)
        place_building(w.grid, 10, 10, C.ZONE.INDUSTRIAL, C.BUILD.COMPLETE)
        near(at(Pollution.compute(w.grid), w.grid, 10, 10), C.POLLUTION.IND_EMIT)
    end)

    it("falls off linearly with distance", function()
        local w = World.new(1)
        place_building(w.grid, 10, 10, C.ZONE.INDUSTRIAL, C.BUILD.COMPLETE)
        local field = Pollution.compute(w.grid)
        -- 3 tiles east: dist 3, falloff (1 - 3/RADIUS).
        local expected = C.POLLUTION.IND_EMIT * (1 - 3 / C.POLLUTION.RADIUS)
        near(at(field, w.grid, 13, 10), expected)
        -- Nearer is dirtier than farther.
        assert.is_true(at(field, w.grid, 11, 10) > at(field, w.grid, 13, 10))
    end)

    it("contributes nothing beyond RADIUS", function()
        local w = World.new(1)
        place_building(w.grid, 10, 10, C.ZONE.INDUSTRIAL, C.BUILD.COMPLETE)
        local field = Pollution.compute(w.grid)
        assert.are.equal(0, at(field, w.grid, 10 + C.POLLUTION.RADIUS + 1, 10))
    end)

    it("adds overlapping sources together", function()
        local w = World.new(1)
        place_building(w.grid, 10, 10, C.ZONE.INDUSTRIAL, C.BUILD.COMPLETE)
        place_building(w.grid, 12, 10, C.ZONE.INDUSTRIAL, C.BUILD.COMPLETE)
        local field = Pollution.compute(w.grid)
        -- Tile (11,10) sits 1 from each source: value = 2 * emit * (1 - 1/RADIUS).
        local one = C.POLLUTION.IND_EMIT * (1 - 1 / C.POLLUTION.RADIUS)
        near(at(field, w.grid, 11, 10), 2 * one)
    end)

    it("ignores residential, commercial, and still-constructing buildings", function()
        local w = World.new(1)
        place_building(w.grid, 5, 5, C.ZONE.RESIDENTIAL, C.BUILD.COMPLETE)
        place_building(w.grid, 20, 20, C.ZONE.COMMERCIAL, C.BUILD.COMPLETE)
        place_building(w.grid, 40, 40, C.ZONE.INDUSTRIAL, C.BUILD.CONSTRUCTING)
        assert.are.same({}, Pollution.compute(w.grid))
    end)

    it("a power plant emits from its anchor tile", function()
        local w = World.new(1)
        World.build_plant(w, 30, 30) -- anchor at (30,30)
        near(at(Pollution.compute(w.grid), w.grid, 30, 30), C.POLLUTION.PLANT_EMIT)
    end)
end)
