-- src/systems/rails.lua
-- Freight rail network as derived state (Phase 5 step 4).
-- Unlike roads, rail components do NOT need to reach a map edge: any
-- connected run of rail tiles forms a valid component. The Freight Station
-- (step 5) bridges a road component to a rail component; goods flow only when
-- that bridge exists.

local Grid    = require("src.world.grid")
local Network = require("src.systems.network")
local Bus     = require("src.bus")
local C       = require("src.world.constants")

local Rails = {}

local function is_rail(tile)
    return tile.rail == true
end

-- Compute the rail component labeling: every rail tile is assigned the integer
-- id of its connected component. Returns {tile_idx -> component_id}.
function Rails.compute(grid)
    local component = Network.components(grid, is_rail)
    return component
end

-- Recompute the cached component table when the rail network changes.
-- Also accepts a pre-built world table missing world.rails (old saves) and
-- initialises the field before writing.
function Rails.install(world)
    if not world.rails then world.rails = {} end
    local function recompute()
        world.rails.components = Rails.compute(world.grid)
    end
    Bus.subscribe(C.EVENTS.RAIL_BUILT,   recompute)
    Bus.subscribe(C.EVENTS.RAIL_REMOVED, recompute)
    recompute()
end

-- READ: component id of the rail tile at (x, y), or nil if not rail.
function Rails.tile_component(world, x, y)
    return world.rails.components[Grid.idx(world.grid, x, y)]
end

-- READ: component id of the rail network adjacent to (x, y), or nil if no
-- rail neighbor exists. Returns the first match (all neighbors share a
-- component in a well-formed network; ambiguity only occurs at a junction,
-- which is handled at the Freight Station level in step 5).
function Rails.adjacent_component(world, x, y)
    for _, nb in ipairs(Grid.neighbors(world.grid, x, y)) do
        local cid = world.rails.components[Grid.idx(world.grid, nb.x, nb.y)]
        if cid then return cid end
    end
    return nil
end

return Rails
