-- src/ui/screens/pause_modal.lua
-- In-game overlay opened by Esc. The iso world stays visible behind a
-- translucent umber backdrop (main draws the world first, then mgr:draw
-- overlays this on top), and the sim-tick gate halts time while we're up.
--
-- Visual register matches Home: outlined panel sized to its rows, full-width
-- option rectangles, selected row scanline-amber with a leading ▶ marker,
-- unselected rows outlined.
--
-- Selection nav:
--   ↑/↓   move selection (clamped)
--   Enter / kpenter  fire the action for the selected option
--   Esc   fires RESUME (modal-close)
--
-- Direct hotkeys (any focus): R resume · S save · L load · M mission control ·
--   Q end transmission. Pressing one selects that row AND fires its action.

local PauseModal   = {}
PauseModal.__index = PauseModal

local PANEL_TOP_Y = 200
local PANEL_PAD   = 24
local ROW_H       = 60
local ROWS_TOP_Y  = PANEL_TOP_Y + PANEL_PAD

local OPTIONS = {
    { key = "resume",            label = "RESUME OPERATION",  hotkey = "r" },
    { key = "save_to_archive",   label = "SAVE TO ARCHIVE",   hotkey = "s" },
    { key = "load_from_archive", label = "LOAD FROM ARCHIVE", hotkey = "l" },
    { key = "mission_control",   label = "MISSION CONTROL",   hotkey = "m" },
    { key = "end_transmission",  label = "END TRANSMISSION",  hotkey = "q" },
}

local HOTKEY_TO_INDEX = {}
for i, opt in ipairs(OPTIONS) do HOTKEY_TO_INDEX[opt.hotkey] = i end

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
        -- Esc on a modal CLOSES the modal — fires resume regardless of focus.
        fire(self, "resume")
    else
        local i = HOTKEY_TO_INDEX[key]
        if i then
            self.selected = i
            fire(self, self.options[i].key)
        end
    end
end

-- GEOMETRY (pure, shared by hit-test and draw) ------------------------------

function PauseModal:row_center(i)
    return 0, ROWS_TOP_Y + (i - 1) * ROW_H + ROW_H * 0.5
end

function PauseModal:row_at(_x, y)
    if y < ROWS_TOP_Y then return nil end
    local i = math.floor((y - ROWS_TOP_Y) / ROW_H) + 1
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
-- Translucent umber backdrop over the iso world; "MISSION PAUSED" title above
-- the framed panel; then the option rows in the same language as Home.

local Theme   = require("src.ui.theme")
local Widgets = require("src.ui.widgets")

local TITLE      = "MISSION PAUSED"
local TITLE_Y    = 140
local BACKDROP_A = 0.85 -- near-opaque black veil over the running iso
local MARKER     = "▶"

function PauseModal:draw()
    local W, H = love.graphics.getWidth(), love.graphics.getHeight()

    -- Backdrop: a dark veil so the iso world dims well behind the modal but
    -- stays faintly visible (situational awareness without competing focus).
    love.graphics.setColor(0, 0, 0, BACKDROP_A)
    love.graphics.rectangle("fill", 0, 0, W, H)

    -- Title above the panel.
    love.graphics.setFont(Theme.font("display"))
    love.graphics.setColor(Theme.color("fg"))
    local font = love.graphics.getFont()
    local tw = font:getWidth(TITLE)
    love.graphics.print(TITLE, (W - tw) * 0.5, TITLE_Y)

    -- Solid umber panel (NOT translucent): fully blocks the iso below so the
    -- modal reads as its own surface. Frame outline drawn on top.
    local pw = W * 0.5
    local px = (W - pw) * 0.5
    local py = PANEL_TOP_Y
    local ph = #self.options * ROW_H + PANEL_PAD * 2
    love.graphics.setColor(Theme.color("bg"))
    love.graphics.rectangle("fill", px, py, pw, ph)
    Widgets.frame(px, py, pw, ph)

    -- Rows.
    local row_x = px + PANEL_PAD
    local row_w = pw - PANEL_PAD * 2
    local row_inner_h = ROW_H - 8

    love.graphics.setFont(Theme.font("heading"))
    font = love.graphics.getFont()

    for i, opt in ipairs(self.options) do
        local ry = ROWS_TOP_Y + (i - 1) * ROW_H + 4
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

return PauseModal
