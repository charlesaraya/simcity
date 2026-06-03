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
    [C.TOOL.ZONE_AGRI]        = "AGRICULTURAL",
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

    -- Left toolbar: persistent category list. Submenu expands right when open.
    local tb_rows = {
        { key = "1", label = "BULLDOZE",  cat = nil },
        { key = "2", label = "ZONE",      cat = 2   },
        { key = "3", label = "NETWORK",   cat = 3   },
        { key = "4", label = "BUILDINGS", cat = 4   },
    }
    local tb_font = love.graphics.getFont()  -- body font set above
    local tb_label_w = tb_font:getWidth("BUILDINGS")
    local tb_key_w   = tb_font:getWidth("[4] ")
    local tb_w = tb_key_w + tb_label_w + 24
    local tb_item_h = ROW_H + 2
    local tb_h = #tb_rows * tb_item_h + 8
    local tb_x = 8
    local tb_y = top_h + 44
    strip(tb_x, tb_y, tb_w, tb_h)
    for i, row in ipairs(tb_rows) do
        local ry = tb_y + 4 + (i - 1) * tb_item_h
        local active = opts.menu and opts.menu.cat == row.cat
        love.graphics.setFont(Theme.font("meta"))
        love.graphics.setColor(active and Theme.color("amber") or Theme.color("dim_fg"))
        love.graphics.print("[" .. row.key .. "]", tb_x + 6, ry + 2)
        love.graphics.setFont(Theme.font("body"))
        love.graphics.setColor(active and Theme.color("fg") or Theme.color("dim_fg"))
        love.graphics.print(row.label, tb_x + tb_key_w + 6, ry)
        if row.cat then
            love.graphics.setFont(Theme.font("meta"))
            love.graphics.setColor(active and Theme.color("amber") or Theme.color("dim_fg"))
            love.graphics.print("▸", tb_x + tb_w - 14, ry + 2)
        end
    end
    -- Submenu: right of toolbar, Y-aligned with the active category row.
    if opts.menu then
        local mc = opts.menu.data[opts.menu.cat]
        if mc then
            local cat_row = opts.menu.cat  -- cat 2=row2, 3=row3, 4=row4
            local sub_y = tb_y + 4 + (cat_row - 1) * tb_item_h
            local sub_x = tb_x + tb_w + 4
            local mitem_w = 0
            for _, item in ipairs(mc.items) do
                local w = tb_font:getWidth(item.label)
                if w > mitem_w then mitem_w = w end
            end
            local mw = mitem_w + tb_key_w + 24
            local mh = #mc.items * tb_item_h + 8
            strip(sub_x, sub_y, mw, mh)
            for i, item in ipairs(mc.items) do
                local iy = sub_y + 4 + (i - 1) * tb_item_h
                local focused = (i == opts.menu.idx)
                love.graphics.setFont(Theme.font("meta"))
                love.graphics.setColor(focused and Theme.color("amber") or Theme.color("dim_fg"))
                love.graphics.print("[" .. i .. "]", sub_x + 6, iy + 2)
                love.graphics.setFont(Theme.font("body"))
                love.graphics.setColor(focused and Theme.color("fg") or Theme.color("dim_fg"))
                love.graphics.print(item.label, sub_x + tb_key_w + 6, iy)
            end
        end
    end

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

    -- Logistics panel: raw-materials (freight chain) + food (farm output) side by side.
    local LOGI_W = 220
    local LOGI_X = W - LOGI_W - PANEL_X
    -- 10 row-equivalents: header(32px) + 4 raw + gap + 4 food + padding
    local logi_h = 10 * ROW_H + 16
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
    local function logi_eff(label, pct, y)
        local eff_str = pct .. "%"
        love.graphics.setFont(Theme.font("meta"))
        love.graphics.setColor(Theme.color("dim_fg"))
        love.graphics.print(string.upper(label), LOGI_X + 12, y)
        love.graphics.setFont(Theme.font("body"))
        local col = pct >= 80 and Theme.color("fg")
            or pct >= 40 and Theme.color("amber")
            or Theme.color("accent")
        love.graphics.setColor(col)
        local fnt = love.graphics.getFont()
        love.graphics.print(eff_str, LOGI_X + LOGI_W - fnt:getWidth(eff_str), y - 2)
    end

    -- Raw-materials rows (freight-gated).
    local raw_s   = world.goods.supply[C.GOODS.RAW_MATERIALS]    or 0
    local raw_d   = world.goods.demand[C.GOODS.RAW_MATERIALS]    or 0
    local raw_inv = world.goods.inventory[C.GOODS.RAW_MATERIALS] or 0
    local raw_eff = math.floor(Goods.efficiency(world, C.GOODS.RAW_MATERIALS) * 100)
    logi_row("RAW SUPPLY", raw_s .. "/mo",      logi_top + 32)
    logi_row("RAW DEMAND", raw_d .. "/mo",      logi_top + 32 + ROW_H)
    logi_row("RAW STOCK",  tostring(raw_inv),   logi_top + 32 + 2 * ROW_H)
    logi_eff("RAW EFF",    raw_eff,             logi_top + 32 + 3 * ROW_H)

    -- Divider between sections.
    love.graphics.setColor(Theme.color("dim_fg"))
    love.graphics.line(LOGI_X + 12, logi_top + 32 + 4 * ROW_H + 4,
                       LOGI_X + LOGI_W - 12, logi_top + 32 + 4 * ROW_H + 4)

    -- Food rows (farm-zone output, fertility-scaled).
    local food_base = logi_top + 32 + 5 * ROW_H
    local food_s   = world.goods.supply[C.GOODS.FOOD]    or 0
    local food_d   = world.goods.demand[C.GOODS.FOOD]    or 0
    local food_inv = world.goods.inventory[C.GOODS.FOOD] or 0
    local food_eff = math.floor(Goods.efficiency(world, C.GOODS.FOOD) * 100)
    logi_row("FOOD SUPPLY", string.format("%.1f/mo", food_s), food_base)
    logi_row("FOOD DEMAND", food_d .. "/mo",                  food_base + ROW_H)
    logi_row("FOOD STOCK",  string.format("%.1f", food_inv),  food_base + 2 * ROW_H)
    logi_eff("FOOD EFF",    food_eff,                         food_base + 3 * ROW_H)

    -- Bottom hint strip.
    local hint_h = 24
    strip(0, H - hint_h, W, hint_h)
    love.graphics.setFont(Theme.font("meta"))
    love.graphics.setColor(Theme.color("fg"))
    love.graphics.print(
        "↑↓ NAVIGATE  ENTER SELECT  ESC CLOSE  |  DRAG TO BUILD  |  [O]VERLAY  |  SPACE PAUSE  +/- SPEED  |  F5 SAVE  F9 LOAD  |  WASD/SCROLL CAMERA",
        12, H - hint_h + 8)
end

return Hud
