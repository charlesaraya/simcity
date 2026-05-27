-- spec/systems/network_spec.lua
-- NetworkedUtility is the connectivity skeleton shared by roads and power: a pure
-- flood-fill that labels member tiles into connected components, plus the neighbor
-- query both utilities use to ask "is (x, y) served?". Tested headless on small
-- hand-built grids -- no love, no world. The membership predicate is supplied by
-- the caller (roads pass tile.road; power passes "any conductor").

local Network = require("src.systems.network")
local Grid = require("src.world.grid")

-- Flag the given {x, y} cells as members on a fresh w*h grid.
local function grid_with_members(w, h, cells)
    local grid = Grid.new(w, h)
    for _, c in ipairs(cells) do
        Grid.get(grid, c[1], c[2]).on = true
    end
    return grid
end

local function is_on(tile)
    return tile.on == true
end

-- The component id at (x, y), or nil.
local function id_at(grid, component, x, y)
    return component[Grid.idx(grid, x, y)]
end

describe("Network.components", function()
    it("returns an empty labeling and zero count when nothing is a member", function()
        local grid = Grid.new(5, 5)
        local component, count = Network.components(grid, is_on)
        assert.are.same({}, component)
        assert.are.equal(0, count)
    end)

    it("labels a single member tile as one component", function()
        local grid = grid_with_members(5, 5, { { 3, 3 } })
        local component, count = Network.components(grid, is_on)
        assert.are.equal(1, count)
        assert.is_not_nil(id_at(grid, component, 3, 3))
    end)

    it("gives one component to a 4-neighbor connected chain", function()
        local grid = grid_with_members(5, 5, { { 1, 3 }, { 2, 3 }, { 3, 3 } })
        local component, count = Network.components(grid, is_on)
        assert.are.equal(1, count)
        local id = id_at(grid, component, 1, 3)
        assert.are.equal(id, id_at(grid, component, 2, 3))
        assert.are.equal(id, id_at(grid, component, 3, 3))
    end)

    it("splits disjoint blobs into separate components", function()
        -- Two separate horizontal pairs, a gap between them.
        local grid = grid_with_members(7, 5, { { 1, 3 }, { 2, 3 }, { 6, 3 }, { 7, 3 } })
        local component, count = Network.components(grid, is_on)
        assert.are.equal(2, count)
        local left = id_at(grid, component, 1, 3)
        local right = id_at(grid, component, 6, 3)
        assert.are.equal(left, id_at(grid, component, 2, 3))
        assert.are.equal(right, id_at(grid, component, 7, 3))
        assert.are_not.equal(left, right)
    end)

    it("does not connect diagonally (4-neighbor only)", function()
        -- (2,2) and (3,3) touch only at a corner.
        local grid = grid_with_members(5, 5, { { 2, 2 }, { 3, 3 } })
        local _, count = Network.components(grid, is_on)
        assert.are.equal(2, count)
    end)
end)

describe("Network.adjacent", function()
    it("is true when a 4-neighbor is present in the set", function()
        local grid = Grid.new(5, 5)
        local set = { [Grid.idx(grid, 2, 3)] = true }
        assert.is_true(Network.adjacent(grid, set, 3, 3))
    end)

    it("is false when no 4-neighbor is in the set", function()
        local grid = Grid.new(5, 5)
        local set = { [Grid.idx(grid, 1, 1)] = true }
        assert.is_false(Network.adjacent(grid, set, 3, 3))
    end)

    it("works on a component map (truthy non-boolean values)", function()
        -- Power stores idx -> component id, not idx -> true. Any truthy value counts.
        local grid = Grid.new(5, 5)
        local component = { [Grid.idx(grid, 2, 3)] = 7 }
        assert.is_true(Network.adjacent(grid, component, 3, 3))
    end)

    it("skips off-grid neighbors at a corner without erroring", function()
        local grid = Grid.new(5, 5)
        assert.is_false(Network.adjacent(grid, {}, 1, 1))
    end)
end)
