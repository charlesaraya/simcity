-- src/ui/screens/confirm_modal.lua
-- Generic 3-button confirmation dialog (Yes / No / Cancel). Used in 4c-2 for
-- save-before-abandoning prompts: End Transmission, Mission Control's Return
-- to Home. Actions are injected at construction so the screen has no coupling
-- to persistence or the manager.
--
-- Keyboard:
--   ↑/↓ or ←/→ move selection between the three buttons
--   Enter / kpenter fires the selected action
--   Esc fires `cancel`
--   Y / N / C hotkeys fire yes / no / cancel from any focus
--
-- Mouse:
--   hover sets selected to the button under the cursor
--   left click selects AND fires the action

local ConfirmModal   = {}
ConfirmModal.__index = ConfirmModal

local BUTTON_KEYS = { "yes", "no", "cancel" }
local DEFAULT_LABELS = {
    yes    = "SAVE & PROCEED",
    no     = "DISCARD",
    cancel = "CANCEL",
}

function ConfirmModal.new(opts)
    opts = opts or {}
    local self = setmetatable({}, ConfirmModal)
    self.title = opts.title or "Confirm"
    self.body  = opts.body  or ""
    self.actions = opts.actions or {}
    self.labels = opts.labels or DEFAULT_LABELS
    self.selected = 1 -- 1 = yes (the affirmative default)
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

function ConfirmModal:keypressed(key)
    if key == "escape" then return fire(self, "cancel") end
    if key == "y" then return fire(self, "yes") end
    if key == "n" then return fire(self, "no") end
    if key == "c" then return fire(self, "cancel") end
    if key == "left" or key == "up" then
        self.selected = clamp(self.selected - 1, 1, #BUTTON_KEYS)
    elseif key == "right" or key == "down" then
        self.selected = clamp(self.selected + 1, 1, #BUTTON_KEYS)
    elseif key == "return" or key == "kpenter" then
        fire(self, BUTTON_KEYS[self.selected])
    end
end

-- GEOMETRY (pure) -----------------------------------------------------------
-- Buttons share a row near the bottom of the modal. row_center returns the
-- center y for the row (constant across i, since they're side-by-side); the
-- x distinguishes which button — but since x isn't used by the hit-test below
-- in the same way as Home (where rows stack vertically), we return a nominal
-- (0, y) and the mouse uses row_at to convert pixel-x into a button index.

local BUTTON_ROW_Y = 380 -- screen-y center of the button row
local BUTTON_W     = 200
local BUTTON_H     = 36
local BUTTON_GAP   = 24

-- Compute the (x, y) center of button i. Uses love.graphics.getWidth when
-- available; falls back to 1280 (the default window width) in headless tests
-- so row_at + row_center stay round-trip consistent there too.
local function window_width()
    if love and love.graphics and love.graphics.getWidth then
        return love.graphics.getWidth()
    end
    return 1280
end

function ConfirmModal:row_center(i)
    local total_w = #BUTTON_KEYS * BUTTON_W + (#BUTTON_KEYS - 1) * BUTTON_GAP
    local left = (window_width() - total_w) * 0.5
    local bx = left + (i - 1) * (BUTTON_W + BUTTON_GAP)
    return bx + BUTTON_W * 0.5, BUTTON_ROW_Y
end

function ConfirmModal:row_at(x, y)
    local top = BUTTON_ROW_Y - BUTTON_H * 0.5
    if y < top or y > top + BUTTON_H then return nil end
    local total_w = #BUTTON_KEYS * BUTTON_W + (#BUTTON_KEYS - 1) * BUTTON_GAP
    local left = (window_width() - total_w) * 0.5
    if x < left or x > left + total_w then return nil end
    local stride = BUTTON_W + BUTTON_GAP
    local i = math.floor((x - left) / stride) + 1
    if i < 1 or i > #BUTTON_KEYS then return nil end
    return i
end

-- MOUSE ---------------------------------------------------------------------

function ConfirmModal:mousemoved(x, y)
    local i = self:row_at(x, y)
    if i then self.selected = i end
end

function ConfirmModal:mousepressed(x, y, button)
    if button ~= 1 then return end
    local i = self:row_at(x, y)
    if not i then return end
    self.selected = i
    fire(self, BUTTON_KEYS[i])
end

-- DRAW (love-only; run-verified) --------------------------------------------
-- Solid umber backdrop over whatever is underneath; outlined panel with the
-- title (heading), body (body), and three buttons in a row.

local Theme   = require("src.ui.theme")
local Widgets = require("src.ui.widgets")

local PANEL_W = 720
local PANEL_H = 280

function ConfirmModal:draw()
    local W, H = love.graphics.getWidth(), love.graphics.getHeight()

    -- Dark veil over the surface underneath.
    love.graphics.setColor(0, 0, 0, 0.78)
    love.graphics.rectangle("fill", 0, 0, W, H)

    -- Centered panel
    local px = (W - PANEL_W) * 0.5
    local py = (H - PANEL_H) * 0.5
    love.graphics.setColor(Theme.color("bg"))
    love.graphics.rectangle("fill", px, py, PANEL_W, PANEL_H)
    Widgets.frame(px, py, PANEL_W, PANEL_H)

    -- Title (heading, amber marker + bone text)
    love.graphics.setFont(Theme.font("heading"))
    love.graphics.setColor(Theme.color("amber"))
    love.graphics.print("▶", px + 32, py + 36)
    love.graphics.setColor(Theme.color("fg"))
    love.graphics.print(string.upper(self.title), px + 56, py + 36)

    -- Body (body font, dim)
    love.graphics.setFont(Theme.font("body"))
    love.graphics.setColor(Theme.color("dim_fg"))
    love.graphics.print(self.body, px + 32, py + 90)

    -- Buttons row
    local total_w = #BUTTON_KEYS * BUTTON_W + (#BUTTON_KEYS - 1) * BUTTON_GAP
    local left = (W - total_w) * 0.5
    local by = BUTTON_ROW_Y - BUTTON_H * 0.5
    love.graphics.setFont(Theme.font("body"))
    local font = love.graphics.getFont()
    for i, k in ipairs(BUTTON_KEYS) do
        local bx = left + (i - 1) * (BUTTON_W + BUTTON_GAP)
        if i == self.selected then
            Widgets.scanline_fill(bx + 1, by + 1, BUTTON_W - 2, BUTTON_H - 2)
        end
        Widgets.outline(bx, by, BUTTON_W, BUTTON_H)
        love.graphics.setColor(i == self.selected and Theme.color("bg") or Theme.color("fg"))
        local label = self.labels[k]
        local tw = font:getWidth(label)
        love.graphics.print(label, bx + (BUTTON_W - tw) * 0.5, by + (BUTTON_H - font:getHeight()) * 0.5)
    end

    -- Hint strip
    love.graphics.setFont(Theme.font("meta"))
    love.graphics.setColor(Theme.color("dim_fg"))
    local hint = "Y SAVE   N DISCARD   ESC / C CANCEL   ←→ SELECT   ENTER CONFIRM"
    local hw = love.graphics.getFont():getWidth(hint)
    love.graphics.print(hint, (W - hw) * 0.5, py + PANEL_H + 20)
end

return ConfirmModal
