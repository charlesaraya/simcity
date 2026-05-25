-- src/ui/hud.lua
-- The debug heads-up display. Reads world state (never writes) and draws the
-- stats overlay. Kept in its own module from the start because UI tends to grow
-- and tangle with everything if you let it.
--
-- main passes in transient view state (current tool, speed) via opts, since
-- those live in the input layer, not the world.

local World = require("src.world.world")
local Clock = require("src.systems.clock")
local Economy = require("src.systems.economy")
local Format = require("src.ui.format")
local C = require("src.world.constants")

local Hud = {}

local PANEL_X = 16
local PANEL_W = 250 -- right edge for right-aligned amounts
local ROW_H = 22

local function money(n) return "$" .. Format.commas(n) end

-- A budget row: label indented on the left, value right-aligned to the panel.
local function budget_row(label, value, y)
    love.graphics.print(label, PANEL_X + 16, y)
    local font = love.graphics.getFont()
    love.graphics.print(value, PANEL_X + PANEL_W - font:getWidth(value), y)
end

local TOOL_NAME = {
    [C.TOOL.BULLDOZE] = "Bulldoze",
    [C.TOOL.ZONE_RES] = "Residential",
    [C.TOOL.ZONE_COM] = "Commercial",
    [C.TOOL.ZONE_IND] = "Industrial",
    [C.TOOL.ROAD]     = "Road",
}

local function speed_name(speed)
    if speed == C.SPEED.PAUSED then return "Paused" end
    if speed == C.SPEED.FAST then return "Fast" end
    return "Normal"
end

function Hud.draw(world, opts)
    love.graphics.setColor(1, 1, 1)
    local year, month = Clock.date(world)
    local res_n = World.count_buildings(world, C.ZONE.RESIDENTIAL, C.BUILD.COMPLETE)
    local com_n = World.count_buildings(world, C.ZONE.COMMERCIAL, C.BUILD.COMPLETE)
    local ind_n = World.count_buildings(world, C.ZONE.INDUSTRIAL, C.BUILD.COMPLETE)

    love.graphics.print("Slow Grid - Phase 3", 16, 16)
    love.graphics.print(("Date %04d-%02d   Speed: %s   FPS %d")
        :format(year, month, speed_name(opts.speed), love.timer.getFPS()), 16, 38)
    love.graphics.print(("Pop %d    R %d    C %d    I %d")
        :format(World.population(world), res_n, com_n, ind_n), 16, 60)
    love.graphics.print(("Demand   R %+.2f    C %+.2f    I %+.2f")
        :format(world.demand.residential, world.demand.commercial, world.demand.industrial), 16, 82)
    love.graphics.print(("Tool: %s"):format(TOOL_NAME[opts.tool]), 16, 104)

    if opts.status then
        love.graphics.setColor(C.COLOR.HIGHLIGHT)
        love.graphics.print(opts.status, 230, 16)
        love.graphics.setColor(1, 1, 1)
    end

    -- Monthly budget panel, bottom-left above the key hint.
    local b = Economy.budget(world)
    local top = love.graphics.getHeight() - 28 - 7 * ROW_H
    love.graphics.print("Monthly Budget", PANEL_X, top)
    love.graphics.line(PANEL_X, top + ROW_H, PANEL_X + PANEL_W, top + ROW_H)
    budget_row("Current Balance", money(world.treasury), top + ROW_H + 4)
    budget_row("Monthly Income", money(b.income), top + 2 * ROW_H + 4)
    budget_row("Monthly Expense", "(" .. money(b.expense) .. ")", top + 3 * ROW_H + 4)
    love.graphics.line(PANEL_X, top + 4 * ROW_H + 6, PANEL_X + PANEL_W, top + 4 * ROW_H + 6)
    budget_row("Month End Cash", money(world.treasury + b.net), top + 5 * ROW_H + 8)

    love.graphics.print(
        "[1]Bulldoze [2]Res [3]Com [4]Ind [5]Road  |  hold-click paint  |  space pause  +/- speed  |  F5 save  F9 load  |  WASD/scroll camera",
        16, love.graphics.getHeight() - 28)
end

return Hud
