-- main.lua
-- LÖVE entry point and orchestration. It owns no game logic,
-- it wires the pieces together and routes LÖVE's callbacks to them:
--   setup:  bus + world + camera + runner (clock/demand/growth) + zoning
--   update: pan camera, hold-to-paint, advance the sim by speed-scaled dt
--   draw:   hand the world to the renderer, then the debug HUD
--   input:  select tool (1/2/3), change speed, zoom

local C = require("src.world.constants")
local World = require("src.world.world")
local Bus = require("src.bus")
local Grid = require("src.world.grid")
local Runner = require("src.systems.runner")
local Clock = require("src.systems.clock")
local Demand = require("src.systems.demand")
local Growth = require("src.systems.growth")
local Zoning = require("src.systems.zoning")
local Tools = require("src.input.tools")
local Camera = require("src.render.camera")
local Iso = require("src.render.iso")
local Renderer = require("src.render.renderer")

local world, cam, runner
local speed = C.SPEED.NORMAL
local current_tool = C.TOOL.ZONE_RES

local TOOL_NAME = {
    [C.TOOL.BULLDOZE] = "Bulldoze",
    [C.TOOL.ZONE_RES] = "Residential",
    [C.TOOL.ZONE_COM] = "Commercial",
}

-- Mouse position -> tile under the cursor, or nil if off-grid. Shared by the
-- paint loop and the hover highlight: screen -> world (camera) -> tile (iso).
local function hovered_tile()
    local mx, my = love.mouse.getPosition()
    local wx, wy = Camera.screen_to_world(cam, mx, my)
    local tx, ty = Iso.screen_to_tile(wx, wy)
    if Grid.in_bounds(world.grid, tx, ty) then return tx, ty end
    return nil
end

function love.load()
    love.graphics.setFont(love.graphics.newFont(15))
    love.graphics.setBackgroundColor(C.COLOR.BG)

    Bus.clear()
    world = World.new(os.time()) -- seed varies per run
    cam = Camera.new()

    runner = Runner.new()
    Runner.add(runner, Clock.system())
    Runner.add(runner, Demand.system())
    Runner.add(runner, Growth.system())
    Zoning.install(world)
end

function love.update(dt)
    Camera.update(cam, dt) -- WASD pan

    -- Hold primary button to paint the hovered tile (tap = one, drag = many).
    if love.mouse.isDown(1) then
        local tx, ty = hovered_tile()
        if tx then Tools.apply(current_tool, world, tx, ty) end
    end

    -- Advance the simulation by speed-scaled time. speed 0 (paused) feeds 0.
    Runner.update(runner, dt * speed, world)
end

function love.draw()
    local tx, ty = hovered_tile()
    Renderer.draw(world, cam, tx and { x = tx, y = ty } or nil)

    -- Debug HUD (replaced by a real hud.lua in Step I).
    love.graphics.setColor(1, 1, 1)
    local year, month = Clock.date(world)
    local speed_name = (speed == C.SPEED.PAUSED) and "Paused"
        or (speed == C.SPEED.FAST) and "Fast" or "Normal"
    local res_n = World.count_buildings(world, C.ZONE.RESIDENTIAL, C.BUILD.COMPLETE)
    local com_n = World.count_buildings(world, C.ZONE.COMMERCIAL, C.BUILD.COMPLETE)

    love.graphics.print("Slow Grid - Phase 1", 16, 16)
    love.graphics.print(("Date %04d-%02d   Speed: %s   FPS %d")
        :format(year, month, speed_name, love.timer.getFPS()), 16, 38)
    love.graphics.print(("Pop %d    Residential %d    Commercial %d")
        :format(World.population(world), res_n, com_n), 16, 60)
    love.graphics.print(("Demand   R %+.2f    C %+.2f")
        :format(world.demand.residential, world.demand.commercial), 16, 82)
    love.graphics.print(("Tool: %s"):format(TOOL_NAME[current_tool]), 16, 104)
    love.graphics.print(
        "[1]Bulldoze [2]Res [3]Com  |  hold-click paint  |  space pause  +/- speed  |  WASD/scroll camera",
        16, love.graphics.getHeight() - 28)
end

function love.keypressed(key)
    if key == "escape" then
        love.event.quit()
    elseif key == "1" then
        current_tool = C.TOOL.BULLDOZE
    elseif key == "2" then
        current_tool = C.TOOL.ZONE_RES
    elseif key == "3" then
        current_tool = C.TOOL.ZONE_COM
    elseif key == "space" then
        speed = (speed == C.SPEED.PAUSED) and C.SPEED.NORMAL or C.SPEED.PAUSED
    elseif key == "+" or key == "=" or key == "kp+" then
        -- '+' is shift+'=' on most Mac layouts, so accept '=' too.
        speed = C.SPEED.FAST
    elseif key == "-" or key == "kp-" then
        speed = C.SPEED.NORMAL
    end
end

-- Wheel notches drive cursor-anchored zoom (two-finger trackpad scroll).
function love.wheelmoved(_dx, dy)
    Camera.zoom(cam, dy, love.mouse.getPosition())
end
