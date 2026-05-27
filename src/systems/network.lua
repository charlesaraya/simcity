-- src/systems/network.lua
-- NetworkedUtility: the connectivity skeleton shared by roads and power. Both are
-- networks of tiles laid on the grid, and both ask the same two questions:
--
--   1. Which tiles form a connected run? -- Network.components flood-fills a
--      caller-supplied membership predicate into connected components (4-neighbor),
--      labeling every member tile with its component id.
--   2. Is this building served by the network? -- Network.adjacent answers "does
--      (x, y) touch a tile in the served set?", the query both utilities expose.
--
-- The utilities layer their own meaning on top: roads keep only the components that
-- reach a map edge; power totals each component's supply and resolves capacity.
-- This module knows nothing about either -- it is pure graph plumbing, no love.

local Grid = require("src.world.grid")

local Network = {}

-- Flood-fill every member tile into connected components over 4-neighbors.
-- `is_member(tile)` decides membership. Returns the labeling `component` (a
-- {idx -> component id} table, ids counted up from 1) and the component `count`.
-- Iteration is in ascending index order, so ids are assigned deterministically.
function Network.components(grid, is_member)
    local component = {}
    local count = 0

    Grid.each(grid, function(x, y, tile)
        local idx = Grid.idx(grid, x, y)
        if is_member(tile) and not component[idx] then
            count = count + 1
            component[idx] = count
            local stack = { { x, y } }
            while #stack > 0 do
                local cell = table.remove(stack)
                for _, nb in ipairs(Grid.neighbors(grid, cell[1], cell[2])) do
                    local nidx = Grid.idx(grid, nb.x, nb.y)
                    if not component[nidx] and is_member(Grid.get(grid, nb.x, nb.y)) then
                        component[nidx] = count
                        stack[#stack + 1] = { nb.x, nb.y }
                    end
                end
            end
        end
    end)

    return component, count
end

-- READ: is (x, y) served? True if any 4-neighbor's index is present (truthy) in
-- `set`. Works for a flat connected set ({idx = true}) and a component labeling
-- ({idx = component id}) alike -- any truthy value counts as "in the network".
function Network.adjacent(grid, set, x, y)
    for _, nb in ipairs(Grid.neighbors(grid, x, y)) do
        if set[Grid.idx(grid, nb.x, nb.y)] then
            return true
        end
    end
    return false
end

return Network
