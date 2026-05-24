-- src/render/camera.lua
-- The camera is state plus a transform: { x, y, scale }, where (x, y) is the
-- WORLD point pinned to the center of the screen, and scale is the zoom factor.
--
-- apply() pushes the transform so anything drawn after it lands in world space;
-- clear() pops it. screen_to_world() inverts the transform so screen-space input
-- (the mouse) can be turned back into world coordinates for picking.

local C = require("src.world.constants")

local Camera = {}

function Camera.new()
    -- Start centered on the middle of the grid so the field is in view.
    local cx, cy = (C.GRID_W) / 2, (C.GRID_H) / 2
    -- That is tile space; convert to world pixels via the same projection iso uses.
    local wx = (cx - cy) * (C.TILE_W / 2)
    local wy = (cx + cy) * (C.TILE_H / 2)
    return { x = wx, y = wy, scale = 1.0 }
end

-- Push the camera transform. Order matters: move origin to screen center, then
-- scale, then translate by the negated camera position. Read it inside-out:
-- a world point p draws at  (p - cam) * scale + screenCenter.
function Camera.apply(cam)
    local w, h = love.graphics.getDimensions()
    love.graphics.push()
    love.graphics.translate(w / 2, h / 2)
    love.graphics.scale(cam.scale)
    love.graphics.translate(-cam.x, -cam.y)
end

function Camera.clear()
    love.graphics.pop()
end

-- Invert the transform: screen pixel -> world pixel.
--   world = (screen - screenCenter) / scale + cam
function Camera.screen_to_world(cam, sx, sy)
    local w, h = love.graphics.getDimensions()
    local wx = (sx - w / 2) / cam.scale + cam.x
    local wy = (sy - h / 2) / cam.scale + cam.y
    return wx, wy
end

-- WASD panning. Dividing by scale keeps the on-screen pan speed constant
-- regardless of zoom (pan covers fewer world pixels when zoomed in).
function Camera.update(cam, dt)
    local speed = C.CAM.PAN_SPEED * dt / cam.scale
    if love.keyboard.isDown("a") then cam.x = cam.x - speed end
    if love.keyboard.isDown("d") then cam.x = cam.x + speed end
    if love.keyboard.isDown("w") then cam.y = cam.y - speed end
    if love.keyboard.isDown("s") then cam.y = cam.y + speed end
end

-- Cursor-anchored zoom, driven by wheel notches (dy). The world point under the
-- cursor must stay under the cursor after zooming: sample it before changing
-- scale, then shift the camera so it maps back to the same world point.
function Camera.zoom(cam, dy, mx, my)
    if dy == 0 then return end
    local wx_before, wy_before = Camera.screen_to_world(cam, mx, my)

    local factor = C.CAM.ZOOM_STEP ^ dy
    cam.scale = math.max(C.CAM.ZOOM_MIN, math.min(C.CAM.ZOOM_MAX, cam.scale * factor))

    local wx_after, wy_after = Camera.screen_to_world(cam, mx, my)
    cam.x = cam.x + (wx_before - wx_after)
    cam.y = cam.y + (wy_before - wy_after)
end

return Camera
