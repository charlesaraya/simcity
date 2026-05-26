-- src/systems/power.lua
-- The power network: the second networked utility, and the deliberate second
-- instance of the roads compute/install/query pattern (a NetworkedUtility will be
-- extracted once this exists). It diverges from roads in one way: capacity
-- and that divergence is split across two stages:
--
--   1. compute_topology: flood-fill the conducting medium into connected components
--      and total each component's supply.
--   2. resolve: allocate finite supply against the buildings' demand and decide which
--      components are lit.
--
-- The conducting medium is roads UNION power lines UNION plant footprints; all
-- three carry electricity. A plant only feeds the grid when its footprint touches
-- an edge-connected road (workers must be able to reach it), so supply reuses
-- the road connectivity cache.

local Grid = require("src.world.grid")
local Roads = require("src.systems.roads")
local C = require("src.world.constants")

local Power = {}

-- Every tile that carries current: a road, a power line, or any part of a plant.
local function is_conductor(tile)
    return tile ~= nil and (tile.road or tile.power_line or tile.plant or tile.plant_part)
end

-- Does this plant (anchor) touch an edge-connected road? Reuses the
-- road query over every footprint tile.
local function plant_has_road(world, ax, ay)
    local n = C.PLANT.FOOTPRINT
    for dy = 0, n - 1 do
        for dx = 0, n - 1 do
            if Roads.building_connected(world, ax + dx, ay + dy) then
                return true
            end
        end
    end
    return false
end

-- Flood-fill the conducting graph into components and sum each one's supply.
function Power.compute_topology(world)
    local grid = world.grid
    local component = {}
    local supply = {}
    local next_id = 0

    -- Label every conducting tile with its component, flooding over 4-neighbors.
    Grid.each(grid, function(x, y, tile)
        local idx = Grid.idx(grid, x, y)
        if is_conductor(tile) and not component[idx] then
            next_id = next_id + 1
            supply[next_id] = 0
            component[idx] = next_id
            local stack = { { x, y } }
            while #stack > 0 do
                local cell = table.remove(stack)
                for _, nb in ipairs(Grid.neighbors(grid, cell[1], cell[2])) do
                    local nidx = Grid.idx(grid, nb.x, nb.y)
                    if is_conductor(Grid.get(grid, nb.x, nb.y)) and not component[nidx] then
                        component[nidx] = next_id
                        stack[#stack + 1] = { nb.x, nb.y }
                    end
                end
            end
        end
    end)

    -- Add each road-connected plant's capacity to its component's supply. Only
    -- the anchor tile carries the plant record, so each plant is counted once.
    Grid.each(grid, function(x, y, tile)
        if tile.plant then
            local cid = component[Grid.idx(grid, x, y)]
            if cid and plant_has_road(world, x, y) then
                supply[cid] = supply[cid] + C.PLANT.CAPACITY
            end
        end
    end)

    return { component = component, supply = supply }
end

return Power
