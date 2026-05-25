-- src/systems/roads.lua
-- The road network as derived state. A road tile is "on the network" if it can
-- reach a map edge by walking road->road over 4-neighbors -- the edge is the
-- city's link to the outside world, so an isolated interior road connects to
-- nothing.

local Grid = require("src.world.grid")

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

return Roads
