-- src/ui/screens/home.lua
-- The top-level menu surface. Five options in the documented order:
-- Continue Operations / New Mission / Load from Archive / Operator Settings /
-- End Transmission. Actions are INJECTED at construction so the screen has no
-- coupling to the manager; main.lua passes in closures.
--
-- Selection nav:
--   ↑/↓   move selection (clamped — no wrap)
--   Enter / kpenter  fire the action for the selected option
--   Esc   fire end_transmission (from the root menu, back-out IS quit)
--
-- Direct hotkeys (any focus): C continue · N new mission · L load archive ·
--   S settings · Q quit. Each unselected row displays its letter on the right;
--   the focused row shows ↵ instead.
--
-- Mouse:
--   hover  sets selected to the row under the cursor
--   click  selects the row AND fires its action (left button only)

local Home   = {}
Home.__index = Home

-- Layout: the menu sits inside an outlined panel sized to its content (height
-- == N rows + padding) and roughly half the window wide, centered horizontally
-- in the draw. The y-anchored constants stay module-level so the pure
-- row_at / row_center hit-test stays headless-testable (no love calls).
local PANEL_TOP_Y = 140
local PANEL_PAD   = 24
local ROW_H       = 60
local ROWS_TOP_Y  = PANEL_TOP_Y + PANEL_PAD

local OPTIONS = {
    { key = "continue",         label = "CONTINUE OPERATIONS", hotkey = "c" },
    { key = "new_mission",      label = "NEW MISSION",         hotkey = "n" },
    { key = "archive",          label = "LOAD FROM ARCHIVE",   hotkey = "l" },
    { key = "settings",         label = "OPERATOR SETTINGS",   hotkey = "s" },
    { key = "end_transmission", label = "END TRANSMISSION",    hotkey = "q" },
}

-- Hotkey -> option index, derived once from OPTIONS so keypressed is O(1).
local HOTKEY_TO_INDEX = {}
for i, opt in ipairs(OPTIONS) do HOTKEY_TO_INDEX[opt.hotkey] = i end

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
    else
        -- Direct hotkey: select that row AND fire its action. Selecting first
        -- keeps the visual in sync so a returning user (or a future "are you
        -- sure?" prompt) sees what was picked.
        local i = HOTKEY_TO_INDEX[key]
        if i then
            self.selected = i
            fire(self, self.options[i].key)
        end
    end
end

-- GEOMETRY (pure, shared by hit-test and draw) ------------------------------

-- Center coordinate of row i. X is nominal (0) — the row spans the panel's
-- full inner width; draw centers content on the actual window.
function Home:row_center(i)
    return 0, ROWS_TOP_Y + (i - 1) * ROW_H + ROW_H * 0.5
end

-- Hit-test: which row index covers screen-y, or nil if y is above the first
-- row or below the last. X is ignored (rows span the panel horizontally).
function Home:row_at(_x, y)
    if y < ROWS_TOP_Y then return nil end
    local i = math.floor((y - ROWS_TOP_Y) / ROW_H) + 1
    if i < 1 or i > #self.options then return nil end
    return i
end

-- MOUSE ---------------------------------------------------------------------

function Home:mousemoved(x, y)
    local i = self:row_at(x, y)
    if i then self.selected = i end
end

function Home:mousepressed(x, y, button)
    if button ~= 1 then return end
    local i = self:row_at(x, y)
    if not i then return end
    self.selected = i
    fire(self, self.options[i].key)
end

-- DRAW (love-only; run-verified) --------------------------------------------
-- Outlined panel sized to content: half the window wide, centered, height
-- equal to N rows + padding. Each row is a full-width-inside-the-panel
-- rectangle. The selected row is amber-filled with horizontal scanlines and
-- reverses to bg-colored text + leading ▶ marker. Unselected rows are
-- outlined with bone label only — hotkeys still work silently (C/N/L/S/Q).

local Theme   = require("src.ui.theme")
local Widgets = require("src.ui.widgets")

local MARKER = "▶"

function Home:draw()
    local W = love.graphics.getWidth()

    -- Panel sized to content + roughly half the window wide.
    local pw = W * 0.5
    local px = (W - pw) * 0.5
    local py = PANEL_TOP_Y
    local ph = #self.options * ROW_H + PANEL_PAD * 2
    Widgets.frame(px, py, pw, ph)

    -- Row geometry inside the panel.
    local row_x = px + PANEL_PAD
    local row_w = pw - PANEL_PAD * 2
    local row_inner_h = ROW_H - 8 -- visual gap between rows

    love.graphics.setFont(Theme.font("heading"))
    local font = love.graphics.getFont()

    for i, opt in ipairs(self.options) do
        local ry = ROWS_TOP_Y + (i - 1) * ROW_H + 4 -- top edge of drawn rect
        local text_y = ry + (row_inner_h - font:getHeight()) * 0.5

        if i == self.selected then
            Widgets.scanline_fill(row_x, ry, row_w, row_inner_h)
            love.graphics.setColor(Theme.color("bg"))
            love.graphics.print(MARKER, row_x + 20, text_y)
            love.graphics.print(opt.label, row_x + 64, text_y)
        else
            Widgets.outline(row_x, ry, row_w, row_inner_h)
            love.graphics.setColor(Theme.color("fg"))
            love.graphics.print(opt.label, row_x + 64, text_y)
        end
    end
end

return Home
