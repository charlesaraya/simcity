-- src/input/drag.lua
-- Pure drag geometry: turn a (start, cursor) tile pair into the set of tiles a
-- drag would affect. Roads paint an axis-only straight run; zones fill the
-- bounding rectangle minus any road tiles.

local Grid = require("src.world.grid")
local C = require("src.world.constants")

local Drag = {}

-- A run tile is buildable iff it's plain grass: in-bounds, unzoned, no building,
-- and free of any infrastructure.
local function buildable(world, t)
    local tile = Grid.get(world.grid, t.x, t.y)
    return tile
        and not tile.road
        and not tile.power_line
        and not tile.plant
        and not tile.plant_part
        and not tile.building
        and tile.zone == C.ZONE.NONE
end

-- How many tiles in a run would actually be built.
local function count_buildable(world, run)
    local n = 0
    for _, t in ipairs(run) do
        if buildable(world, t) then n = n + 1 end
    end
    return n
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
            -- Zoning flows around all infrastructure.
            if tile and not tile.road and not tile.power_line
                and not tile.plant and not tile.plant_part then
                tiles[#tiles + 1] = { x = x, y = y }
            end
        end
    end
    return tiles
end

-- A road/power-line run is valid unless it leaves the grid or crosses a solid
-- obstacle. Existing roads and power lines are fine both conduct and are skipped
-- at build time, so a run flows over them.
function Drag.road_run_valid(world, run)
    for _, t in ipairs(run) do
        local tile = Grid.get(world.grid, t.x, t.y)
        if not tile then return false end -- off-grid
        if tile.zone ~= C.ZONE.NONE or tile.building then return false end
        if tile.plant or tile.plant_part then return false end
    end
    return true
end

-- Cost is ROAD.COST per grass tile that will actually be built.
function Drag.road_cost(world, run)
    return count_buildable(world, run) * C.ROAD.COST
end

function Drag.road_affordable(world, run)
    return world.treasury >= Drag.road_cost(world, run)
end

-- Power lines reuse the road run's geometry and validity;
-- only the per-tile price differs.
function Drag.power_line_cost(world, run)
    return count_buildable(world, run) * C.POWER_LINE.COST
end

function Drag.power_line_affordable(world, run)
    return world.treasury >= Drag.power_line_cost(world, run)
end

-- A power plant's footprint.
function Drag.plant_footprint(x, y)
    local n = C.PLANT.FOOTPRINT
    local tiles = {}
    for dy = 0, n - 1 do
        for dx = 0, n - 1 do
            tiles[#tiles + 1] = { x = x + dx, y = y + dy }
        end
    end
    return tiles
end

-- A plant placement is valid only if every footprint tile is on-grid plain grass.
function Drag.plant_footprint_valid(world, x, y)
    for _, t in ipairs(Drag.plant_footprint(x, y)) do
        if not buildable(world, t) then return false end
    end
    return true
end

function Drag.plant_cost()
    return C.PLANT.COST
end

function Drag.plant_affordable(world)
    return world.treasury >= C.PLANT.COST
end

-- Zone cost = ZONE_COST per tile whose zone actually CHANGES. Tiles already in
-- the target zone (or roads) are no-ops at commit, so they aren't charged.
function Drag.zone_cost(world, tiles, zone)
    local n = 0
    for _, t in ipairs(tiles) do
        local tile = Grid.get(world.grid, t.x, t.y)
        if tile and not tile.road and not tile.power_line
            and not tile.plant and not tile.plant_part and tile.zone ~= zone then
            n = n + 1
        end
    end
    return n * C.ZONE_COST[zone]
end

function Drag.zone_affordable(world, tiles, zone)
    return world.treasury >= Drag.zone_cost(world, tiles, zone)
end

return Drag
