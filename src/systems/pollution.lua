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
local C = require("src.world.constants")

local Pollution = {}

-- A tile's emission strength as a source, or 0 if it isn't one. Only a power plant
-- (its anchor carries tile.plant) and a COMPLETED industrial building emit;
-- residential/commercial and still-constructing tiles are clean.
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
-- Returns {idx -> value}; an absent index reads as zero pollution.
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

return Pollution
