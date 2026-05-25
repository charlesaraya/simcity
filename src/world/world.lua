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

-- Build a new world. The grid is all grass; the RNG is seeded so growth is
-- reproducible; demand starts neutral; the treasury starts funded and the
-- economy's last-net readout at zero.
function World.new(seed)
    return {
        grid = Grid.new(),
        rng = RNG.new(seed),
        demand = { residential = 0, commercial = 0, industrial = 0 },
        clock = { months = 0 }, -- elapsed sim-months; the clock system advances it
        treasury = C.ECON.START_TREASURY, -- city funds; the economy moves this
        economy = { last_net = 0 },        -- last month's net delta, for the HUD
        -- Derived road-connectivity cache (the roads system fills `connected`
        -- with the indices of road tiles reaching a map edge). Rebuilt from the
        -- grid on install/load, so a stale serialized copy can't desync it.
        roads = { connected = {} },
    }
end

-- WRITE: designate a tile's zone. Idempotent -- zoning a tile to the zone it
-- already has is a no-op (no event), so hold-to-paint never spams events or
-- re-triggers consequences. Publishes tile_zoned only on an actual change.
function World.zone_tile(world, x, y, zone)
    local tile = Grid.get(world.grid, x, y)
    if not tile then return false end
    if tile.zone == zone then return false end
    tile.zone = zone
    Bus.publish(C.EVENTS.TILE_ZONED, { x = x, y = y, zone = zone })
    return true
end

-- WRITE: clear a tile back to unzoned grass, removing any building.
-- Publishes tile_bulldozed.
function World.bulldoze(world, x, y)
    local tile = Grid.get(world.grid, x, y)
    if not tile then return false end
    tile.zone = C.ZONE.NONE
    tile.building = nil
    Bus.publish(C.EVENTS.TILE_BULLDOZED, { x = x, y = y })
    return true
end

-- WRITE: lay a road on a tile. Roads are mutually exclusive with zones and
-- buildings, so this only succeeds on plain, unzoned grass -- otherwise it's a
-- no-op (the player must bulldoze first). Publishes road_built so the roads
-- system can recompute connectivity. Idempotent: re-roading a road tile is a
-- no-op (no event), so hold-to-paint never re-fires.
function World.build_road(world, x, y)
    local tile = Grid.get(world.grid, x, y)
    if not tile then return false end
    if tile.road or tile.zone ~= C.ZONE.NONE or tile.building then return false end
    tile.road = true
    Bus.publish(C.EVENTS.ROAD_BUILT, { x = x, y = y })
    return true
end

-- WRITE: begin construction on a tile. No event yet -- the building doesn't
-- contribute until it completes. (Growth calls this, then completes it later.)
function World.start_building(world, x, y)
    local tile = Grid.get(world.grid, x, y)
    if not tile then return false end
    tile.building = { state = C.BUILD.CONSTRUCTING, progress = 0 }
    return true
end

-- WRITE: finish construction. Publishes building_constructed (now it counts).
function World.complete_building(world, x, y)
    local tile = Grid.get(world.grid, x, y)
    if not (tile and tile.building) then return false end
    tile.building.state = C.BUILD.COMPLETE
    Bus.publish(C.EVENTS.BUILDING_CONSTRUCTED, { x = x, y = y, zone = tile.zone })
    return true
end

-- WRITE: remove a building (demand collapsed, hostile conditions, etc).
-- Publishes building_abandoned, carrying the zone it vacated.
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
-- its per-zone job count. Both zones employ; only residential houses.
function World.jobs(world)
    local com = World.count_buildings(world, C.ZONE.COMMERCIAL, C.BUILD.COMPLETE)
    local ind = World.count_buildings(world, C.ZONE.INDUSTRIAL, C.BUILD.COMPLETE)
    return com * C.JOBS_PER_COM + ind * C.JOBS_PER_IND
end

-- READ: total completed buildings across every zone. The economy pays upkeep
-- per building regardless of kind, so it needs this gross count. A zone-less
-- count_buildings call -- one scan, no duplicated walk logic.
function World.building_count(world)
    return World.count_buildings(world, nil, C.BUILD.COMPLETE)
end

return World
