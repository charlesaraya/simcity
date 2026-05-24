-- main.lua
-- LÖVE entry point and orchestration. It owns no game logic,
-- it wires the pieces together and routes LÖVE's callbacks to them:
--   setup:  bus + world + camera + runner (clock/demand/growth/economy) + zoning
--   update: pan camera, hold-to-paint, advance the sim by speed-scaled dt
--   draw:   hand the world to the renderer, then the debug HUD
--   input:  select tool (1/2/3/4), change speed, zoom

local C = require("src.world.constants")
local World = require("src.world.world")
local Bus = require("src.bus")
local Grid = require("src.world.grid")
local Runner = require("src.systems.runner")
local Clock = require("src.systems.clock")
local Demand = require("src.systems.demand")
local Growth = require("src.systems.growth")
local Economy = require("src.systems.economy")
local Zoning = require("src.systems.zoning")
local Tools = require("src.input.tools")
local Camera = require("src.render.camera")
local Iso = require("src.render.iso")
local Renderer = require("src.render.renderer")
local Hud = require("src.ui.hud")
local Save = require("src.persistence.save")

local world, cam, runner
local speed = C.SPEED.NORMAL
local current_tool = C.TOOL.ZONE_RES

-- Transient HUD status ("Saved"/"Loaded"), cleared after a short while.
local status_msg, status_until = nil, 0
local function flash(msg)
    status_msg = msg
    status_until = love.timer.getTime() + 1.5
end

-- (Re)wire event-driven systems onto a world. Zoning subscribes with a closure
-- over the world, so after a load (a new world table) the bus must be cleared
-- and zoning re-installed. Ticking systems take world as an argument, so they
-- need no rewiring.
local function wire_world(w)
    Bus.clear()
    Zoning.install(w)
end

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

    world = World.new(os.time()) -- seed varies per run
    cam = Camera.new()

    runner = Runner.new()
    Runner.add(runner, Clock.system())
    Runner.add(runner, Demand.system())
    Runner.add(runner, Growth.system())
    Runner.add(runner, Economy.system())
    wire_world(world)
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
    local msg = (love.timer.getTime() < status_until) and status_msg or nil
    Hud.draw(world, { tool = current_tool, speed = speed, status = msg })
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
    elseif key == "4" then
        current_tool = C.TOOL.ZONE_IND
    elseif key == "space" then
        speed = (speed == C.SPEED.PAUSED) and C.SPEED.NORMAL or C.SPEED.PAUSED
    elseif key == "+" or key == "=" or key == "kp+" then
        -- '+' is shift+'=' on most Mac layouts, so accept '=' too.
        speed = C.SPEED.FAST
    elseif key == "-" or key == "kp-" then
        speed = C.SPEED.NORMAL
    elseif key == "f5" then
        Save.save(world, 1)
        flash("Saved")
    elseif key == "f9" then
        local loaded = Save.load(1)
        if loaded then
            world = loaded
            wire_world(world)
            flash("Loaded")
        else
            flash("No save")
        end
    end
end

-- Wheel notches drive cursor-anchored zoom (two-finger trackpad scroll).
function love.wheelmoved(_dx, dy)
    Camera.zoom(cam, dy, love.mouse.getPosition())
end
