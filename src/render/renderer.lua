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
local C = require("src.world.constants")

local Renderer = {}

local BUILD_SCALE = 0.55 -- building diamond size relative to the tile

local function tile_color(tile, x, y)
    if tile.zone == C.ZONE.RESIDENTIAL then return C.COLOR.ZONE_RES end
    if tile.zone == C.ZONE.COMMERCIAL then return C.COLOR.ZONE_COM end
    -- unzoned: keep the grass checkerboard
    return ((x + y) % 2 == 0) and C.COLOR.GRASS_A or C.COLOR.GRASS_B
end

local function building_color(tile)
    if tile.building.state == C.BUILD.CONSTRUCTING then return C.COLOR.BUILD_PENDING end
    if tile.zone == C.ZONE.RESIDENTIAL then return C.COLOR.BUILD_RES end
    if tile.zone == C.ZONE.COMMERCIAL then return C.COLOR.BUILD_COM end
    return C.COLOR.BUILD_PENDING
end

function Renderer.draw(world, cam, hover)
    Camera.apply(cam)

    Grid.each(world.grid, function(x, y, tile)
        love.graphics.setColor(tile_color(tile, x, y))
        love.graphics.polygon("fill", Iso.tile_corners(x, y))
        love.graphics.setColor(C.COLOR.TILE_LINE)
        love.graphics.polygon("line", Iso.tile_corners(x, y))

        if tile.building then
            local cx, cy = Iso.tile_to_screen(x, y)
            local hw = (C.TILE_W / 2) * BUILD_SCALE
            local hh = (C.TILE_H / 2) * BUILD_SCALE
            love.graphics.setColor(building_color(tile))
            love.graphics.polygon("fill", cx, cy - hh, cx + hw, cy, cx, cy + hh, cx - hw, cy)
        end
    end)

    if hover and Grid.in_bounds(world.grid, hover.x, hover.y) then
        local h = C.COLOR.HIGHLIGHT
        love.graphics.setColor(h[1], h[2], h[3], 0.45)
        love.graphics.polygon("fill", Iso.tile_corners(hover.x, hover.y))
    end

    Camera.clear()
end

return Renderer
