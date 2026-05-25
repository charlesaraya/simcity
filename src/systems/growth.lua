-- src/systems/growth.lua
-- Each month, walk every tile and evolve it (Principle 5, the other half of the
-- loop). A tile is in exactly one of three situations, so the branches are
-- mutually exclusive:
--   empty zoned tile + positive demand  -> maybe start construction
--   constructing                        -> advance; complete when done
--   complete + demand collapsed         -> maybe abandon
--
-- All randomness comes from world.rng (seeded) and tiles are visited in fixed
-- index order, so the same seed + demand always produces the same city.

local World = require("src.world.world")
local RNG = require("src.sim.rng")
local Grid = require("src.world.grid")
local Roads = require("src.systems.roads")
local C = require("src.world.constants")

local Growth = {}

local function demand_for(world, zone)
    if zone == C.ZONE.RESIDENTIAL then return world.demand.residential end
    if zone == C.ZONE.COMMERCIAL then return world.demand.commercial end
    if zone == C.ZONE.INDUSTRIAL then return world.demand.industrial end
    return 0
end

function Growth.system()
    return {
        interval = C.SIM.SECONDS_PER_MONTH,
        accumulator = 0,
        tick = function(world)
            Grid.each(world.grid, function(x, y, tile)
                if tile.zone == C.ZONE.NONE then return end
                local d = demand_for(world, tile.zone)
                local connected = Roads.building_connected(world, x, y)

                if not tile.building then
                    -- Empty zoned tile: needs demand AND road access to start.
                    if d > 0 and connected and RNG.chance(world.rng, d * C.GROWTH.RATE) then
                        World.start_building(world, x, y)
                    end
                elseif tile.building.state == C.BUILD.CONSTRUCTING then
                    if not connected then
                        -- Access lost mid-build: halt and roll to abandon the site.
                        if RNG.chance(world.rng, C.GROWTH.ABANDON_RATE) then
                            World.abandon_building(world, x, y)
                        end
                    else
                        -- Progress is internal building data.
                        tile.building.progress = tile.building.progress + 1
                        if tile.building.progress >= C.GROWTH.CONSTRUCTION_TICKS then
                            World.complete_building(world, x, y)
                        end
                    end
                else
                    -- Abandon a completed building on a true demand collapse, or on lost road.
                    if d < C.GROWTH.ABANDON_THRESHOLD
                        and RNG.chance(world.rng, -d * C.GROWTH.ABANDON_RATE) then
                        World.abandon_building(world, x, y)
                    elseif not connected and RNG.chance(world.rng, C.GROWTH.ABANDON_RATE) then
                        World.abandon_building(world, x, y)
                    end
                end
            end)
        end,
    }
end

return Growth
