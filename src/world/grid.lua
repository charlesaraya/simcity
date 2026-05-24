-- src/world/grid.lua
-- The grid is pure data: { width, height, tiles }. `tiles` is a 1D array of tile
-- tables, indexed by idx(x, y) = (y - 1) * width + x.
--
-- Every function here takes the grid as its first argument and reads or writes it
-- explicitly. There is no `grid:update()` and no tile that knows how to change
-- itself. That discipline (blueprint Principle 2) is what lets us serialize the
-- whole world from one table and run it headless later.
--
-- Coordinates are 1-based (x, y both start at 1), matching Lua's array convention.

local C = require("src.world.constants")

local Grid = {}

-- Map a 1-based (x, y) to a flat array index.
function Grid.idx(grid, x, y)
    return (y - 1) * grid.width + x
end

-- Inverse of idx: recover (x, y) from a flat index.
function Grid.coord(grid, idx)
    local x = (idx - 1) % grid.width + 1
    local y = math.floor((idx - 1) / grid.width) + 1
    return x, y
end

-- Is (x, y) inside the grid? Guard every access with this;
-- out-of-bounds reads are the second most common grid bug.
function Grid.in_bounds(grid, x, y)
    return x >= 1 and x <= grid.width and y >= 1 and y <= grid.height
end

-- Read the tile at (x, y), or nil if out of bounds.
function Grid.get(grid, x, y)
    if not Grid.in_bounds(grid, x, y) then return nil end
    return grid.tiles[Grid.idx(grid, x, y)]
end

-- Replace a tile's type at (x, y). Returns true on success, false if out of bounds.
-- Note we mutate the tile's field rather than the array slot: a tile keeps its
-- identity, only its data changes.
function Grid.set_type(grid, x, y, tile_type)
    if not Grid.in_bounds(grid, x, y) then return false end
    grid.tiles[Grid.idx(grid, x, y)].type = tile_type
    return true
end

-- Build a fresh grid filled with grass. The only constructor.
function Grid.new(width, height)
    width = width or C.GRID_W
    height = height or C.GRID_H
    local tiles = {}
    for i = 1, width * height do
        -- type = terrain; zone = planning designation; building added on growth.
        tiles[i] = { type = C.TILE.GRASS, zone = C.ZONE.NONE }
    end
    return { width = width, height = height, tiles = tiles }
end

-- Iterate every tile, calling fn(x, y, tile). Centralizes the loop so callers
-- never re-derive index math. Used by the renderer to draw the whole grid.
function Grid.each(grid, fn)
    for idx = 1, grid.width * grid.height do
        local x, y = Grid.coord(grid, idx)
        fn(x, y, grid.tiles[idx])
    end
end

-- The four orthogonal neighbors of (x, y), skipping any off the grid. Roads,
-- power, and pollution diffusion will all lean on this in later phases.
local OFFSETS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
function Grid.neighbors(grid, x, y)
    local result = {}
    for _, off in ipairs(OFFSETS) do
        local nx, ny = x + off[1], y + off[2]
        if Grid.in_bounds(grid, nx, ny) then
            result[#result + 1] = { x = nx, y = ny }
        end
    end
    return result
end

return Grid
