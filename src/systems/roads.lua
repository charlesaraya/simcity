-- src/systems/roads.lua
-- The road network as derived state. A road tile is "on the network" if it can
-- reach a map edge by walking road->road over 4-neighbors -- the edge is the
-- city's link to the outside world, so an isolated interior road connects to
-- nothing.

local Grid = require("src.world.grid")
local Network = require("src.systems.network")
local Bus = require("src.bus")
local C = require("src.world.constants")

local Roads = {}

local function is_edge(grid, x, y)
    return x == 1 or x == grid.width or y == 1 or y == grid.height
end

local function is_road(tile)
    return tile.road == true
end

-- A road is on the network iff its connected component touches a map edge -- the
-- edge is the city's link to the outside world, so an interior-only run connects
-- to nothing. Label every road component (NetworkedUtility), mark the ones with an
-- edge tile, then keep the tiles of those components. Returns a flat set {idx=true}.
function Roads.compute(grid)
    local component = Network.components(grid, is_road)

    local edge_reaching = {}
    Grid.each(grid, function(x, y, _)
        local cid = component[Grid.idx(grid, x, y)]
        if cid and is_edge(grid, x, y) then
            edge_reaching[cid] = true
        end
    end)

    local connected = {}
    for idx, cid in pairs(component) do
        if edge_reaching[cid] then
            connected[idx] = true
        end
    end
    return connected
end

-- Event-driven, like zoning: recompute the cache only when roads change. The
-- recompute runs once at install time too, so a fresh game gets an empty cache
-- and a loaded game rebuilds its cache from the saved road tiles.
function Roads.install(world)
    local function recompute()
        world.roads.connected = Roads.compute(world.grid)
    end
    Bus.subscribe(C.EVENTS.ROAD_BUILT, recompute)
    Bus.subscribe(C.EVENTS.ROAD_REMOVED, recompute)
    recompute()
end

-- READ: is (x, y) served by the network? True if any 4-neighbor is a road tile
-- that reaches a map edge (the shared NetworkedUtility query over the cached set).
function Roads.building_connected(world, x, y)
    return Network.adjacent(world.grid, world.roads.connected, x, y)
end

return Roads
