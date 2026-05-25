-- spec/systems/roads_spec.lua
-- Roads.compute is pure: given a grid, return the set of road-tile indices that
-- reach a map edge by walking road->road over 4-neighbors. The map edge is the
-- city's link to the outside world, so an isolated interior road connects to
-- nothing. Tested headless on small hand-built grids -- no love, no world.

local Roads = require("src.systems.roads")
local Grid = require("src.world.grid")
local World = require("src.world.world")
local Bus = require("src.bus")
local C = require("src.world.constants")

-- Lay roads at the given {x, y} pairs on a fresh w*h grass grid.
local function grid_with_roads(w, h, cells)
    local grid = Grid.new(w, h)
    for _, c in ipairs(cells) do
        Grid.get(grid, c[1], c[2]).road = true
    end
    return grid
end

-- Sorted list of "x,y" labels for the connected set, for order-stable asserts.
local function connected_coords(grid, set)
    local out = {}
    for idx in pairs(set) do
        local x, y = Grid.coord(grid, idx)
        out[#out + 1] = x .. "," .. y
    end
    table.sort(out)
    return out
end

describe("Roads.compute", function()
    it("returns an empty set when there are no roads", function()
        local grid = Grid.new(5, 5)
        assert.are.same({}, Roads.compute(grid))
    end)

    it("connects a chain that reaches the edge", function()
        -- Row y=3, x=1 (edge) .. x=3 (interior). All reach the edge via x=1.
        local grid = grid_with_roads(5, 5, { { 1, 3 }, { 2, 3 }, { 3, 3 } })
        assert.are.same({ "1,3", "2,3", "3,3" }, connected_coords(grid, Roads.compute(grid)))
    end)

    it("ignores an isolated interior loop that never touches an edge", function()
        -- A 2x2 block at the center: no tile is on an edge, none connect out.
        local grid = grid_with_roads(5, 5, { { 3, 3 }, { 4, 3 }, { 3, 4 }, { 4, 4 } })
        -- (4,4) is interior on a 5x5 grid -- edges are x/y in {1,5}.
        assert.are.same({}, Roads.compute(grid))
    end)

    it("splits the network when a connecting tile is removed", function()
        -- Edge-anchored chain x=1..4 at y=3.
        local grid = grid_with_roads(5, 5, { { 1, 3 }, { 2, 3 }, { 3, 3 }, { 4, 3 } })
        assert.are.same({ "1,3", "2,3", "3,3", "4,3" }, connected_coords(grid, Roads.compute(grid)))
        -- Remove x=2: x=1 still reaches the edge; x=3,4 are now stranded.
        Grid.get(grid, 2, 3).road = nil
        assert.are.same({ "1,3" }, connected_coords(grid, Roads.compute(grid)))
    end)

    it("counts a road on any of the four edges as connected", function()
        -- One road tile on each edge of a 5x5 grid, each isolated.
        local grid = grid_with_roads(5, 5, { { 1, 3 }, { 5, 3 }, { 3, 1 }, { 3, 5 } })
        assert.are.same({ "1,3", "3,1", "3,5", "5,3" }, connected_coords(grid, Roads.compute(grid)))
    end)
end)

describe("Roads.install", function()
    before_each(function() Bus.clear() end)

    it("populates the cache from pre-laid roads at install time", function()
        -- A road laid on the grid BEFORE install (e.g. as if loaded from a save).
        local w = World.new(1)
        Grid.get(w.grid, 1, 3).road = true -- x=1 is the map edge
        Roads.install(w)
        assert.is_true(w.roads.connected[Grid.idx(w.grid, 1, 3)])
    end)

    it("recomputes when a road is built after install", function()
        local w = World.new(1)
        Roads.install(w)
        assert.are.same({}, w.roads.connected)
        World.build_road(w, 1, 3)
        assert.is_true(w.roads.connected[Grid.idx(w.grid, 1, 3)])
    end)

    it("recomputes when a road is bulldozed", function()
        local w = World.new(1)
        Roads.install(w)
        World.build_road(w, 1, 3)
        World.bulldoze(w, 1, 3)
        assert.are.same({}, w.roads.connected)
    end)
end)

describe("Roads.building_connected", function()
    before_each(function() Bus.clear() end)

    it("is true for a tile adjacent to a connected (edge-reaching) road", function()
        local w = World.new(1)
        Roads.install(w)
        World.build_road(w, 1, 3) -- edge road, connected
        assert.is_true(Roads.building_connected(w, 2, 3))
    end)

    it("is false for a tile adjacent only to an isolated interior road", function()
        local w = World.new(1)
        Grid.get(w.grid, 10, 10).road = true -- interior, never reaches an edge
        Roads.install(w)
        assert.is_false(Roads.building_connected(w, 11, 10))
    end)

    it("is false when there are no roads at all", function()
        local w = World.new(1)
        Roads.install(w)
        assert.is_false(Roads.building_connected(w, 5, 5))
    end)
end)
