-- src/render/renderer.lua
-- Reads world state and draws it through the camera. Like all rendering, it
-- READS the world and never writes -- so the sim could run headless and this
-- module could be swapped wholesale without touching simulation code.
--
-- Each tile draws as a diamond tinted by its zone; a completed or constructing
-- building draws as a smaller inset diamond on top.

local Grid = require("src.world.grid")
local Iso = require("src.render.iso")
local Camera = require("src.render.camera")
local Power = require("src.systems.power")
local Overlays = require("src.render.overlays")
local C = require("src.world.constants")

local Renderer = {}

local BUILD_SCALE = 0.55  -- building diamond size relative to the tile
local OVERLAY_ALPHA = 0.6 -- heatmap drawn translucent so zones/roads show through

local function tile_color(tile, x, y)
    if tile.plant or tile.plant_part then return C.COLOR.PLANT end
    if tile.power_line then return C.COLOR.POWER_LINE end
    if tile.road then return C.COLOR.ROAD end
    if tile.zone == C.ZONE.RESIDENTIAL then return C.COLOR.ZONE_RES end
    if tile.zone == C.ZONE.COMMERCIAL then return C.COLOR.ZONE_COM end
    if tile.zone == C.ZONE.INDUSTRIAL then return C.COLOR.ZONE_IND end
    -- unzoned: keep the grass checkerboard
    return ((x + y) % 2 == 0) and C.COLOR.GRASS_A or C.COLOR.GRASS_B
end

local function building_color(tile)
    if tile.building.state == C.BUILD.CONSTRUCTING then return C.COLOR.BUILD_PENDING end
    if tile.zone == C.ZONE.RESIDENTIAL then return C.COLOR.BUILD_RES end
    if tile.zone == C.ZONE.COMMERCIAL then return C.COLOR.BUILD_COM end
    if tile.zone == C.ZONE.INDUSTRIAL then return C.COLOR.BUILD_IND end
    return C.COLOR.BUILD_PENDING
end

-- `preview` (optional) = { tiles = {{x,y}...}, color = {r,g,b}, valid = bool };
-- a translucent overlay of the tiles a drag would affect, red when invalid.
-- `overlay` (optional, default NONE) selects a derived-state heatmap that replaces
-- each tile's fill with its ramp color (buildings + grid lines still draw on top).
function Renderer.draw(world, cam, hover, preview, overlay)
    Camera.apply(cam)
    overlay = overlay or C.OVERLAY.NONE
    local lo, hi = 0, 0
    if overlay ~= C.OVERLAY.NONE then lo, hi = Overlays.range(overlay, world) end

    Grid.each(world.grid, function(x, y, tile)
        -- Base tile first, then the heatmap as a translucent layer on top, so the
        -- underlying zone/road/terrain still reads through the overlay.
        love.graphics.setColor(tile_color(tile, x, y))
        love.graphics.polygon("fill", Iso.tile_corners(x, y))
        if overlay ~= C.OVERLAY.NONE then
            local oc = Overlays.color(overlay, world, x, y, lo, hi)
            if oc then
                love.graphics.setColor(oc[1], oc[2], oc[3], OVERLAY_ALPHA)
                love.graphics.polygon("fill", Iso.tile_corners(x, y))
            end
        end
        love.graphics.setColor(C.COLOR.TILE_LINE)
        love.graphics.polygon("line", Iso.tile_corners(x, y))

        if tile.building then
            local cx, cy = Iso.tile_to_screen(x, y)
            local hw = (C.TILE_W / 2) * BUILD_SCALE
            local hh = (C.TILE_H / 2) * BUILD_SCALE
            love.graphics.setColor(building_color(tile))
            love.graphics.polygon("fill", cx, cy - hh, cx + hw, cy, cx, cy + hh, cx - hw, cy)
            -- A completed but unpowered building wears an amber outline: it draws no
            -- power (dark component or no connection) and will abandon over time.
            if tile.building.state == C.BUILD.COMPLETE and not Power.building_powered(world, x, y) then
                love.graphics.setColor(C.COLOR.UNPOWERED)
                love.graphics.setLineWidth(2)
                love.graphics.polygon("line", cx, cy - hh, cx + hw, cy, cx, cy + hh, cx - hw, cy)
                love.graphics.setLineWidth(1)
            end
        end
    end)

    if preview then
        local col = preview.valid and preview.color or C.COLOR.PREVIEW_INVALID
        love.graphics.setColor(col[1], col[2], col[3], 0.5)
        for _, t in ipairs(preview.tiles) do
            love.graphics.polygon("fill", Iso.tile_corners(t.x, t.y))
        end
    end

    if hover and Grid.in_bounds(world.grid, hover.x, hover.y) then
        local h = C.COLOR.HIGHLIGHT
        love.graphics.setColor(h[1], h[2], h[3], 0.45)
        love.graphics.polygon("fill", Iso.tile_corners(hover.x, hover.y))
    end

    Camera.clear()
end

return Renderer
