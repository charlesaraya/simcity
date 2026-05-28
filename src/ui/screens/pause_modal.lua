-- src/ui/screens/pause_modal.lua
-- In-game overlay opened by Esc. The iso world stays visible underneath
-- (main draws the world first, then mgr:draw overlays this on top — and the
-- sim-tick gate, driven by mgr:should_tick, halts time while we're up).
--
-- Same structural shape as Home — selected/options/actions, keyboard +
-- mouse — but Esc means RESUME here, not end_transmission. The two screens
-- share enough to invite a MenuList widget, but a third instance (step 6's
-- New Mission is a FORM, not a list, and step 9's Mission Control is more
-- complex) hasn't appeared yet, so we keep both concrete for now and revisit.
--
-- Actions are injected: main.lua passes closures that pop the modal, save
-- and load through the persistence layer, return to Home, or quit.

local PauseModal   = {}
PauseModal.__index = PauseModal

local START_Y = 240
local ROW_H   = 44

local OPTIONS = {
    { key = "resume",            label = "Resume Operation" },
    { key = "save_to_archive",   label = "Save to Archive" },
    { key = "load_from_archive", label = "Load from Archive" },
    { key = "mission_control",   label = "Mission Control" },
    { key = "end_transmission",  label = "End Transmission" },
}

function PauseModal.new(actions)
    local self = setmetatable({}, PauseModal)
    self.options = OPTIONS
    self.actions = actions or {}
    self.selected = 1
    return self
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function fire(self, key)
    local fn = self.actions[key]
    if fn then fn() end
end

-- KEYBOARD ------------------------------------------------------------------

function PauseModal:keypressed(key)
    if key == "down" then
        self.selected = clamp(self.selected + 1, 1, #self.options)
    elseif key == "up" then
        self.selected = clamp(self.selected - 1, 1, #self.options)
    elseif key == "return" or key == "kpenter" then
        fire(self, self.options[self.selected].key)
    elseif key == "escape" then
        -- The distinguishing rule vs Home: Esc on a modal CLOSES the modal,
        -- i.e. fires the resume action. The action closure in main pops the
        -- modal off the stack; the sim-tick gate releases on the next frame.
        fire(self, "resume")
    end
end

-- GEOMETRY (pure, shared by hit-test and draw) ------------------------------

function PauseModal:row_center(i)
    return 0, START_Y + (i - 1) * ROW_H + ROW_H * 0.5
end

function PauseModal:row_at(_x, y)
    if y < START_Y then return nil end
    local i = math.floor((y - START_Y) / ROW_H) + 1
    if i < 1 or i > #self.options then return nil end
    return i
end

-- MOUSE ---------------------------------------------------------------------

function PauseModal:mousemoved(x, y)
    local i = self:row_at(x, y)
    if i then self.selected = i end
end

function PauseModal:mousepressed(x, y, button)
    if button ~= 1 then return end
    local i = self:row_at(x, y)
    if not i then return end
    self.selected = i
    fire(self, self.options[i].key)
end

-- DRAW (love-only; run-verified) --------------------------------------------
-- A translucent umber backdrop covers the full window so the iso world tints
-- darker but stays legible; the modal frame and options sit centered on top.
-- "MISSION PAUSED" labels the state plainly so the modal is unambiguous even
-- on first encounter.

local Theme = require("src.ui.theme")

local TITLE        = "MISSION PAUSED"
local TITLE_Y      = 160
local BACKDROP_A   = 0.78 -- alpha of the umber tint over the iso world

function PauseModal:draw()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()

    -- Translucent backdrop. Uses the C.UI.bg umber so the modal sits in the
    -- same visual register as the menu screens, just over the running world.
    local bg = Theme.color("bg")
    love.graphics.setColor(bg[1], bg[2], bg[3], BACKDROP_A)
    love.graphics.rectangle("fill", 0, 0, w, h)

    -- Title (slab serif display, bone)
    love.graphics.setFont(Theme.font("display"))
    love.graphics.setColor(Theme.color("fg"))
    local tw = love.graphics.getFont():getWidth(TITLE)
    love.graphics.print(TITLE, (w - tw) * 0.5, TITLE_Y)

    -- Options
    love.graphics.setFont(Theme.font("heading"))
    local font = love.graphics.getFont()
    for i, opt in ipairs(self.options) do
        local _, cy = self:row_center(i)
        local y = cy - font:getHeight() * 0.5
        if i == self.selected then
            love.graphics.setColor(Theme.color("accent"))
            local label = "› " .. opt.label
            local lw = font:getWidth(label)
            love.graphics.print(label, (w - lw) * 0.5, y)
        else
            love.graphics.setColor(Theme.color("fg"))
            local lw = font:getWidth(opt.label)
            love.graphics.print(opt.label, (w - lw) * 0.5, y)
        end
    end
end

return PauseModal
