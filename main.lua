-- main.lua
-- LÖVE entry point and orchestration. Wires the world grid and the camera,
-- then drives them through LÖVE's callbacks:
--   love.load        build grid + camera
--   love.update(dt)  pan the camera (WASD)
--   love.draw        render the grid through the camera, highlight the picked tile
--   love.keypressed  Esc to quit
--   love.wheelmoved  cursor-anchored zoom
--
-- Picking pipeline: screen -> Camera.screen_to_world -> Iso.screen_to_tile.

local Grid = require("src.world.grid")
local Iso = require("src.render.iso")
local Camera = require("src.render.camera")
local C = require("src.world.constants")

local grid -- the world's tile data
local cam  -- the view: pan + zoom

function love.load()
    -- A readable default font size for debug text.
    love.graphics.setFont(love.graphics.newFont(16))
    love.graphics.setBackgroundColor(C.COLOR.BG)

    grid = Grid.new() -- 64x64 of grass
    cam = Camera.new()

    -- Sanity check: idx and coord must be inverses. If this assertion fires,
    -- the index math is wrong and everything downstream breaks.
    local i = Grid.idx(grid, 7, 12)
    local x, y = Grid.coord(grid, i)
    assert(x == 7 and y == 12, "idx/coord round-trip broken")
end

function love.update(dt)
    Camera.update(cam, dt) -- WASD panning
end

function love.draw()
    -- World space: everything between apply() and clear() draws through the
    -- camera transform (pan + zoom).
    Camera.apply(cam)

    -- Draw every tile as a filled diamond, checkerboarded so individual tiles
    -- are visible. (4096 polygons/frame is fine at vsync for now; Phase 0
    -- placeholder. Terrain moves to a SpriteBatch when performance matters.)
    Grid.each(grid, function(x, y, _tile)
        local fill = ((x + y) % 2 == 0) and C.COLOR.GRASS_A or C.COLOR.GRASS_B
        love.graphics.setColor(fill)
        love.graphics.polygon("fill", Iso.tile_corners(x, y))
        love.graphics.setColor(C.COLOR.TILE_LINE)
        love.graphics.polygon("line", Iso.tile_corners(x, y))
    end)

    -- Picking through TWO inverse transforms: screen -> world (camera) ->
    -- tile (iso). If the highlight still tracks under pan and zoom, both are right.
    local mx, my = love.mouse.getPosition()
    local wx, wy = Camera.screen_to_world(cam, mx, my)
    local tx, ty = Iso.screen_to_tile(wx, wy)
    local hovering = Grid.in_bounds(grid, tx, ty)
    if hovering then
        love.graphics.setColor(C.COLOR.HIGHLIGHT[1], C.COLOR.HIGHLIGHT[2],
            C.COLOR.HIGHLIGHT[3], 0.55)
        love.graphics.polygon("fill", Iso.tile_corners(tx, ty))
    end

    Camera.clear()

    -- Screen space HUD (drawn after clear(), so the camera transform is gone).
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("Slow Grid - Phase 0, Step D", 16, 16)
    love.graphics.print(("FPS: %d"):format(love.timer.getFPS()), 16, 40)
    love.graphics.print(
        hovering and ("Hover tile: %d, %d"):format(tx, ty) or "Hover tile: -",
        16, 64)
    love.graphics.print(("Zoom: %.2fx"):format(cam.scale), 16, 88)
    love.graphics.print("WASD pan - scroll zoom - Esc quit", 16, 112)
end

function love.keypressed(key)
    if key == "escape" then
        love.event.quit()
    end
end

-- Wheel notches (dy) drive zoom, anchored at the cursor. Two-finger trackpad
-- scroll arrives here as wheel events.
function love.wheelmoved(_dx, dy)
    Camera.zoom(cam, dy, love.mouse.getPosition())
end
