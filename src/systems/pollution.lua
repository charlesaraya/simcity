-- src/systems/pollution.lua
-- Pollution is a DIFFUSION field, not a connectivity network -- so it does not use
-- the NetworkedUtility skeleton. Industrial buildings and power plants emit; the
-- value spreads outward from each source within RADIUS and fades linearly with
-- distance, and overlapping sources add. The whole field is a pure function of the
-- grid (Pollution.compute), so it rebuilds from scratch and is never trusted from
-- a save.
--
-- Diffusion model: bounded-radius accumulation. Sources are sparse, so the cost is
-- O(sources * RADIUS^2), not O(tiles * sources). Chosen over iterative relaxation
-- (stateful, all-tiles-every-tick) for determinism and the rebuild-from-grid
-- property the road/power caches already rely on.

local Grid = require("src.world.grid")
local Bus = require("src.bus")
local C = require("src.world.constants")

local Pollution = {}

-- A tile's emission strength as a source, or 0 if it isn't one.
local function emit(tile)
    if tile.plant then
        return C.POLLUTION.PLANT_EMIT
    end
    if tile.zone == C.ZONE.INDUSTRIAL and tile.building
        and tile.building.state == C.BUILD.COMPLETE then
        return C.POLLUTION.IND_EMIT
    end
    return 0
end

-- Flood each source's contribution onto every tile within RADIUS, summing.
function Pollution.compute(grid)
    local field = {}
    local r = C.POLLUTION.RADIUS

    Grid.each(grid, function(sx, sy, tile)
        local strength = emit(tile)
        if strength > 0 then
            for dy = -r, r do
                for dx = -r, r do
                    local dist = math.sqrt(dx * dx + dy * dy)
                    local x, y = sx + dx, sy + dy
                    if dist < r and Grid.in_bounds(grid, x, y) then
                        local idx = Grid.idx(grid, x, y)
                        field[idx] = (field[idx] or 0) + strength * (1 - dist / r)
                    end
                end
            end
        end
    end)

    return field
end

-- READ: pollution at (x, y). An unpolluted tile reads 0.
function Pollution.at(world, x, y)
    return world.pollution.field[Grid.idx(world.grid, x, y)] or 0
end

-- Lazily rebuild the cached field from the grid, but only when it is dirty.
function Pollution.resolve(world)
    if world.pollution.dirty then
        world.pollution.field = Pollution.compute(world.grid)
        world.pollution.dirty = false
    end
    return world.pollution.field
end

-- Event-driven dirtying: any change to the set of sources (a building finishing or
-- abandoning, a plant going up or down) marks the field stale; the next resolve
-- rebuilds it.
function Pollution.install(world)
    local function mark_dirty()
        world.pollution.dirty = true
    end
    local events = {
        C.EVENTS.BUILDING_CONSTRUCTED, C.EVENTS.BUILDING_ABANDONED,
        C.EVENTS.PLANT_BUILT, C.EVENTS.PLANT_REMOVED,
    }
    for _, ev in ipairs(events) do
        Bus.subscribe(ev, mark_dirty)
    end
    world.pollution.dirty = true
    Pollution.resolve(world)
end

return Pollution
