-- src/ui/screens/home.lua
-- The top-level menu surface. Five options in the documented order:
-- Continue Operations / New Mission / Load from Archive / Operator Settings /
-- End Transmission. Actions are INJECTED at construction so the screen has no
-- coupling to the manager; main.lua passes in closures that start a mission,
-- load a save, quit, etc. Everything except draw is pure and headless-testable.
--
-- Selection nav:
--   ↑/↓   move selection (clamped — no wrap; see review-before-commit notes)
--   Enter / kpenter  fire the action for the selected option
--   Esc   fire end_transmission (from the root menu, back-out IS quit)
--
-- Mouse:
--   hover  sets selected to the row under the cursor
--   click  selects the row AND fires its action (left button only)

local Home    = {}
Home.__index  = Home

-- Layout constants. Kept module-local so the pure hit-test (row_at) and the
-- love-side draw (step 3 draw is a stub — wired in the run-verify pass) share
-- one source of truth.
local START_Y = 240
local ROW_H   = 44

local OPTIONS = {
    { key = "continue",         label = "Continue Operations" },
    { key = "new_mission",      label = "New Mission" },
    { key = "archive",          label = "Load from Archive" },
    { key = "settings",         label = "Operator Settings" },
    { key = "end_transmission", label = "End Transmission" },
}

function Home.new(actions)
    local self = setmetatable({}, Home)
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

function Home:keypressed(key)
    if key == "down" then
        self.selected = clamp(self.selected + 1, 1, #self.options)
    elseif key == "up" then
        self.selected = clamp(self.selected - 1, 1, #self.options)
    elseif key == "return" or key == "kpenter" then
        fire(self, self.options[self.selected].key)
    elseif key == "escape" then
        fire(self, "end_transmission")
    end
end

-- GEOMETRY (pure, shared by hit-test and draw) ------------------------------

-- Center coordinate of row i. X is nominal (0) — the row spans the menu's
-- full horizontal extent for hit-testing purposes in step 3; draw centers on
-- the window width at love-time.
function Home:row_center(i)
    return 0, START_Y + (i - 1) * ROW_H + ROW_H * 0.5
end

-- Hit-test: which row index covers screen-y, or nil if y is above the first
-- row or below the last. X is ignored (rows span the menu horizontally).
function Home:row_at(_x, y)
    if y < START_Y then return nil end
    local i = math.floor((y - START_Y) / ROW_H) + 1
    if i < 1 or i > #self.options then return nil end
    return i
end

-- MOUSE ---------------------------------------------------------------------

function Home:mousemoved(x, y)
    local i = self:row_at(x, y)
    if i then self.selected = i end
end

function Home:mousepressed(x, y, button)
    if button ~= 1 then return end -- left only
    local i = self:row_at(x, y)
    if not i then return end
    self.selected = i
    fire(self, self.options[i].key)
end

-- DRAW --------------------------------------------
-- Minimal first pass: display title, dim subtitle,
-- then the five options. Selected row is rendered in the ink-red accent with
-- a leading marker. Centered on the current window width.

local Theme      = require("src.ui.theme")

local TITLE      = "SLOW GRID"
local SUBTITLE   = "GROUND CONTROL · MISSION SHELL"
local TITLE_Y    = 120
local SUBTITLE_Y = 180

function Home:draw()
    local w = love.graphics.getWidth()

    -- Title (slab serif display)
    love.graphics.setFont(Theme.font("display"))
    love.graphics.setColor(Theme.color("fg"))
    local tw = love.graphics.getFont():getWidth(TITLE)
    love.graphics.print(TITLE, (w - tw) * 0.5, TITLE_Y)

    -- Subtitle (mono meta, dim)
    love.graphics.setFont(Theme.font("meta"))
    love.graphics.setColor(Theme.color("dim_fg"))
    local sw = love.graphics.getFont():getWidth(SUBTITLE)
    love.graphics.print(SUBTITLE, (w - sw) * 0.5, SUBTITLE_Y)

    -- Options (slab serif heading). The selected row gets the accent and a
    -- leading marker; siblings render in bone fg.
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

return Home
