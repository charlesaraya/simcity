-- src/render/iso.lua
-- Isometric projection: the linear map between grid coordinates and screen pixels.
--
-- A diamond grid is a square grid run through a linear transform. tile_to_screen
-- and screen_to_tile are exact inverses; tile_corners gives the four diamond
-- vertices for drawing. All screen coordinates here are in WORLD space (before
-- the camera applies its pan/zoom) -- the camera, added in Step D, handles that.

local C = require("src.world.constants")

local Iso = {}

local HW = C.TILE_W / 2 -- half tile width  (32)
local HH = C.TILE_H / 2 -- half tile height (16)

-- Grid (x, y) -> screen pixel of the tile's CENTER.
--   cx = (x - y) * HW
--   cy = (x + y) * HH
-- Anchoring on the center (not a corner) makes the inverse a clean round().
function Iso.tile_to_screen(x, y)
    return (x - y) * HW, (x + y) * HH
end

-- Screen pixel -> grid (x, y), inverting tile_to_screen.
-- Solve the two equations:
--   x - y = sx / HW
--   x + y = sy / HH
-- => x = (sx/HW + sy/HH) / 2 ,  y = (sy/HH - sx/HW) / 2
-- The diamond around a tile maps to a unit square centered on its integer
-- coords, so we ROUND to land on the right tile. floor() would be off by half.
function Iso.screen_to_tile(sx, sy)
    local fx = (sx / HW + sy / HH) / 2
    local fy = (sy / HH - sx / HW) / 2
    return math.floor(fx + 0.5), math.floor(fy + 0.5)
end

-- The four diamond vertices for tile (x, y), as a flat list of 8 numbers
-- (top, right, bottom, left) ready to hand to love.graphics.polygon.
function Iso.tile_corners(x, y)
    local cx, cy = Iso.tile_to_screen(x, y)
    return cx, cy - HH,      -- top
        cx + HW, cy,         -- right
        cx, cy + HH,         -- bottom
        cx - HW, cy          -- left
end

return Iso
