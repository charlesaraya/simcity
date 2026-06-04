-- src/world/world.lua
-- The world database (Principle 2): a plain-data container plus read and write
-- functions. It holds NO logic about what changes mean -- systems do that.
--
-- The defining rule: every write function mutates the data AND publishes an
-- event. Mutation and notification are co-located, so no caller can change the
-- world without the rest of the game hearing about it. Systems subscribe; they
-- are never called directly.

local Grid = require("src.world.grid")
local RNG  = require("src.sim.rng")
local Bus  = require("src.bus")
local C    = require("src.world.constants")

local World = {}

-- A tile is buildable only if it is unclaimed grass.
-- Every placement writer shares this gate, so the on-grid
-- pieces stay mutually exclusive.
local function is_buildable(tile)
    return tile ~= nil
        and not tile.road
        and not tile.power_line
        and not tile.pipe
        and not tile.pump
        and not tile.plant
        and not tile.plant_part
        and not tile.station
        and not tile.station_part
        and not tile.hospital
        and not tile.hospital_part
        and not tile.med_center
        and not tile.building
        and not tile.mine
        and not tile.rail
        and tile.zone == C.ZONE.NONE
        and tile.type ~= C.TILE.IRON_DEPOSIT
end

-- Seed a continuous fertility gradient (0..1) on every tile using distance
-- falloff from a set of random hotspots. Higher values = better farm yield.
-- Called once by World.new(); permanent terrain attribute.
local function seed_fertility(world)
    local g    = world.grid
    local rng  = world.rng
    local w, h = g.width, g.height

    local function rng_range(lo, hi)
        return lo + math.floor(RNG.random(rng) * (hi - lo + 1))
    end

    local hotspots = {}
    for _ = 1, C.FERTILITY.HOTSPOTS do
        hotspots[#hotspots + 1] = { x = rng_range(1, w), y = rng_range(1, h) }
    end

    Grid.each(g, function(x, y, tile)
        tile.fertility = 1
    end)
end

-- Place a cluster of IRON_DEPOSIT tiles in a random corner quadrant.
-- Called once by World.new(); never called again (deposits are permanent terrain).
-- The corner is chosen via the world RNG so placement is seed-deterministic.
local function seed_deposits(world)
    local g    = world.grid
    local rng  = world.rng
    local w, h = g.width, g.height
    local pad  = C.DEPOSIT.EDGE_PAD
    local reach = C.DEPOSIT.CORNER_REACH

    -- Pick one of the four corners: sign pair drives direction from that corner.
    local corners = { { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } }
    local s  = corners[math.floor(RNG.random(rng) * 4) + 1]
    local ox = s[1] > 0 and 1 or w
    local oy = s[2] > 0 and 1 or h

    local function rng_range(lo, hi)
        return lo + math.floor(RNG.random(rng) * (hi - lo + 1))
    end
    local cx = ox + s[1] * rng_range(pad, reach)
    local cy = oy + s[2] * rng_range(pad, reach)

    -- Six-tile cross cluster; skip any tile already off-grid.
    local OFFSETS = { {0,0}, {1,0}, {-1,0}, {0,1}, {0,-1}, {1,1} }
    for _, off in ipairs(OFFSETS) do
        local tile = Grid.get(g, cx + off[1], cy + off[2])
        if tile then tile.type = C.TILE.IRON_DEPOSIT end
    end
end

-- Build a new world. The grid is all grass; iron deposits are seeded in a
-- corner quadrant; the RNG is seeded so growth and deposit placement are
-- reproducible; demand starts neutral; the treasury starts funded and the
-- economy's last-net readout at zero.
-- opts (4c-2): per-mission overrides applied at construction. Currently just
-- start_treasury (set by the difficulty preset chosen on the charter screen).
function World.new(seed, opts)
    opts = opts or {}
    local world = {
        grid      = Grid.new(),
        rng       = RNG.new(seed),
        demand    = { residential = 0, commercial = 0, industrial = 0, agricultural = 0 },
        clock     = { months = 0 },
        treasury  = opts.start_treasury or C.ECON.START_TREASURY,
        economy   = { last_net = 0 },
        roads     = { connected = {} },
        rails     = { components = {} },
        freight   = { bridged = {} },
        power     = { topology = {}, powered = {} },
        pollution = { field = {}, dirty = false },
        -- Typed-goods stockpiles (supply/demand/inventory keyed by C.GOODS.*).
        -- Seed food and processed goods so RES/COM can start before full supply
        -- chains are established. Medicine starts empty: it only gates growth
        -- once the player builds a hospital, so no starter buffer needed.
        goods     = { supply = {}, demand = {},
                      inventory = { [C.GOODS.FOOD]            = 10,
                                    [C.GOODS.PROCESSED_GOODS] = 10 } },
        water     = { covered = {} },
        crew      = {},
        mission   = {},
    }
    seed_deposits(world)
    seed_fertility(world)
    return world
end

-- WRITE: charter a mission -- set world.mission and world.crew atomically and
-- publish MISSION_CHARTERED. Subsequent calls REPLACE both (the charter screen
-- may let the operator re-roll). No system reacts in 4c (the crew is flavor
-- only); the writer publishes the event anyway so Phase 5+ mechanics can plug
-- in without editing this function. (Principle 4: writers mutate AND publish.)
function World.charter(world, mission, crew)
    world.mission = mission
    world.crew = crew
    Bus.publish(C.EVENTS.MISSION_CHARTERED, { mission = mission, crew = crew })
    return true
end

-- WRITE: designate a tile's zone. Idempotent: re-zoning is a no-op (no event);
-- hold-to-paint never spams events. Refuses any infrastructure tile.
function World.zone_tile(world, x, y, zone)
    local tile = Grid.get(world.grid, x, y)
    if not tile then return false end
    if tile.road or tile.power_line or tile.pipe or tile.pump
    or tile.plant or tile.plant_part
    or tile.station or tile.station_part or tile.hospital or tile.hospital_part
    or tile.med_center or tile.mine or tile.type == C.TILE.IRON_DEPOSIT then return false end
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
    if tile.station or tile.station_part then
        local ax, ay = x, y
        if tile.station_part then
            ax, ay = Grid.coord(world.grid, tile.station_part)
        end
        local n = C.FREIGHT_STATION.FOOTPRINT
        for dy = 0, n - 1 do
            for dx = 0, n - 1 do
                local t = Grid.get(world.grid, ax + dx, ay + dy)
                if t then
                    t.station = nil
                    t.station_part = nil
                end
            end
        end
        Bus.publish(C.EVENTS.STATION_REMOVED, { x = ax, y = ay })
        return true
    end
    if tile.hospital or tile.hospital_part then
        local ax, ay = x, y
        if tile.hospital_part then
            ax, ay = Grid.coord(world.grid, tile.hospital_part)
        end
        local n = C.HOSPITAL.FOOTPRINT
        for dy = 0, n - 1 do
            for dx = 0, n - 1 do
                local t = Grid.get(world.grid, ax + dx, ay + dy)
                if t then
                    t.hospital = nil
                    t.hospital_part = nil
                end
            end
        end
        Bus.publish(C.EVENTS.HOSPITAL_REMOVED, { x = ax, y = ay })
        return true
    end
    if tile.med_center then
        tile.med_center = nil
        Bus.publish(C.EVENTS.MED_CENTER_REMOVED, { x = x, y = y })
        return true
    end
    if tile.mine then
        tile.mine = nil
        Bus.publish(C.EVENTS.MINE_REMOVED, { x = x, y = y })
        return true
    end
    if tile.rail then
        tile.rail = nil
        Bus.publish(C.EVENTS.RAIL_REMOVED, { x = x, y = y })
        return true
    end
    if tile.pump then
        tile.pump = nil
        Bus.publish(C.EVENTS.PUMP_REMOVED, { x = x, y = y })
        return true
    end
    if tile.pipe then
        tile.pipe = nil
        Bus.publish(C.EVENTS.PIPE_REMOVED, { x = x, y = y })
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

-- WRITE: lay a water pipe on a tile. Plain grass only (same rule as roads).
function World.build_pipe(world, x, y)
    local tile = Grid.get(world.grid, x, y)
    if not is_buildable(tile) then return false end
    tile.pipe = true
    Bus.publish(C.EVENTS.PIPE_BUILT, { x = x, y = y })
    return true
end

-- WRITE: place a water pump on a plain-grass tile. Validity (road + power-line
-- adjacency) is enforced by the command layer (drag.lua / tools.lua).
function World.build_pump(world, x, y)
    local tile = Grid.get(world.grid, x, y)
    if not is_buildable(tile) then return false end
    tile.pump = true
    Bus.publish(C.EVENTS.PUMP_BUILT, { x = x, y = y })
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

-- WRITE: place a 2×2 freight station anchored at (x, y). All footprint tiles
-- must be plain grass. The anchor holds tile.station; the rest hold
-- tile.station_part = anchor index (same backlink pattern as power plants).
function World.build_station(world, x, y)
    local n = C.FREIGHT_STATION.FOOTPRINT
    for dy = 0, n - 1 do
        for dx = 0, n - 1 do
            if not is_buildable(Grid.get(world.grid, x + dx, y + dy)) then
                return false
            end
        end
    end
    local anchor = Grid.idx(world.grid, x, y)
    for dy = 0, n - 1 do
        for dx = 0, n - 1 do
            local tile = Grid.get(world.grid, x + dx, y + dy)
            if dx == 0 and dy == 0 then
                tile.station = true
            else
                tile.station_part = anchor
            end
        end
    end
    Bus.publish(C.EVENTS.STATION_BUILT, { x = x, y = y })
    return true
end

-- WRITE: place a 2×2 hospital anchored at (x, y). All footprint tiles must be
-- plain grass. Anchor holds tile.hospital; the rest hold tile.hospital_part =
-- anchor index (same backlink pattern as power plants and stations).
function World.build_hospital(world, x, y)
    local n = C.HOSPITAL.FOOTPRINT
    for dy = 0, n - 1 do
        for dx = 0, n - 1 do
            if not is_buildable(Grid.get(world.grid, x + dx, y + dy)) then
                return false
            end
        end
    end
    local anchor = Grid.idx(world.grid, x, y)
    for dy = 0, n - 1 do
        for dx = 0, n - 1 do
            local tile = Grid.get(world.grid, x + dx, y + dy)
            if dx == 0 and dy == 0 then
                tile.hospital = true
            else
                tile.hospital_part = anchor
            end
        end
    end
    Bus.publish(C.EVENTS.HOSPITAL_BUILT, { x = x, y = y })
    return true
end

-- READ: number of hospitals (anchor tiles only).
function World.hospital_count(world)
    local n = 0
    Grid.each(world.grid, function(_, _, tile)
        if tile.hospital then n = n + 1 end
    end)
    return n
end

-- WRITE: place a 1×1 medical centre on plain grass adjacent to a road.
function World.build_med_center(world, x, y)
    local tile = Grid.get(world.grid, x, y)
    if not is_buildable(tile) then return false end
    tile.med_center = true
    Bus.publish(C.EVENTS.MED_CENTER_BUILT, { x = x, y = y })
    return true
end

-- READ: total healthcare facilities (hospitals + medical centres).
function World.healthcare_count(world)
    local n = 0
    Grid.each(world.grid, function(_, _, tile)
        if tile.hospital or tile.med_center then n = n + 1 end
    end)
    return n
end

-- READ: number of water pumps placed.
function World.pump_count(world)
    local n = 0
    Grid.each(world.grid, function(_, _, tile)
        if tile.pump then n = n + 1 end
    end)
    return n
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

-- WRITE: lay a freight rail tile. Mutually exclusive with roads, zones, and
-- buildings. Existing rail is a no-op (idempotent, like build_road).
function World.build_rail(world, x, y)
    local tile = Grid.get(world.grid, x, y)
    if not tile then return false end
    if tile.road or tile.power_line or tile.plant or tile.plant_part
    or tile.station or tile.station_part or tile.hospital or tile.hospital_part
    or tile.med_center or tile.building or tile.mine or tile.rail then return false end
    if tile.zone ~= C.ZONE.NONE then return false end
    if tile.type == C.TILE.IRON_DEPOSIT then return false end
    tile.rail = true
    Bus.publish(C.EVENTS.RAIL_BUILT, { x = x, y = y })
    return true
end

-- WRITE: place an iron mine on an IRON_DEPOSIT tile. Refused on any other
-- terrain type, or if the tile already has infrastructure or a mine.
function World.build_mine(world, x, y)
    local tile = Grid.get(world.grid, x, y)
    if not tile then return false end
    if tile.type ~= C.TILE.IRON_DEPOSIT then return false end
    if tile.road or tile.power_line or tile.plant or tile.plant_part
    or tile.station or tile.station_part or tile.hospital or tile.hospital_part
    or tile.med_center or tile.building or tile.mine then return false end
    if tile.zone ~= C.ZONE.NONE then return false end
    tile.mine = true
    Bus.publish(C.EVENTS.MINE_BUILT, { x = x, y = y })
    return true
end

-- READ: number of active iron mines (anchor tiles only).
function World.mine_count(world)
    local n = 0
    Grid.each(world.grid, function(_, _, tile)
        if tile.mine then n = n + 1 end
    end)
    return n
end

-- READ: number of freight stations (anchor tiles only).
function World.station_count(world)
    local n = 0
    Grid.each(world.grid, function(_, _, tile)
        if tile.station then n = n + 1 end
    end)
    return n
end

-- READ: positions of every IRON_DEPOSIT tile, as a list of {x, y} pairs.
-- Used by the build-mine tool to highlight valid placement tiles.
function World.deposit_tiles(world)
    local result = {}
    Grid.each(world.grid, function(x, y, tile)
        if tile.type == C.TILE.IRON_DEPOSIT then
            result[#result + 1] = { x = x, y = y }
        end
    end)
    return result
end

-- READ: number of completed farm buildings (agricultural zone, complete state).
function World.farm_count(world)
    return World.count_buildings(world, C.ZONE.AGRICULTURAL, C.BUILD.COMPLETE)
end

-- READ: number of power plants, counted by anchor tile.
function World.plant_count(world)
    local n = 0
    Grid.each(world.grid, function(_, _, tile)
        if tile.plant then n = n + 1 end
    end)
    return n
end

-- Pure read: true when road/power-line/zone can be placed at (x, y).
function World.tile_buildable(world, x, y)
    return is_buildable(Grid.get(world.grid, x, y))
end

-- Pure read: true when a rail tile can be placed at (x, y).
function World.tile_rail_buildable(world, x, y)
    local tile = Grid.get(world.grid, x, y)
    return tile ~= nil
        and not tile.road and not tile.power_line and not tile.plant and not tile.plant_part
        and not tile.building and not tile.mine and not tile.rail
        and not tile.station and not tile.station_part
        and not tile.hospital and not tile.hospital_part
        and not tile.med_center
        and tile.zone == C.ZONE.NONE
        and tile.type ~= C.TILE.IRON_DEPOSIT
end

return World
