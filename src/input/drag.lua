-- src/input/drag.lua
-- Pure drag geometry: turn a (start, cursor) tile pair into the set of tiles a
-- drag would affect. Roads paint an axis-only straight run; zones fill the
-- bounding rectangle minus any road tiles.

local Grid = require("src.world.grid")

local Drag = {}

-- Axis-only run from (x0,y0) to (x1,y1): a single straight line along whichever
-- axis the drag moved further on (ties go horizontal). Inclusive of both ends;
-- handles drags in any direction.
function Drag.road_run(x0, y0, x1, y1)
    local tiles = {}
    local dx, dy = x1 - x0, y1 - y0
    if math.abs(dx) >= math.abs(dy) then
        local step = dx >= 0 and 1 or -1
        for x = x0, x1, step do tiles[#tiles + 1] = { x = x, y = y0 } end
    else
        local step = dy >= 0 and 1 or -1
        for y = y0, y1, step do tiles[#tiles + 1] = { x = x0, y = y } end
    end
    return tiles
end

-- All zonable tiles in the bounding box of (x0,y0)-(x1,y1): every in-bounds tile
-- that isn't a road. Roads are skipped so a zone drag flows around them.
function Drag.zone_rect(world, x0, y0, x1, y1)
    local tiles = {}
    local lx, hx = math.min(x0, x1), math.max(x0, x1)
    local ly, hy = math.min(y0, y1), math.max(y0, y1)
    for x = lx, hx do
        for y = ly, hy do
            local tile = Grid.get(world.grid, x, y)
            if tile and not tile.road then tiles[#tiles + 1] = { x = x, y = y } end
        end
    end
    return tiles
end

return Drag
