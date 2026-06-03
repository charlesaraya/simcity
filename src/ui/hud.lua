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
local Power = require("src.systems.power")
local Goods = require("src.systems.goods")
local Format = require("src.ui.format")
local Theme = require("src.ui.theme")
local Widgets = require("src.ui.widgets")
local C = require("src.world.constants")

local Hud = {}

local PANEL_X = 16
local PANEL_W = 280
local ROW_H = 18

local function money(n) return "₡" .. Format.commas(n) end

-- A budget row.
local function budget_row(label, value, y)
    love.graphics.setFont(Theme.font("meta"))
    love.graphics.setColor(Theme.color("dim_fg"))
    love.graphics.print(string.upper(label), PANEL_X + 12, y)
    love.graphics.setFont(Theme.font("body"))
    love.graphics.setColor(Theme.color("fg"))
    local font = love.graphics.getFont()
    love.graphics.print(value, PANEL_X + PANEL_W - font:getWidth(value), y - 2)
end

local TOOL_NAME = {
    [C.TOOL.BULLDOZE]   = "BULLDOZE",
    [C.TOOL.ZONE_RES]   = "RESIDENTIAL",
    [C.TOOL.ZONE_COM]   = "COMMERCIAL",
    [C.TOOL.ZONE_IND]   = "INDUSTRIAL",
    [C.TOOL.ROAD]       = "ROAD",
    [C.TOOL.POWER_LINE] = "POWER LINE",
    [C.TOOL.PLANT]      = "POWER PLANT",
    [C.TOOL.MINE]             = "IRON MINE",
    [C.TOOL.RAIL]             = "FREIGHT RAIL",
    [C.TOOL.FREIGHT_STATION]  = "FREIGHT STATION",
}

local OVERLAY_NAME = {
    [C.OVERLAY.NONE]       = "NONE",
    [C.OVERLAY.POLLUTION]  = "POLLUTION",
    [C.OVERLAY.LAND_VALUE] = "LAND VALUE",
    [C.OVERLAY.POWER]      = "POWER",
    [C.OVERLAY.FREIGHT]    = "FREIGHT",
}

local function speed_name(speed)
    if speed == C.SPEED.PAUSED then return "PAUSED" end
    if speed == C.SPEED.FAST then return "FAST" end
    return "NORMAL"
end

local function label_value(label, value, x, y)
    love.graphics.setFont(Theme.font("meta"))
    love.graphics.setColor(Theme.color("dim_fg"))
    love.graphics.print(label, x, y)
    love.graphics.setFont(Theme.font("body"))
    love.graphics.setColor(Theme.color("fg"))
    love.graphics.print(value, x, y + 12)
end

-- Draw a top-bar style strip. Used so HUD readouts sit on a consistent dark background.
local function strip(x, y, w, h)
    love.graphics.setColor(Theme.color("bg"))
    love.graphics.rectangle("fill", x, y, w, h)
    Widgets.outline(x, y, w, h)
end

function Hud.draw(world, opts)
    local year, month = Clock.date(world)
    local res_n = World.count_buildings(world, C.ZONE.RESIDENTIAL, C.BUILD.COMPLETE)
    local com_n = World.count_buildings(world, C.ZONE.COMMERCIAL, C.BUILD.COMPLETE)
    local ind_n = World.count_buildings(world, C.ZONE.INDUSTRIAL, C.BUILD.COMPLETE)
    local W, H = love.graphics.getWidth(), love.graphics.getHeight()

    -- Top status strip.
    local top_h = 64
    strip(0, 0, W, top_h)

    love.graphics.setFont(Theme.font("body"))
    local font = love.graphics.getFont()
    local mission_name = (world.mission and world.mission.name) or "MISSION"

    -- Row 1: ▶ MISSION NAME · DATE · SPEED · FPS
    love.graphics.setColor(Theme.color("amber"))
    love.graphics.print("▶", 16, 10)
    love.graphics.setColor(Theme.color("fg"))
    local line1 = ("%s    DATE %04d-%02d    %s    FPS %d"):format(
        string.upper(mission_name), year, month,
        speed_name(opts.speed), love.timer.getFPS())
    love.graphics.print(line1, 40, 10)

    -- Row 2: POP / RCI / DEMAND / POWER, all in one line
    local p = Power.stats(world)
    local line2 = ("POP %d   R %d   C %d   I %d   DEMAND R%+.2f C%+.2f I%+.2f   POWER %d/%d MW"):format(
        World.population(world), res_n, com_n, ind_n,
        world.demand.residential, world.demand.commercial, world.demand.industrial,
        p.supply, p.demand)
    love.graphics.print(line2, 16, 36)
    -- Unpowered warning appended in accent.
    if p.dark > 0 then
        love.graphics.setColor(Theme.color("accent"))
        love.graphics.print(("   ! %d AREA(S) UNPOWERED"):format(p.dark),
            16 + font:getWidth(line2), 36)
    end

    -- Status flash.
    if opts.status then
        love.graphics.setColor(Theme.color("amber"))
        local sw = font:getWidth(opts.status)
        love.graphics.print(string.upper(opts.status), W - 16 - sw, 10)
    end

    -- Tool / Overlay / Cost line below the strip (drawn directly on grass
    -- but in bone bold-feel = body font, contrast still solid).
    love.graphics.setColor(Theme.color("fg"))
    local tool_line = ("TOOL %s    OVERLAY %s"):format(
        TOOL_NAME[opts.tool], OVERLAY_NAME[opts.overlay or C.OVERLAY.NONE])
    if opts.drag_cost then
        tool_line = tool_line .. ("    COST %s"):format(money(opts.drag_cost))
    end
    -- A small umber chip behind it so the values read; sized to the text.
    local tlw = font:getWidth(tool_line)
    strip(8, top_h + 8, tlw + 24, font:getHeight() + 10)
    love.graphics.setColor(Theme.color("fg"))
    love.graphics.print(tool_line, 20, top_h + 13)

    -- Monthly budget panel, bottom-left above the key hint.
    local b = Economy.budget(world)
    local panel_h = 7 * ROW_H + 16
    local top = H - 36 - panel_h
    strip(PANEL_X, top, PANEL_W, panel_h)
    love.graphics.setFont(Theme.font("meta"))
    love.graphics.setColor(Theme.color("gold"))
    love.graphics.print("MONTHLY BUDGET", PANEL_X + 12, top + 8)
    love.graphics.setColor(Theme.color("dim_fg"))
    love.graphics.line(PANEL_X + 12, top + 24, PANEL_X + PANEL_W - 12, top + 24)
    budget_row("CURRENT BALANCE", money(world.treasury), top + 32)
    budget_row("MONTHLY INCOME", money(b.income), top + 32 + ROW_H)
    budget_row("MONTHLY EXPENSE", "(" .. money(b.expense) .. ")", top + 32 + 2 * ROW_H)
    love.graphics.setColor(Theme.color("dim_fg"))
    love.graphics.line(PANEL_X + 12, top + 32 + 3 * ROW_H + 2, PANEL_X + PANEL_W - 12, top + 32 + 3 * ROW_H + 2)
    budget_row("MONTH END CASH", money(world.treasury + b.net), top + 32 + 4 * ROW_H + 4)

    -- Logistics panel, bottom-right above the key hint. Shows raw-materials
    -- supply chain status so the player can diagnose freight bottlenecks.
    local LOGI_W = 220
    local LOGI_X = W - LOGI_W - PANEL_X
    local supply  = world.goods.supply[C.GOODS.RAW_MATERIALS]  or 0
    local demand  = world.goods.demand[C.GOODS.RAW_MATERIALS]  or 0
    local inv     = world.goods.inventory[C.GOODS.RAW_MATERIALS] or 0
    local eff_pct = math.floor(Goods.efficiency(world, C.GOODS.RAW_MATERIALS) * 100)
    local logi_rows = 5  -- header + divider + 4 data rows
    local logi_h = logi_rows * ROW_H + 16
    local logi_top = H - 36 - logi_h
    strip(LOGI_X, logi_top, LOGI_W, logi_h)
    love.graphics.setFont(Theme.font("meta"))
    love.graphics.setColor(Theme.color("gold"))
    love.graphics.print("LOGISTICS", LOGI_X + 12, logi_top + 8)
    love.graphics.setColor(Theme.color("dim_fg"))
    love.graphics.line(LOGI_X + 12, logi_top + 24, LOGI_X + LOGI_W - 12, logi_top + 24)
    local function logi_row(label, value, y)
        love.graphics.setFont(Theme.font("meta"))
        love.graphics.setColor(Theme.color("dim_fg"))
        love.graphics.print(string.upper(label), LOGI_X + 12, y)
        love.graphics.setFont(Theme.font("body"))
        love.graphics.setColor(Theme.color("fg"))
        local fnt = love.graphics.getFont()
        love.graphics.print(value, LOGI_X + LOGI_W - fnt:getWidth(value), y - 2)
    end
    logi_row("RAW SUPPLY",  supply .. "/mo",  logi_top + 32)
    logi_row("RAW DEMAND",  demand .. "/mo",  logi_top + 32 + ROW_H)
    logi_row("RAW STOCK",   tostring(inv),    logi_top + 32 + 2 * ROW_H)
    -- Color efficiency value: green when high, amber when mid, accent when low.
    local eff_str = eff_pct .. "%"
    love.graphics.setFont(Theme.font("meta"))
    love.graphics.setColor(Theme.color("dim_fg"))
    love.graphics.print("EFFICIENCY", LOGI_X + 12, logi_top + 32 + 3 * ROW_H)
    love.graphics.setFont(Theme.font("body"))
    local eff_color = eff_pct >= 80 and Theme.color("fg")
        or eff_pct >= 40 and Theme.color("amber")
        or Theme.color("accent")
    love.graphics.setColor(eff_color)
    local fnt2 = love.graphics.getFont()
    love.graphics.print(eff_str, LOGI_X + LOGI_W - fnt2:getWidth(eff_str),
        logi_top + 32 + 3 * ROW_H - 2)

    -- Bottom hint strip.
    local hint_h = 24
    strip(0, H - hint_h, W, hint_h)
    love.graphics.setFont(Theme.font("meta"))
    love.graphics.setColor(Theme.color("fg"))
    love.graphics.print(
        "[1]BULLDOZE  [2]RES  [3]COM  [4]IND  [5]ROAD  [6]LINE  [7]PLANT  [8]MINE  [9]RAIL  [0]STATION  |  DRAG TO BUILD  |  [O]VERLAY  |  SPACE PAUSE  +/- SPEED  |  F5 SAVE  F9 LOAD  |  WASD/SCROLL CAMERA",
        12, H - hint_h + 8)
end

return Hud
