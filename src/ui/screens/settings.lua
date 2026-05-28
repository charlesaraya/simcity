-- src/ui/screens/settings.lua
-- Operator Settings — stub in 4c-1. The screen exists so Home's "Operator
-- Settings" navigation completes; real content (window mode, audio levels
-- after 4c-3, key remap, save-slot management) lands as later passes.
--
-- Only behavior: Esc / B fires back. No focus model, no other inputs.

local Settings   = {}
Settings.__index = Settings

function Settings.new(actions)
    local self = setmetatable({}, Settings)
    self.actions = actions or {}
    return self
end

local function fire_back(self)
    if self.actions.back then self.actions.back() end
end

function Settings:keypressed(key)
    if key == "escape" or key == "b" then fire_back(self) end
end

-- DRAW (love-only; run-verified) --------------------------------------------
-- Title strip + dim "coming soon" placeholder inside a framed panel.

local Theme   = require("src.ui.theme")
local Widgets = require("src.ui.widgets")

local TITLE       = "OPERATOR SETTINGS"
local SUBTITLE    = "-- INSTRUMENT CALIBRATION --"
local PLACEHOLDER = "-- AWAITING SUBSEQUENT UPDATE --"
local TITLE_X     = 56
local TITLE_Y     = 36
local PANEL_TOP_Y = 140
local PANEL_PAD   = 24
local PANEL_H     = 280

function Settings:draw()
    local W = love.graphics.getWidth()

    -- Title strip
    love.graphics.setFont(Theme.font("heading"))
    love.graphics.setColor(Theme.color("amber"))
    love.graphics.print("▶", TITLE_X, TITLE_Y)
    love.graphics.setColor(Theme.color("fg"))
    love.graphics.print(TITLE, TITLE_X + 24, TITLE_Y)
    love.graphics.setFont(Theme.font("meta"))
    love.graphics.setColor(Theme.color("dim_fg"))
    love.graphics.print(SUBTITLE, TITLE_X + 24, TITLE_Y + 22)

    -- Framed panel with the placeholder line centered.
    local pw = math.min(W * 0.6, 720)
    local px = (W - pw) * 0.5
    local py = PANEL_TOP_Y
    Widgets.frame(px, py, pw, PANEL_H)

    love.graphics.setFont(Theme.font("body"))
    local font = love.graphics.getFont()
    love.graphics.setColor(Theme.color("dim_fg"))
    local plw = font:getWidth(PLACEHOLDER)
    love.graphics.print(PLACEHOLDER,
        px + (pw - plw) * 0.5,
        py + (PANEL_H - font:getHeight()) * 0.5)

    -- Hint strip beneath the panel.
    love.graphics.setFont(Theme.font("meta"))
    love.graphics.setColor(Theme.color("dim_fg"))
    local hint = "ESC / B BACK"
    local hw = love.graphics.getFont():getWidth(hint)
    love.graphics.print(hint, (W - hw) * 0.5, py + PANEL_H + 28)
end

return Settings
