-- src/input/drag.lua
-- Pure drag geometry: turn a (start, cursor) tile pair into the set of tiles a
-- drag would affect. Roads paint an axis-only straight run; zones fill the
-- bounding rectangle minus any road tiles.

local Grid = require("src.world.grid")
local C = require("src.world.constants")

local Drag = {}

-- A run tile is buildable iff it's plain grass: in-bounds, unzoned, no building,
-- not already a road. Existing roads are skipped.
local function buildable(world, t)
    local tile = Grid.get(world.grid, t.x, t.y)
    return tile and not tile.road and tile.zone == C.ZONE.NONE and not tile.building
end

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

-- A road run is valid unless it leaves the grid or crosses a zone/building.
-- Existing roads are fine (they'll be skipped at build time).
function Drag.road_run_valid(world, run)
    for _, t in ipairs(run) do
        local tile = Grid.get(world.grid, t.x, t.y)
        if not tile then return false end -- off-grid
        if tile.zone ~= C.ZONE.NONE or tile.building then return false end
    end
    return true
end

-- Cost = ROAD.COST per grass tile that will actually be built. Existing roads in
-- the run are transparent and not charged.
function Drag.road_cost(world, run)
    local n = 0
    for _, t in ipairs(run) do
        if buildable(world, t) then n = n + 1 end
    end
    return n * C.ROAD.COST
end

function Drag.road_affordable(world, run)
    return world.treasury >= Drag.road_cost(world, run)
end

return Drag
