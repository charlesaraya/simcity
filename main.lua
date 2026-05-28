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
local Meta = require("src.persistence.meta")
local Theme = require("src.ui.theme")
local ScreenManager = require("src.ui.screen_manager")
local Home = require("src.ui.screens.home")
local PauseModal = require("src.ui.screens.pause_modal")
local NewMission = require("src.ui.screens.new_mission")
local Archive = require("src.ui.screens.archive")
local Settings = require("src.ui.screens.settings")
local MissionControl = require("src.ui.screens.mission_control")
local RNG = require("src.sim.rng")

local world, cam, runner
local mgr
local speed = C.SPEED.NORMAL
local current_tool = C.TOOL.ZONE_RES
local current_overlay = C.OVERLAY.NONE

-- Save slug the live mission belongs to (Phase 4c-2: slug-based on-disk
-- layout, saves/<slug>/world.lua + meta.lua). F5 / pause "Save to Archive"
-- write here; "Continue Operations" loads the newest by saved_at; New
-- Mission mints a slug at charter time from the chosen mission name.
local current_slug = nil
-- Real seconds the player has spent in this mission with the sim ticking.
-- Stamped into meta.time_played on save; restored on load.
local mission_elapsed = 0

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

-- Per-call entropy: os.time() advances only once a second, so two New Mission
-- entries or charters in the same wall-clock second would otherwise share an
-- RNG seed (same suggested name, same world seed). Mix in love.timer's
-- microsecond clock and an incrementing counter so consecutive calls always
-- diverge -- even within the same frame.
local seed_counter = 0
local function fresh_seed()
    seed_counter = seed_counter + 1
    local micros = math.floor((love.timer and love.timer.getTime() or 0) * 1e6)
    return os.time() + micros + seed_counter
end

-- Build the meta sidecar table for the live world. Stamps saved_at to now
-- and reads the current mission_elapsed counter as time_played.
local function build_meta()
    return Meta.from_world(world, {
        slug        = current_slug,
        saved_at    = os.time(),
        time_played = math.floor(mission_elapsed),
        population  = World.population(world),
    })
end

-- Write both the world and its sidecar. The pair always stays in sync --
-- one isn't useful without the other.
local function persist()
    Save.save(world, current_slug)
    Meta.save(current_slug, build_meta())
end

-- Install a world (fresh or loaded) as the live mission: bind it to the
-- runtime globals, build a fresh camera + runner, and re-wire event-driven
-- systems onto it. Shared by start_mission, load_into_mission, and Archive's
-- Continue. Does NOT flip in_game / clear_current — callers own the UI
-- transition.
local function install_world(w)
    world = w
    cam = Camera.new()
    runner = Runner.new()
    Runner.add(runner, Clock.system())
    Runner.add(runner, Demand.system())
    Runner.add(runner, Growth.system())
    Runner.add(runner, Economy.system())
    wire_world(world)
end

-- Build a fresh mission from a seed and enter in-game. current_slug is left
-- nil; the charter action mints one once the player has named the mission.
local function start_mission(seed)
    install_world(World.new(seed))
    current_slug = nil
    mission_elapsed = 0
    mgr.in_game = true
    mgr:clear_current()
end

-- Load the most recent save (newest saved_at across all sidecars) into the
-- live mission. Returns true on success. Used by Home's Continue Operations.
local function load_into_mission()
    local metas = Meta.list()
    if #metas == 0 then return false end
    local newest = metas[1] -- Meta.list returns sorted desc by saved_at
    local loaded = Save.load(newest.slug)
    if not loaded then return false end
    install_world(loaded)
    current_slug = newest.slug
    mission_elapsed = newest.time_played or 0
    return true
end

-- Convert a meta sidecar (Meta.list shape) into the table the Archive screen
-- consumes. `ordinal` is a 1..N row index used for display only -- the slug
-- is the stable identifier across reloads.
local function build_slot_entry(ordinal, meta)
    return {
        slot         = ordinal,
        slug         = meta.slug,
        mission_name = meta.mission_name,
        cycle        = meta.cycle or 0,
        population   = meta.population or 0,
        treasury     = meta.treasury or 0,
        difficulty   = meta.difficulty,
        saved_at     = meta.saved_at,
        time_played  = meta.time_played or 0,
        world_params = meta.world_params,
    }
end

-- Archive action closures. Back returns to Home; Continue loads the slot's
-- world from disk by slug, installs it, and rebinds current_slug.
local function archive_actions()
    return {
        back = function() mgr:set_current("home") end,
        continue = function(slot)
            local loaded = Save.load(slot.slug)
            if not loaded then return end
            install_world(loaded)
            current_slug = slot.slug
            mission_elapsed = slot.time_played or 0
            mgr.in_game = true
            mgr:clear_current()
        end,
    }
end

-- NewMission action closures. Back returns to Home; Charter commits the form:
-- start a fresh mission world, populate crew + mission, then mint a unique
-- slug from the chosen mission name (write-side identity binds here).
local function new_mission_actions()
    return {
        back = function() mgr:set_current("home") end,
        charter = function(payload)
            local mission = payload.mission
            mission.started_at = os.time()
            start_mission(fresh_seed()) -- builds world/runner/wires; flips in_game on
            World.charter(world, mission, payload.crew)
            current_slug = Meta.unique_slug(Meta.slugify(mission.name))
            world.slug = current_slug -- written into the world too so loaded games know their home
        end,
    }
end

-- Home action closures. Step 3 stubs for archive/settings (later steps wire
-- real screens); continue/new_mission/end_transmission do their real work.
local function home_actions()
    return {
        continue = function()
            if not load_into_mission() then return end -- silent no-op until step 7 surfaces a flash
            mgr.in_game = true
            mgr:clear_current()
        end,
        -- Fresh charter screen on each entry: a new RNG seed gives a different
        -- suggested mission + crew each time, so Back/re-enter feels alive.
        new_mission = function()
            mgr:register("new_mission", NewMission.new({
                rng = RNG.new(fresh_seed()),
                actions = new_mission_actions(),
            }))
            mgr:set_current("new_mission")
        end,
        archive = function()
            -- Cheap meta-sidecar scan (no world deserialization). Slots come
            -- back sorted newest-first by saved_at; ordinals reflect that.
            local metas = Meta.list()
            local slots = {}
            for i, m in ipairs(metas) do
                slots[i] = build_slot_entry(i, m)
            end
            mgr:register("archive", Archive.new({
                slots = slots,
                actions = archive_actions(),
            }))
            mgr:set_current("archive")
        end,
        settings = function()
            mgr:set_current("settings")
        end,
        end_transmission = function() love.event.quit() end,
    }
end

-- Pause-modal action closures. Save stays on the modal (player can save without
-- resuming); Load pops back to the now-loaded world; Mission Control is a stub
-- until step 9 wires the crew dashboard. End Transmission quits regardless of
-- save state (4c-2 adds the "save first?" prompt).
local function pause_actions()
    return {
        resume = function()
            mgr:pop_modal()
        end,
        save_to_archive = function()
            -- Write the live mission's world AND its meta sidecar. current_slug
            -- is set at charter / continue / archive-load.
            persist()
            -- Stay on the modal so the player sees the menu after the action.
        end,
        load_from_archive = function()
            if not load_into_mission() then return end -- silent no-op for now
            mgr:pop_modal()
        end,
        mission_control = function()
            -- Replace the pause modal with Mission Control on the stack so the
            -- sim stays paused (modal_count > 0) and Back can re-push pause.
            mgr:pop_modal()
            local cycle = math.floor(((world.clock and world.clock.months) or 0)
                                     / C.SIM.MONTHS_PER_YEAR)
            mgr:register("mission_control", MissionControl.new({
                mission = world.mission or {},
                crew = world.crew or {},
                cycle = cycle,
                actions = {
                    back = function()
                        mgr:pop_modal()
                        mgr:push_modal("pause_modal")
                    end,
                    return_to_home = function()
                        mgr:clear_modals()
                        mgr.in_game = false
                        mgr:set_current("home")
                    end,
                },
            }))
            mgr:push_modal("mission_control")
        end,
        end_transmission = function() love.event.quit() end,
    }
end

function love.load()
    love.graphics.setBackgroundColor(C.UI.bg)
    Theme.init(love.graphics.newFont)
    love.graphics.setFont(Theme.font("body"))

    -- 4c-2: convert any pre-existing flat save1..6.lua files into the new
    -- slug-based layout. Idempotent; harmless after the first run.
    Save.migrate_legacy()

    mgr = ScreenManager.new()
    mgr:register("home", Home.new(home_actions()))
    mgr:register("pause_modal", PauseModal.new(pause_actions()))
    mgr:register("settings", Settings.new({ back = function() mgr:set_current("home") end }))
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
        -- Track real seconds spent playing this mission with the sim ticking
        -- (matches PRD's "Played" column on the Archive). Paused / menu time
        -- doesn't count.
        mission_elapsed = mission_elapsed + dt
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
    -- Snapshot before dispatching to mgr: a menu key (e.g. Enter on the
    -- Charter button) flips in_game to true mid-call, but the SAME keystroke
    -- must not then re-fire as in-game input.
    local was_in_game = in_game_active()
    mgr:keypressed(key)
    if not was_in_game then return end

    -- Esc in-game opens the Pause modal. Once it's pushed, the next
    -- keypressed (incl. another Esc) routes to the modal, not here.
    if key == "escape" then
        mgr:push_modal("pause_modal")
        drag_start = nil -- cancel any in-progress drag on pause
        return
    end

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
        if current_slug then
            persist()
            flash("Saved")
        end
    elseif key == "f9" then
        if current_slug then
            local loaded = Save.load(current_slug)
            if loaded then
                world = loaded
                wire_world(world)
                flash("Loaded")
            else
                flash("No save")
            end
        end
    end
end

-- Begin a road/zone drag: anchor on the tile under the cursor (in tile coords,
-- so panning mid-drag doesn't move the anchor). Bulldoze isn't a drag tool.
-- The snapshot of in_game_active BEFORE dispatching to mgr is what gates the
-- in-game branch -- a Charter button click transitions to in_game during the
-- mgr call, but we must not then re-fire the SAME click as a zoning action.
function love.mousepressed(x, y, button)
    local was_in_game = in_game_active()
    mgr:mousepressed(x, y, button)
    if not was_in_game then return end
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
    local was_in_game = in_game_active()
    mgr:mousereleased(x, y, button)
    if not was_in_game then return end
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
-- Text input routes to menu screens (mission-name rename on the charter).
-- Discarded when nothing is up; in-game has no text-field UI.
function love.textinput(text)
    mgr:textinput(text)
end

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
