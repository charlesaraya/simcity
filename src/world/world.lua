-- src/world/world.lua
-- The world database (Principle 2): a plain-data container plus read and write
-- functions. It holds NO logic about what changes mean -- systems do that.
--
-- The defining rule: every write function mutates the data AND publishes an
-- event. Mutation and notification are co-located, so no caller can change the
-- world without the rest of the game hearing about it. Systems subscribe; they
-- are never called directly.

local Grid = require("src.world.grid")
local RNG = require("src.sim.rng")
local Bus = require("src.bus")
local C = require("src.world.constants")

local World = {}

-- A tile is buildable only if it is unclaimed grass.
-- Every placement writer shares this gate, so the on-grid
-- pieces stay mutually exclusive.
local function is_buildable(tile)
    return tile ~= nil
        and not tile.road
        and not tile.power_line
        and not tile.plant
        and not tile.plant_part
        and not tile.building
        and tile.zone == C.ZONE.NONE
end

-- Build a new world. The grid is all grass; the RNG is seeded so growth is
-- reproducible; demand starts neutral; the treasury starts funded and the
-- economy's last-net readout at zero.
function World.new(seed)
    return {
        grid = Grid.new(),
        rng = RNG.new(seed),
        demand = { residential = 0, commercial = 0, industrial = 0 },
        clock = { months = 0 },                  -- elapsed sim-months; the clock system advances it
        treasury = C.ECON.START_TREASURY,        -- city funds; the economy moves this
        economy = { last_net = 0 },              -- last month's net delta, for the HUD
        roads = { connected = {} },              -- Derived road-connectivity cache
        power = { topology = {}, powered = {} }, -- Derived power state, rebuilt from the grid on load
        pollution = { field = {}, dirty = false }, -- Derived diffusion field; lazily rebuilt from the grid
    }
end

-- WRITE: designate a tile's zone. Idempotent: re-zoning is a no-op (no event);
-- hold-to-paint never spams events. Refuses any infrastructure tile.
function World.zone_tile(world, x, y, zone)
    local tile = Grid.get(world.grid, x, y)
    if not tile then return false end
    if tile.road or tile.power_line or tile.plant or tile.plant_part then return false end
    if tile.zone == zone then return false end
    tile.zone = zone
    Bus.publish(C.EVENTS.TILE_ZONED, { x = x, y = y, zone = zone })
    return true
end

-- WRITE: clear a tile back to plain grass.
function World.bulldoze(world, x, y)
    local tile = Grid.get(world.grid, x, y)
    if not tile then return false end
    -- Plant: bulldozing any footprint tile clears the whole square and reports the anchor.
    if tile.plant or tile.plant_part then
        local ax, ay = x, y
        if tile.plant_part then
            ax, ay = Grid.coord(world.grid, tile.plant_part)
        end
        local n = C.PLANT.FOOTPRINT
        for dy = 0, n - 1 do
            for dx = 0, n - 1 do
                local t = Grid.get(world.grid, ax + dx, ay + dy)
                if t then
                    t.plant = nil
                    t.plant_part = nil
                end
            end
        end
        Bus.publish(C.EVENTS.PLANT_REMOVED, { x = ax, y = ay })
        return true
    end
    if tile.power_line then
        tile.power_line = nil
        Bus.publish(C.EVENTS.POWER_LINE_REMOVED, { x = x, y = y })
        return true
    end
    if tile.road then
        tile.road = nil
        Bus.publish(C.EVENTS.ROAD_REMOVED, { x = x, y = y })
        return true
    end
    tile.zone = C.ZONE.NONE
    tile.building = nil
    Bus.publish(C.EVENTS.TILE_BULLDOZED, { x = x, y = y })
    return true
end

-- WRITE: lay a road on a tile. Roads are mutually exclusive with zones and
-- buildings, so this only succeeds on plain, unzoned grass, otherwise it's a
-- no-op.
function World.build_road(world, x, y)
    local tile = Grid.get(world.grid, x, y)
    if not is_buildable(tile) then return false end
    tile.road = true
    Bus.publish(C.EVENTS.ROAD_BUILT, { x = x, y = y })
    return true
end

-- WRITE: lay a power line on a tile. Same plain-grass rule as roads.
function World.build_power_line(world, x, y)
    local tile = Grid.get(world.grid, x, y)
    if not is_buildable(tile) then return false end
    tile.power_line = true
    Bus.publish(C.EVENTS.POWER_LINE_BUILT, { x = x, y = y })
    return true
end

-- WRITE: place a power plant whose anchor is (x, y), occupying a square of side
-- C.PLANT.FOOTPRINT extending +x and +y. All footprint tiles must be on-grid and
-- plain grass, or the whole placement is refused.
function World.build_plant(world, x, y)
    local n = C.PLANT.FOOTPRINT
    -- Validate the entire footprint before writing anything.
    for dy = 0, n - 1 do
        for dx = 0, n - 1 do
            if not is_buildable(Grid.get(world.grid, x + dx, y + dy)) then
                return false
            end
        end
    end
    -- The anchor tile holds the plant record; each other footprint tile holds plant_part = the
    -- anchor's flat index, so bulldozing any one tile can find and clear the lot.
    local anchor = Grid.idx(world.grid, x, y)
    for dy = 0, n - 1 do
        for dx = 0, n - 1 do
            local tile = Grid.get(world.grid, x + dx, y + dy)
            if dx == 0 and dy == 0 then
                tile.plant = true
            else
                tile.plant_part = anchor
            end
        end
    end
    Bus.publish(C.EVENTS.PLANT_BUILT, { x = x, y = y })
    return true
end

-- WRITE: begin construction on a tile. No event yet.
function World.start_building(world, x, y)
    local tile = Grid.get(world.grid, x, y)
    if not tile then return false end
    tile.building = { state = C.BUILD.CONSTRUCTING, progress = 0 }
    return true
end

-- WRITE: finish construction.
function World.complete_building(world, x, y)
    local tile = Grid.get(world.grid, x, y)
    if not (tile and tile.building) then return false end
    tile.building.state = C.BUILD.COMPLETE
    Bus.publish(C.EVENTS.BUILDING_CONSTRUCTED, { x = x, y = y, zone = tile.zone })
    return true
end

-- WRITE: remove a building.
function World.abandon_building(world, x, y)
    local tile = Grid.get(world.grid, x, y)
    if not (tile and tile.building) then return false end
    local zone = tile.zone
    tile.building = nil
    Bus.publish(C.EVENTS.BUILDING_ABANDONED, { x = x, y = y, zone = zone })
    return true
end

-- READ: count buildings, optionally filtered by zone and/or lifecycle state. A
-- nil zone counts every zone (a cross-zone total); a nil state counts any state.
-- Derived by scanning -- no cached total to fall out of sync.
function World.count_buildings(world, zone, state)
    local n = 0
    Grid.each(world.grid, function(_, _, tile)
        if tile.building and (zone == nil or tile.zone == zone) then
            if (not state) or tile.building.state == state then
                n = n + 1
            end
        end
    end)
    return n
end

-- READ: total population = completed residential buildings * per-building pop.
function World.population(world)
    return World.count_buildings(world, C.ZONE.RESIDENTIAL, C.BUILD.COMPLETE) * C.POP_PER_RES
end

-- READ: total jobs = completed commercial + industrial buildings, each scaled by
-- its per-zone job count.
function World.jobs(world)
    local com = World.count_buildings(world, C.ZONE.COMMERCIAL, C.BUILD.COMPLETE)
    local ind = World.count_buildings(world, C.ZONE.INDUSTRIAL, C.BUILD.COMPLETE)
    return com * C.JOBS_PER_COM + ind * C.JOBS_PER_IND
end

-- READ: total completed buildings across every zone (a gross count for the HUD
-- and stats; the economy bills upkeep on businesses only -- see business_count).
function World.building_count(world)
    return World.count_buildings(world, nil, C.BUILD.COMPLETE)
end

-- READ: counts the buildings that carry city upkeep. Residential housing is
-- upkeep-free, so population can grow without bleeding the budget.
function World.business_count(world)
    return World.count_buildings(world, C.ZONE.COMMERCIAL, C.BUILD.COMPLETE)
        + World.count_buildings(world, C.ZONE.INDUSTRIAL, C.BUILD.COMPLETE)
end

-- READ: number of power plants, counted by anchor tile.
function World.plant_count(world)
    local n = 0
    Grid.each(world.grid, function(_, _, tile)
        if tile.plant then n = n + 1 end
    end)
    return n
end

return World
