-- main.lua
-- LÖVE entry point and orchestration. Owns no game logic; wires the pieces
-- together and routes LÖVE's callbacks to them:
--   boot:    Theme + ScreenManager + Home; app starts on the menu, NOT in-game
--   in-game: bus + world + camera + runner (clock/demand/growth/economy) + zoning
--   update:  pan camera, hold-to-paint, advance the sim by speed-scaled dt — gated
--            on mgr:should_tick() so menu/modal halts the sim
--   draw:    iso world + HUD when in_game; ALWAYS overlay the menu/modal layer
--   input:   in-game keys (tool, speed, save/load) run only when in_game AND no
--            modal; menu screens consume input via the manager

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
local Roads = require("src.systems.roads")
local Power = require("src.systems.power")
local Pollution = require("src.systems.pollution")
local Tools = require("src.input.tools")
local Drag = require("src.input.drag")
local Camera = require("src.render.camera")
local Iso = require("src.render.iso")
local Renderer = require("src.render.renderer")
local Hud = require("src.ui.hud")
local Save = require("src.persistence.save")
local Theme = require("src.ui.theme")
local ScreenManager = require("src.ui.screen_manager")
local Home = require("src.ui.screens.home")

local world, cam, runner
local mgr
local speed = C.SPEED.NORMAL
local current_tool = C.TOOL.ZONE_RES
local current_overlay = C.OVERLAY.NONE

-- Overlay cycle order for the [O] key: off -> pollution -> land value -> power -> off.
local OVERLAY_CYCLE = {
    [C.OVERLAY.NONE]       = C.OVERLAY.POLLUTION,
    [C.OVERLAY.POLLUTION]  = C.OVERLAY.LAND_VALUE,
    [C.OVERLAY.LAND_VALUE] = C.OVERLAY.POWER,
    [C.OVERLAY.POWER]      = C.OVERLAY.NONE,
}

-- Number keys 1-7 select a tool.
local TOOL_KEYS = {
    ["1"] = C.TOOL.BULLDOZE,
    ["2"] = C.TOOL.ZONE_RES,
    ["3"] = C.TOOL.ZONE_COM,
    ["4"] = C.TOOL.ZONE_IND,
    ["5"] = C.TOOL.ROAD,
    ["6"] = C.TOOL.POWER_LINE,
    ["7"] = C.TOOL.PLANT,
}

-- Tile coords where the current drag began (nil when not dragging). Roads and
-- zones build on press/drag/release; bulldoze stays hold-to-paint.
local drag_start = nil

local ZONE_OF = {
    [C.TOOL.ZONE_RES] = C.ZONE.RESIDENTIAL,
    [C.TOOL.ZONE_COM] = C.ZONE.COMMERCIAL,
    [C.TOOL.ZONE_IND] = C.ZONE.INDUSTRIAL,
}
local ZONE_PREVIEW_COLOR = {
    [C.ZONE.RESIDENTIAL] = C.COLOR.ZONE_RES,
    [C.ZONE.COMMERCIAL]  = C.COLOR.ZONE_COM,
    [C.ZONE.INDUSTRIAL]  = C.COLOR.ZONE_IND,
}

local function is_drag_tool(tool)
    return tool == C.TOOL.ROAD or tool == C.TOOL.POWER_LINE or ZONE_OF[tool] ~= nil
end

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
    Roads.install(w)   -- recomputes the road-connectivity cache from the grid (on load too)
    Power.install(w)   -- AFTER Roads: the plant-supply gate reads roads.connected (bus order)
    Pollution.install(w) -- subscribes source events (sets dirty); seeds the field from the grid
    Economy.install(w) -- subscribes the one-time road/line/plant debits
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

-- Given the cursor tile during an active drag, return the preview overlay
-- and its live cost. Roads preview an axis-only run; zones preview the
-- bounding rectangle.
local function current_drag(cx, cy)
    local sx, sy = drag_start.x, drag_start.y
    if current_tool == C.TOOL.ROAD then
        local run = Drag.road_run(sx, sy, cx, cy)
        local valid = Drag.road_run_valid(world, run) and Drag.road_affordable(world, run)
        return { tiles = run, color = C.COLOR.PREVIEW_ROAD, valid = valid }, Drag.road_cost(world, run)
    end
    if current_tool == C.TOOL.POWER_LINE then
        -- Power lines reuse the road run's geometry and validity; only price differs.
        local run = Drag.road_run(sx, sy, cx, cy)
        local valid = Drag.road_run_valid(world, run) and Drag.power_line_affordable(world, run)
        return { tiles = run, color = C.COLOR.POWER_LINE, valid = valid }, Drag.power_line_cost(world, run)
    end
    local zone = ZONE_OF[current_tool]
    if not zone then return nil end -- tool is not a zone (e.g. changed mid-drag): no preview
    local tiles = Drag.zone_rect(world, sx, sy, cx, cy)
    local valid = Drag.zone_affordable(world, tiles, zone)
    return { tiles = tiles, color = ZONE_PREVIEW_COLOR[zone], valid = valid }, Drag.zone_cost(world, tiles, zone)
end

-- Build a fresh mission from a seed: world, camera, runner, event wiring.
-- Hoisted out of love.load so the Home actions ("New Mission", "Continue")
-- can call it. Continue replaces the world post-construction via Save.load
-- and re-wires; this helper only handles the fresh-mission path.
local function start_mission(seed)
    world = World.new(seed)
    cam = Camera.new()
    runner = Runner.new()
    Runner.add(runner, Clock.system())
    Runner.add(runner, Demand.system())
    Runner.add(runner, Growth.system())
    Runner.add(runner, Economy.system())
    wire_world(world)
    mgr.in_game = true
    mgr:clear_current() -- in-game = no menu surface underneath
end

-- Home action closures. Step 3 stubs for archive/settings (later steps wire
-- real screens); continue/new_mission/end_transmission do their real work.
local function home_actions()
    return {
        continue = function()
            local loaded = Save.load(1)
            if not loaded then return end -- silent no-op until step 7 surfaces a flash
            world = loaded
            cam = Camera.new()
            runner = Runner.new()
            Runner.add(runner, Clock.system())
            Runner.add(runner, Demand.system())
            Runner.add(runner, Growth.system())
            Runner.add(runner, Economy.system())
            wire_world(world)
            mgr.in_game = true
            mgr:clear_current()
        end,
        new_mission      = function() start_mission(os.time()) end,
        archive          = function() end, -- step 7
        settings         = function() end, -- step 8
        end_transmission = function() love.event.quit() end,
    }
end

function love.load()
    love.graphics.setBackgroundColor(C.UI.bg)
    Theme.init(love.graphics.newFont)
    love.graphics.setFont(Theme.font("body"))

    mgr = ScreenManager.new()
    mgr:register("home", Home.new(home_actions()))
    mgr:set_current("home")
    -- in_game stays false: the app boots on the menu, not in a running mission.
end

function love.update(dt)
    -- Camera pan (WASD) responds whenever a mission is loaded, even with a
    -- modal open (PRD: pan/zoom continue to work behind the Pause modal).
    if cam then Camera.update(cam, dt) end

    if mgr:should_tick() then
        -- Bulldoze paints on hold (tap = one, drag = many). Roads and zones build
        -- on release via a drag preview (see mousepressed/mousereleased).
        if current_tool == C.TOOL.BULLDOZE and love.mouse.isDown(1) then
            local tx, ty = hovered_tile()
            if tx then Tools.apply(C.TOOL.BULLDOZE, world, tx, ty) end
        end
        -- Advance the simulation by speed-scaled time. speed 0 (paused) feeds 0.
        Runner.update(runner, dt * speed, world)
    end

    -- Keep pollution-derived caches current for the overlays even between
    -- growth ticks: resolve is a no-op unless the field is dirty.
    if mgr.in_game then Pollution.resolve(world) end

    mgr:update(dt)
end

function love.draw()
    if mgr.in_game then
        local tx, ty = hovered_tile()
        local preview, drag_cost
        if drag_start and tx then
            preview, drag_cost = current_drag(tx, ty)
        elseif current_tool == C.TOOL.PLANT and tx then
            -- Plant is a single click, not a drag: preview its 2x2 footprint under
            -- the cursor, red when blocked or unaffordable.
            local valid = Drag.plant_footprint_valid(world, tx, ty) and Drag.plant_affordable(world)
            preview = { tiles = Drag.plant_footprint(tx, ty), color = C.COLOR.PLANT, valid = valid }
            drag_cost = Drag.plant_cost()
        end
        Renderer.draw(world, cam, tx and { x = tx, y = ty } or nil, preview, current_overlay)
        local msg = (love.timer.getTime() < status_until) and status_msg or nil
        Hud.draw(world, { tool = current_tool, speed = speed, status = msg, drag_cost = drag_cost, overlay = current_overlay })
    end
    -- Menu screens + modals draw on top (layered overlay).
    mgr:draw()
end

-- Helper: are we live in-game with no modal in the way? Tools/speed/save keys
-- and mouse-driven build only run when this is true.
local function in_game_active()
    return mgr.in_game and mgr:modal_count() == 0
end

function love.keypressed(key)
    -- Menu/modal first; they consume input when active.
    mgr:keypressed(key)
    if not in_game_active() then return end

    local tool = TOOL_KEYS[key]
    if tool then
        current_tool = tool
        drag_start = nil -- switching tools cancels any in-progress drag
        return
    end
    if key == "o" then
        current_overlay = OVERLAY_CYCLE[current_overlay] or C.OVERLAY.NONE
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
    -- Note: Esc-in-game quit went away with step 3. The Pause modal (step 4)
    -- will subscribe to Esc here; until then Esc has no in-game binding.
end

-- Begin a road/zone drag: anchor on the tile under the cursor (in tile coords,
-- so panning mid-drag doesn't move the anchor). Bulldoze isn't a drag tool.
function love.mousepressed(x, y, button)
    mgr:mousepressed(x, y, button)
    if not in_game_active() then return end
    if button ~= 1 then return end
    local tx, ty = hovered_tile()
    if not tx then return end
    -- Plant places on a single click (not a drag), all-or-nothing and self-gating.
    if current_tool == C.TOOL.PLANT then
        Tools.apply_plant(world, tx, ty)
        return
    end
    if is_drag_tool(current_tool) then drag_start = { x = tx, y = ty } end
end

-- Commit the drag on release. apply_run/apply_rect are all-or-nothing and
-- self-validating, so an invalid/unaffordable drag is a safe no-op.
function love.mousereleased(x, y, button)
    mgr:mousereleased(x, y, button)
    if not in_game_active() then return end
    if button ~= 1 or not drag_start then return end
    local cx, cy = hovered_tile()
    if cx then
        if current_tool == C.TOOL.ROAD then
            Tools.apply_run(world, Drag.road_run(drag_start.x, drag_start.y, cx, cy))
        elseif current_tool == C.TOOL.POWER_LINE then
            Tools.apply_line_run(world, Drag.road_run(drag_start.x, drag_start.y, cx, cy))
        else
            Tools.apply_rect(current_tool, world, Drag.zone_rect(world, drag_start.x, drag_start.y, cx, cy))
        end
    end
    drag_start = nil
end

-- Hover routing for menu screens (Home highlights the row under the cursor).
-- In-game has no hover-driven state, so this is menu-only.
function love.mousemoved(x, y)
    mgr:mousemoved(x, y)
end

-- Wheel notches drive cursor-anchored zoom (two-finger trackpad scroll).
function love.wheelmoved(dx, dy)
    mgr:wheelmoved(dx, dy)
    if cam and mgr.in_game then
        -- Zoom continues to respond behind a modal, mirroring camera pan.
        Camera.zoom(cam, dy, love.mouse.getPosition())
    end
end
