-- src/render/overlays.lua
-- The PURE half of the overlay heatmaps (no LÖVE): given a world it picks the
-- value range a heatmap spans and the per-tile color. The renderer does the actual
-- love.graphics drawing; keeping the math here makes the gradient testable.
--
-- Pollution uses a DYNAMIC range (0 .. current peak) so the green->yellow->red
-- gradient always spreads across whatever pollution exists, however small. Land
-- value uses its fixed absolute scale [MIN, MAX] -- green always means "good".

local Grid = require("src.world.grid")
local Ramp = require("src.render.ramp")
local Pollution = require("src.systems.pollution")
local LandValue = require("src.systems.land_value")
local Power = require("src.systems.power")
local C = require("src.world.constants")

local Overlays = {}

-- The (lo, hi) value range the active overlay's ramp spans.
function Overlays.range(overlay, world)
    if overlay == C.OVERLAY.POLLUTION then
        local hi = 0
        for _, v in pairs(world.pollution.field) do
            if v > hi then hi = v end
        end
        return 0, hi
    elseif overlay == C.OVERLAY.LAND_VALUE then
        return C.LAND.MIN, C.LAND.MAX
    end
    return 0, 0
end

-- The heatmap color {r,g,b} for tile (x, y) under `overlay`, or nil to leave the
-- base tile untinted. (lo, hi) come from Overlays.range.
function Overlays.color(overlay, world, x, y, lo, hi)
    if overlay == C.OVERLAY.POLLUTION then
        local p = Pollution.at(world, x, y)
        if p <= 0 then return nil end -- clean: let the terrain show through
        return Ramp.color(p, lo, hi, C.RAMP.POLLUTION)
    elseif overlay == C.OVERLAY.LAND_VALUE then
        return Ramp.color(LandValue.at(world, x, y), lo, hi, C.RAMP.LAND_VALUE)
    elseif overlay == C.OVERLAY.POWER then
        local tile = Grid.get(world.grid, x, y)
        local idx = Grid.idx(world.grid, x, y)
        local conductor = tile.road or tile.power_line or tile.plant or tile.plant_part
        if (world.power.powered or {})[idx] or (tile.building and Power.building_powered(world, x, y)) then
            return C.RAMP.POLLUTION[1] -- green = served
        elseif conductor or tile.building then
            return C.RAMP.POLLUTION[3] -- red = unpowered infra/building
        end
        return nil
    end
    return nil
end

return Overlays
