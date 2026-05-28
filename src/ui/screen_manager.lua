-- src/ui/screen_manager.lua
-- The screen state machine. Owns which menu screen is current, the modal stack
-- (Pause modal pushes here from in-game), an `in_game` flag for the running
-- mission, and the dispatch order for love callbacks. Pure module, headless-
-- testable: it never touches love itself; screens are just tables of callbacks.
--
-- Sim-tick gate: `should_tick()` is true iff in_game AND the modal stack is
-- empty — main reads this each frame to decide whether to call Runner.update.
-- Any open modal (or being on a menu) pauses the sim.
--
-- Dispatch: input/update routes to the TOP active surface only — the topmost
-- modal if any, else the current screen, else a no-op. Draw is layered: the
-- current screen draws first, then every modal in stack order, so modals
-- visibly overlay the screen they were opened from. The iso world (when
-- in_game and no current screen) is drawn by main, NOT by the manager —
-- modals layer over that too because main draws iso first, then calls
-- manager:draw().

local ScreenManager = {}
ScreenManager.__index = ScreenManager

function ScreenManager.new()
    local self = setmetatable({}, ScreenManager)
    self._screens = {}
    self._current = nil
    self._stack = {}
    self.in_game = false
    return self
end

-- REGISTRATION ---------------------------------------------------------------

-- Bind an id to a screen handler table. The screen may define any of:
-- update(self, dt), draw(self), keypressed(self, key), mousepressed(self, x, y, b),
-- mousereleased(self, x, y, b), wheelmoved(self, dx, dy). All are optional.
-- Registering an id twice replaces the previous handler.
function ScreenManager:register(id, screen)
    self._screens[id] = screen
end

local function require_registered(self, id)
    if not self._screens[id] then
        error(("ScreenManager: id %q is not registered"):format(tostring(id)), 3)
    end
end

-- CURRENT SCREEN -------------------------------------------------------------

function ScreenManager:set_current(id)
    require_registered(self, id)
    self._current = id
end

function ScreenManager:current_id()
    return self._current
end

-- MODAL STACK ----------------------------------------------------------------

function ScreenManager:push_modal(id)
    require_registered(self, id)
    self._stack[#self._stack + 1] = id
end

function ScreenManager:pop_modal()
    -- No-op on an empty stack: the Pause-modal close path is naturally idempotent.
    if #self._stack == 0 then return end
    self._stack[#self._stack] = nil
end

function ScreenManager:modal_count()
    return #self._stack
end

-- SIM-TICK GATE --------------------------------------------------------------

function ScreenManager:should_tick()
    return self.in_game and #self._stack == 0
end

-- DISPATCH HELPERS -----------------------------------------------------------

-- The active surface for input/update: topmost modal handler if any, else the
-- current screen handler, else nil.
local function active(self)
    if #self._stack > 0 then
        return self._screens[self._stack[#self._stack]]
    elseif self._current then
        return self._screens[self._current]
    end
    return nil
end

-- Invoke method `name` on `screen` with method-call semantics, but only if the
-- screen defines that callback. Screens that omit a callback are tolerated.
local function call(screen, name, ...)
    local fn = screen and screen[name]
    if fn then fn(screen, ...) end
end

-- CALLBACK DISPATCH (top surface only) --------------------------------------

function ScreenManager:update(dt)
    call(active(self), "update", dt)
end

function ScreenManager:keypressed(key)
    call(active(self), "keypressed", key)
end

function ScreenManager:mousepressed(x, y, button)
    call(active(self), "mousepressed", x, y, button)
end

function ScreenManager:mousereleased(x, y, button)
    call(active(self), "mousereleased", x, y, button)
end

function ScreenManager:wheelmoved(dx, dy)
    call(active(self), "wheelmoved", dx, dy)
end

-- DRAW (layered: current first, then every modal in stack order) ------------

function ScreenManager:draw()
    if self._current then
        call(self._screens[self._current], "draw")
    end
    for i = 1, #self._stack do
        call(self._screens[self._stack[i]], "draw")
    end
end

return ScreenManager
