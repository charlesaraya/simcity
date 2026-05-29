-- src/ui/screens/mission_control.lua
-- Crew dashboard reached via Pause modal's "Mission Control". Read-only in
-- 4c-1: snapshots the current mission identity + crew at construction so the
-- screen is pure (no live world reads from the draw). Two keyboard actions:
-- Esc/B back to the Pause modal; H to Return to Home (abandoning the active
-- mission to the title menu).
--
-- Phase 5+ will add per-specialist mechanical effects, status changes
-- (injured/transit), and assignment UI. The data shape (world.crew on the
-- live world) is forward-compatible -- the screen just snapshots it.

local MissionControl   = {}
MissionControl.__index = MissionControl

function MissionControl.new(opts)
    opts = opts or {}
    local self = setmetatable({}, MissionControl)
    self.mission = opts.mission or {}
    self.crew = opts.crew or {}
    self.cycle = opts.cycle or 0
    self.actions = opts.actions or {}
    return self
end

local function fire(self, name)
    local fn = self.actions[name]
    if fn then fn() end
end

-- KEYBOARD ------------------------------------------------------------------

function MissionControl:keypressed(key)
    if key == "escape" or key == "b" then
        fire(self, "back")
    elseif key == "h" then
        fire(self, "return_to_home")
    end
    -- Other keys are a no-op: the screen is read-only in 4c-1.
end

-- DRAW (love-only; run-verified) --------------------------------------------
-- Title strip; mission identity strip (name + cycle + difficulty); crew table
-- panel with columns # / ROLE / NAME / TRAITS / STATUS; bottom hint line.
-- No interactive widgets in 4c-1.

local Theme        = require("src.ui.theme")
local Widgets      = require("src.ui.widgets")
local C            = require("src.world.constants")
local difficulties = require("src.ui.content.difficulties")

local TITLE         = "MISSION CONTROL"
local SUBTITLE      = "-- COMMAND DECK --"
local TITLE_X       = 56
local TITLE_Y       = 36
local IDENTITY_TOP  = 100
local IDENTITY_H    = 64
local PANEL_TOP_Y   = 184
local PANEL_PAD     = 24
local HEADER_H      = 34
local ROW_H         = 36
local VISIBLE_ROWS  = 5

local function difficulty_label(key)
    for _, d in ipairs(difficulties) do
        if d.key == key then return string.upper(d.label) end
    end
    return "—"
end

-- Column ratios within the table row width.
local COLS = {
    NUM    = 24,
    ROLE   = 64,
    NAME   = 0.36,
    TRAITS = 0.62,
    STATUS = 0.88,
}

local function col_x(row_x, row_w, key)
    local v = COLS[key]
    if v < 1 then return row_x + math.floor(row_w * v) end
    return row_x + v
end

function MissionControl:draw()
    local W, H = love.graphics.getWidth(), love.graphics.getHeight()

    -- Backdrop: solid umber filling the entire viewport so the iso world +
    -- HUD don't bleed through. Mission Control is its own surface, not an
    -- overlay onto the running game (despite riding on the modal stack to
    -- pause the sim).
    love.graphics.setColor(Theme.color("bg"))
    love.graphics.rectangle("fill", 0, 0, W, H)

    -- Panel geometry first so title can anchor to the panel's left edge.
    local pw = math.min(W * 0.86, 1100)
    local px = (W - pw) * 0.5

    -- Title strip — left-aligned to the panel (shared positioning rule).
    love.graphics.setFont(Theme.font("heading"))
    love.graphics.setColor(Theme.color("amber"))
    love.graphics.print("▶", px, TITLE_Y)
    love.graphics.setColor(Theme.color("fg"))
    love.graphics.print(TITLE, px + 24, TITLE_Y)
    love.graphics.setFont(Theme.font("meta"))
    love.graphics.setColor(Theme.color("dim_fg"))
    love.graphics.print(SUBTITLE, px + 24, TITLE_Y + 22)

    -- Mission identity strip: small outlined panel with name + cycle + difficulty.
    love.graphics.setColor(Theme.color("bg"))
    love.graphics.rectangle("fill", px, IDENTITY_TOP, pw, IDENTITY_H)
    Widgets.outline(px, IDENTITY_TOP, pw, IDENTITY_H)
    love.graphics.setFont(Theme.font("meta"))
    love.graphics.setColor(Theme.color("dim_fg"))
    love.graphics.print("MISSION",    px + 24,  IDENTITY_TOP + 12)
    love.graphics.print("CYCLE",      px + 360, IDENTITY_TOP + 12)
    love.graphics.print("DIFFICULTY", px + 480, IDENTITY_TOP + 12)
    love.graphics.setFont(Theme.font("body"))
    love.graphics.setColor(Theme.color("fg"))
    love.graphics.print(string.upper(self.mission.name or "UNTITLED"), px + 24,  IDENTITY_TOP + 34)
    love.graphics.print(("%04d"):format(self.cycle),                   px + 360, IDENTITY_TOP + 34)
    love.graphics.print(difficulty_label(self.mission.difficulty),     px + 480, IDENTITY_TOP + 34)

    -- Crew table panel.
    local ph = PANEL_PAD * 2 + HEADER_H + VISIBLE_ROWS * ROW_H
    local py = PANEL_TOP_Y
    Widgets.frame(px, py, pw, ph)

    local row_x = px + PANEL_PAD
    local row_w = pw - PANEL_PAD * 2

    -- Header row.
    love.graphics.setFont(Theme.font("meta"))
    love.graphics.setColor(Theme.color("dim_fg"))
    local header_y = py + PANEL_PAD + 6
    love.graphics.print("#",       row_x + COLS.NUM,                 header_y)
    love.graphics.print("ROLE",    row_x + COLS.ROLE,                header_y)
    love.graphics.print("NAME",    col_x(row_x, row_w, "NAME"),      header_y)
    love.graphics.print("TRAITS",  col_x(row_x, row_w, "TRAITS"),    header_y)
    love.graphics.print("STATUS",  col_x(row_x, row_w, "STATUS"),    header_y)
    Widgets.dashed_hr(row_x, py + PANEL_PAD + HEADER_H - 2, row_x + row_w)

    -- Crew rows (up to VISIBLE_ROWS — 4c-1 caps team_size at 5 anyway).
    love.graphics.setFont(Theme.font("body"))
    local font = love.graphics.getFont()
    local rows_top = py + PANEL_PAD + HEADER_H
    for i, member in ipairs(self.crew) do
        if i > VISIBLE_ROWS then break end
        local ry = rows_top + (i - 1) * ROW_H + 4
        local row_inner_h = ROW_H - 8
        local text_y = ry + (row_inner_h - font:getHeight()) * 0.5
        love.graphics.setColor(Theme.color("fg"))
        love.graphics.print(("%02d"):format(i),          row_x + COLS.NUM,             text_y)
        love.graphics.print(string.upper(C.ROLE_LABEL[member.role] or "—"),
                                                         row_x + COLS.ROLE,            text_y)
        love.graphics.print(member.name or "—",          col_x(row_x, row_w, "NAME"),  text_y)
        love.graphics.print(member.traits and member.traits[1] or "—",
                                                         col_x(row_x, row_w, "TRAITS"), text_y)
        -- Status in green when ACTIVE; dim otherwise (4c-1 only ships ACTIVE).
        if member.status == C.STATUS.ACTIVE then
            love.graphics.setColor(Theme.color("amber"))
        else
            love.graphics.setColor(Theme.color("dim_fg"))
        end
        love.graphics.print(string.upper(member.status or "—"),
            col_x(row_x, row_w, "STATUS"), text_y)
        if i < math.min(#self.crew, VISIBLE_ROWS) then
            love.graphics.setColor(Theme.color("dim_fg"))
            Widgets.dashed_hr(row_x, ry + row_inner_h + 3, row_x + row_w)
        end
    end

    -- Hint strip.
    love.graphics.setFont(Theme.font("meta"))
    love.graphics.setColor(Theme.color("dim_fg"))
    local hint = "ESC / B BACK   H RETURN TO HOME"
    local hw = love.graphics.getFont():getWidth(hint)
    love.graphics.print(hint, (W - hw) * 0.5, py + ph + 28)
end

return MissionControl
