-- conf.lua
-- LÖVE reads this BEFORE main.lua to configure the window and runtime.
-- Keeping config out of game code means window/title/flags change here, nowhere else.

function love.conf(t)
    t.identity = "slowgrid"          -- save-directory name (used later for save/load)
    t.version = "11.4"               -- LÖVE API version this game targets

    t.window.title = "Slow Grid"
    t.window.width = 1280
    t.window.height = 720
    t.window.resizable = true
    t.window.highdpi = true          -- crisp rendering on Retina MacBook displays
    t.window.vsync = 1               -- cap to display refresh; avoids tearing + wasted GPU

    -- Trim subsystems we don't use yet. Less to load, fewer surprises.
    t.modules.joystick = false
    t.modules.physics = false        -- no continuous physics; the grid is the world
end
