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
-- reproducible; demand starts neutral.
function World.new(seed)
    return {
        grid = Grid.new(),
        rng = RNG.new(seed),
        demand = { residential = 0, commercial = 0 },
    }
end

-- WRITE: designate a tile's zone. Publishes tile_zoned.
function World.zone_tile(world, x, y, zone)
    local tile = Grid.get(world.grid, x, y)
    if not tile then return false end
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

-- READ: count buildings of a zone, optionally filtered by lifecycle state.
-- Derived by scanning -- no cached total to fall out of sync.
function World.count_buildings(world, zone, state)
    local n = 0
    Grid.each(world.grid, function(_, _, tile)
        if tile.building and tile.zone == zone then
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

return World
