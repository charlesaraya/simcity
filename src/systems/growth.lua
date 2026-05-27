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
local Power = require("src.systems.power")
local Pollution = require("src.systems.pollution")
local LandValue = require("src.systems.land_value")
local C = require("src.world.constants")

local Growth = {}

local function demand_for(world, zone)
    if zone == C.ZONE.RESIDENTIAL then return world.demand.residential end
    if zone == C.ZONE.COMMERCIAL then return world.demand.commercial end
    if zone == C.ZONE.INDUSTRIAL then return world.demand.industrial end
    return 0
end

-- How much land value scales a tile's start chance. Residential and commercial
-- prefer high-value (clean) land: the factor ramps from LV_MIN_FACTOR on the
-- worst land up to 1.0 on the best, so dirty land still grows, just slowly.
-- Industry is indifferent -- it takes the cheap, polluted land residents reject.
local function land_value_factor(world, x, y, zone)
    if zone == C.ZONE.INDUSTRIAL then return 1 end
    local span = C.LAND.MAX - C.LAND.MIN
    if span <= 0 then return 1 end
    local norm = (LandValue.at(world, x, y) - C.LAND.MIN) / span
    return C.GROWTH.LV_MIN_FACTOR + (1 - C.GROWTH.LV_MIN_FACTOR) * norm
end

function Growth.system()
    return {
        interval = C.SIM.SECONDS_PER_MONTH,
        accumulator = 0,
        tick = function(world)
            -- Resolve the power grid ONCE up front: every tile this tick reads the
            -- same powered snapshot, so a building completing mid-pass can't black
            -- out its neighbours within the same tick.
            Power.resolve(world)
            -- Rebuild the pollution field once too (only if dirtied since last tick),
            -- so land-value reads below see a consistent snapshot for the whole pass.
            Pollution.resolve(world)
            -- Spare capacity per component, decremented as we commit new sites this
            -- tick. Growth never starts a building its grid can't power, so the city
            -- plateaus at its supply ceiling instead of overshooting into a blackout.
            local headroom = Power.headroom(world)
            Grid.each(world.grid, function(x, y, tile)
                if tile.zone == C.ZONE.NONE then return end
                local d = demand_for(world, tile.zone)
                local connected = Roads.building_connected(world, x, y)

                if not tile.building then
                    -- Empty zoned tile: needs demand, road access, AND a power
                    -- component with room for its draw. Starting reserves that draw.
                    local cid = Power.component_at(world, x, y)
                    local draw = C.POWER_DRAW[tile.zone] or 0
                    local has_power = cid ~= nil and (headroom[cid] or 0) >= draw
                    -- Res/com favour clean, high-value land; industry is indifferent.
                    local lv = land_value_factor(world, x, y, tile.zone)
                    if d > 0 and connected and has_power
                        and RNG.chance(world.rng, d * C.GROWTH.RATE * lv) then
                        World.start_building(world, x, y)
                        headroom[cid] = headroom[cid] - draw
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
                    -- Abandon a completed building on any one of four triggers:
                    local poisoned = tile.zone ~= C.ZONE.INDUSTRIAL
                        and Pollution.at(world, x, y) > C.GROWTH.POLLUTION_ABANDON_THRESHOLD
                    if d < C.GROWTH.ABANDON_THRESHOLD
                        and RNG.chance(world.rng, -d * C.GROWTH.ABANDON_RATE) then
                        World.abandon_building(world, x, y)
                    elseif not connected and RNG.chance(world.rng, C.GROWTH.ABANDON_RATE) then
                        World.abandon_building(world, x, y)
                    elseif not Power.building_powered(world, x, y)
                        and RNG.chance(world.rng, C.GROWTH.ABANDON_RATE) then
                        World.abandon_building(world, x, y)
                    elseif poisoned and RNG.chance(world.rng, C.GROWTH.ABANDON_RATE) then
                        -- Heavy pollution drives residents/shops out; industry tolerates it.
                        World.abandon_building(world, x, y)
                    end
                end
            end)
        end,
    }
end

return Growth
