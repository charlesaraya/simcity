-- src/systems/roads.lua
-- The road network as derived state. A road tile is "on the network" if it can
-- reach a map edge by walking road->road over 4-neighbors -- the edge is the
-- city's link to the outside world, so an isolated interior road connects to
-- nothing.

local Grid = require("src.world.grid")
local Bus = require("src.bus")
local C = require("src.world.constants")

local Roads = {}

local function is_edge(grid, x, y)
    return x == 1 or x == grid.width or y == 1 or y == grid.height
end

-- Flood-fill from every edge road tile over road neighbors.
function Roads.compute(grid)
    local connected = {}
    local stack = {}

    -- Seed the frontier with road tiles sitting on a map edge.
    Grid.each(grid, function(x, y, tile)
        if tile.road and is_edge(grid, x, y) then
            local idx = Grid.idx(grid, x, y)
            if not connected[idx] then
                connected[idx] = true
                stack[#stack + 1] = { x, y }
            end
        end
    end)

    -- Walk inward: any road neighbor of a connected tile is itself connected.
    while #stack > 0 do
        local cell = table.remove(stack)
        for _, n in ipairs(Grid.neighbors(grid, cell[1], cell[2])) do
            local tile = Grid.get(grid, n.x, n.y)
            local idx = Grid.idx(grid, n.x, n.y)
            if tile.road and not connected[idx] then
                connected[idx] = true
                stack[#stack + 1] = { n.x, n.y }
            end
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
-- that reaches a map edge.
function Roads.building_connected(world, x, y)
    for _, n in ipairs(Grid.neighbors(world.grid, x, y)) do
        if world.roads.connected[Grid.idx(world.grid, n.x, n.y)] then
            return true
        end
    end
    return false
end

return Roads
