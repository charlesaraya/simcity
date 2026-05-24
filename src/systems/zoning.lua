-- src/systems/zoning.lua
-- An event-driven system (no tick). Where demand and growth run on the clock,
-- zoning just reacts to changes on the bus. install() wires its subscriptions
-- once at setup, capturing the world it operates on.
--
-- Responsibility: keep tile and building consistent. zone_tile only publishes
-- tile_zoned on a real zone change, so if the rezoned tile still carries a
-- building, that building belonged to the old zone and must be demolished --
-- it will regrow as the new zone if demand warrants.

local Bus = require("src.bus")
local Grid = require("src.world.grid")
local C = require("src.world.constants")

local Zoning = {}

function Zoning.install(world)
    Bus.subscribe(C.EVENTS.TILE_ZONED, function(data)
        local tile = Grid.get(world.grid, data.x, data.y)
        if tile and tile.building then
            -- Direct clear: a player-driven rezone, not an economic abandonment,
            -- so no building_abandoned event.
            tile.building = nil
        end
    end)
end

return Zoning
