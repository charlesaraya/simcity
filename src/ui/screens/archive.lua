-- src/ui/screens/archive.lua
-- Load from Archive: lists saved missions in a fixed-height panel; selected
-- slot's metadata appears in a detail strip below; Continue loads it. Slot
-- metadata is computed by main.lua (it reads the persistence layer) and
-- passed in as plain tables, so the screen has no coupling to Save / love.
--
-- 4c-1 ships single-slot semantics (the existing F5 slot). For one save the
-- scroll machinery never engages; it's there so 4c-2 multi-slot lands as
-- pure data with no screen edits.
--
-- Selection nav:
--   ↑/↓   move selection (clamped, no-op when empty); auto-scrolls to keep
--         the selected row inside the fixed visible window
--   Enter / kpenter  fire continue(selected_slot)
--   Esc   fire back
--
-- Direct hotkeys (any focus): B back · C continue.
--
-- Mouse:
--   hover  sets selected to the slot row under the cursor (visible rows only)
--   click  selects AND fires continue (left button only)

local Archive   = {}
Archive.__index = Archive

-- Layout. PANEL_TOP_Y / ROW_H / VISIBLE_ROWS define the fixed-height list
-- window; the panel always reserves room for VISIBLE_ROWS so the screen
-- stays the same height regardless of how many slots are filled.
local PANEL_TOP_Y     = 110
local PANEL_PAD       = 24
local HEADER_H        = 34 -- column-header row height inside the panel
local ROW_H           = 56
local VISIBLE_ROWS    = 7
local ROWS_TOP_Y      = PANEL_TOP_Y + PANEL_PAD + HEADER_H

-- Detail strip sits beneath the main panel.
local DETAIL_GAP      = 16
local DETAIL_H        = 76

function Archive.new(opts)
    opts = opts or {}
    local self = setmetatable({}, Archive)
    self.slots = opts.slots or {}
    self.actions = opts.actions or {}
    -- selected = 0 sentinels the empty state.
    self.selected = (#self.slots > 0) and 1 or 0
    self.scroll_offset = 1
    -- Exposed as instance field so specs can reference it without parsing the
    -- module constants; tests assert scroll math against this number.
    self.VISIBLE_ROWS = VISIBLE_ROWS
    return self
end

function Archive:is_empty()
    return #self.slots == 0
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- Keep the selected row inside the visible window by adjusting scroll_offset.
-- Called after every selection change.
local function ensure_visible(self)
    if self.selected < self.scroll_offset then
        self.scroll_offset = self.selected
    elseif self.selected > self.scroll_offset + VISIBLE_ROWS - 1 then
        self.scroll_offset = self.selected - VISIBLE_ROWS + 1
    end
    -- Clamp scroll_offset so we never scroll past the last row.
    local max_offset = math.max(1, #self.slots - VISIBLE_ROWS + 1)
    self.scroll_offset = clamp(self.scroll_offset, 1, max_offset)
end

local function fire_back(self)
    if self.actions.back then self.actions.back() end
end

local function fire_continue(self)
    if self:is_empty() then return end
    if self.actions.continue then self.actions.continue(self.slots[self.selected]) end
end

-- KEYBOARD ------------------------------------------------------------------

function Archive:keypressed(key)
    if key == "escape" or key == "b" then
        fire_back(self); return
    end
    if self:is_empty() then return end
    if key == "down" then
        self.selected = clamp(self.selected + 1, 1, #self.slots)
        ensure_visible(self)
    elseif key == "up" then
        self.selected = clamp(self.selected - 1, 1, #self.slots)
        ensure_visible(self)
    elseif key == "return" or key == "kpenter" or key == "c" then
        fire_continue(self)
    end
end

-- GEOMETRY (pure, shared by hit-test and draw) ------------------------------

-- row_center returns the screen-y for the GLOBAL slot index i. The visible
-- window applies a -scroll_offset shift so a slot off-screen returns a y
-- outside the panel; the mouse hit-test filters by visibility separately.
function Archive:row_center(i)
    local visible_index = i - self.scroll_offset + 1
    return 0, ROWS_TOP_Y + (visible_index - 1) * ROW_H + ROW_H * 0.5
end

function Archive:row_at(_x, y)
    if self:is_empty() then return nil end
    if y < ROWS_TOP_Y then return nil end
    local visible_index = math.floor((y - ROWS_TOP_Y) / ROW_H) + 1
    if visible_index < 1 or visible_index > VISIBLE_ROWS then return nil end
    local i = self.scroll_offset + visible_index - 1
    if i < 1 or i > #self.slots then return nil end
    return i
end

-- MOUSE ---------------------------------------------------------------------

function Archive:mousemoved(x, y)
    local i = self:row_at(x, y)
    if i then self.selected = i end
end

function Archive:mousepressed(x, y, button)
    if button ~= 1 then return end
    local i = self:row_at(x, y)
    if not i then return end
    self.selected = i
    fire_continue(self)
end

-- DRAW (love-only; run-verified) --------------------------------------------

local Theme        = require("src.ui.theme")
local Widgets      = require("src.ui.widgets")
local difficulties = require("src.ui.content.difficulties")

local TITLE       = "LOAD FROM ARCHIVE"
local TITLE_X     = 56
local TITLE_Y     = 36
local EMPTY_MSG   = "-- NO RECORDS ON FILE --"
local MARKER      = "▶"

local function difficulty_abbr(key)
    for _, d in ipairs(difficulties) do
        if d.key == key then return d.abbr end
    end
    return "—"
end

-- Format treasury as currency. K-shorten when >= 1000 so the column never
-- wraps even at high values: 1500 -> "₡1.5K", 248000 -> "₡248K".
local function fmt_money(n)
    n = math.floor(n or 0)
    if n >= 100000 then return ("₡%dK"):format(math.floor(n / 1000)) end
    if n >= 1000 then return ("₡%.1fK"):format(n / 1000) end
    return ("₡%d"):format(n)
end

-- Column x-offsets within the row. Tuned so the header alignment matches.
local COLS = {
    NUM      = 28,
    NAME     = 96,
    CYCLE    = 0.50, -- ratio of row width
    POP      = 0.66,
    TREASURY = 0.80,
    DIFF     = 0.94,
}

local function col_x(row_x, row_w, key)
    local v = COLS[key]
    if v < 1 then return row_x + math.floor(row_w * v) end
    return row_x + v
end

function Archive:draw()
    local W = love.graphics.getWidth()

    -- Title strip
    love.graphics.setFont(Theme.font("heading"))
    love.graphics.setColor(Theme.color("amber"))
    love.graphics.print("▶", TITLE_X, TITLE_Y)
    love.graphics.setColor(Theme.color("fg"))
    love.graphics.print(TITLE, TITLE_X + 24, TITLE_Y)
    love.graphics.setFont(Theme.font("meta"))
    love.graphics.setColor(Theme.color("dim_fg"))
    local n = #self.slots
    local subtitle = ("-- MISSION RECORDS · %d %s --"):format(n, n == 1 and "RECORD" or "RECORDS")
    love.graphics.print(subtitle, TITLE_X + 24, TITLE_Y + 22)

    -- Main panel (fixed height regardless of slot count)
    local pw = math.min(W * 0.86, 1100)
    local px = (W - pw) * 0.5
    local py = PANEL_TOP_Y
    local ph = PANEL_PAD * 2 + HEADER_H + VISIBLE_ROWS * ROW_H
    Widgets.frame(px, py, pw, ph)

    local row_x = px + PANEL_PAD
    local row_w = pw - PANEL_PAD * 2

    -- Column header row (dim small caps + dashed separator beneath)
    love.graphics.setFont(Theme.font("meta"))
    love.graphics.setColor(Theme.color("dim_fg"))
    local header_y = py + PANEL_PAD + 6
    love.graphics.print("#",        row_x + COLS.NUM,           header_y)
    love.graphics.print("NAME",     row_x + COLS.NAME,          header_y)
    love.graphics.print("CYCLE",    col_x(row_x, row_w, "CYCLE"),    header_y)
    love.graphics.print("POP",      col_x(row_x, row_w, "POP"),      header_y)
    love.graphics.print("TREASURY", col_x(row_x, row_w, "TREASURY"), header_y)
    love.graphics.print("DIFF",     col_x(row_x, row_w, "DIFF"),     header_y)
    Widgets.dashed_hr(row_x, py + PANEL_PAD + HEADER_H - 2, row_x + row_w)

    -- Slot rows. Empty archive shows a single dim message centered in the
    -- list area; otherwise iterate the visible window.
    if self:is_empty() then
        love.graphics.setFont(Theme.font("body"))
        local font = love.graphics.getFont()
        love.graphics.setColor(Theme.color("dim_fg"))
        local mid_y = ROWS_TOP_Y + (VISIBLE_ROWS * ROW_H - font:getHeight()) * 0.5
        local mw = font:getWidth(EMPTY_MSG)
        love.graphics.print(EMPTY_MSG, row_x + (row_w - mw) * 0.5, mid_y)
    else
        love.graphics.setFont(Theme.font("body"))
        local font = love.graphics.getFont()
        local last = math.min(#self.slots, self.scroll_offset + VISIBLE_ROWS - 1)
        for i = self.scroll_offset, last do
            local slot = self.slots[i]
            local visible_index = i - self.scroll_offset + 1
            local ry = ROWS_TOP_Y + (visible_index - 1) * ROW_H + 4
            local row_inner_h = ROW_H - 8
            local text_y = ry + (row_inner_h - font:getHeight()) * 0.5

            local selected = (i == self.selected)
            if selected then
                Widgets.scanline_fill(row_x, ry, row_w, row_inner_h)
                love.graphics.setColor(Theme.color("bg"))
                love.graphics.print(MARKER, row_x + 8, text_y)
            else
                love.graphics.setColor(Theme.color("fg"))
            end

            local num = ("%02d"):format(slot.slot or i)
            local name = string.upper(slot.mission_name or "UNTITLED")
            local cycle = ("%04d"):format(slot.cycle or 0)
            local pop = tostring(slot.population or 0)
            local treasury = fmt_money(slot.treasury)
            local diff = difficulty_abbr(slot.difficulty)

            love.graphics.print(num,      row_x + COLS.NUM,                 text_y)
            love.graphics.print(name,     row_x + COLS.NAME,                text_y)
            love.graphics.print(cycle,    col_x(row_x, row_w, "CYCLE"),     text_y)
            love.graphics.print(pop,      col_x(row_x, row_w, "POP"),       text_y)
            love.graphics.print(treasury, col_x(row_x, row_w, "TREASURY"),  text_y)
            love.graphics.print(diff,     col_x(row_x, row_w, "DIFF"),      text_y)

            -- Subtle dashed separator between rows (skip after last visible).
            if i < last and not selected then
                love.graphics.setColor(Theme.color("dim_fg"))
                Widgets.dashed_hr(row_x, ry + row_inner_h + 3, row_x + row_w)
            end
        end
    end

    -- Detail strip beneath the panel.
    local dy = py + ph + DETAIL_GAP
    love.graphics.setColor(Theme.color("bg"))
    love.graphics.rectangle("fill", px, dy, pw, DETAIL_H)
    Widgets.outline(px, dy, pw, DETAIL_H)
    love.graphics.setFont(Theme.font("meta"))
    love.graphics.setColor(Theme.color("dim_fg"))
    if self:is_empty() then
        love.graphics.print("NO SLOT SELECTED", px + 24, dy + 20)
    else
        local s = self.slots[self.selected]
        love.graphics.print(("SELECTED · SLOT %02d"):format(s.slot or self.selected), px + 24, dy + 14)
        love.graphics.setFont(Theme.font("body"))
        love.graphics.setColor(Theme.color("fg"))
        love.graphics.print(string.upper(s.mission_name or "UNTITLED"), px + 24, dy + 36)
        -- PLAYED / SAVED placeholders -- 4c-2 will fill these from a metadata
        -- sidecar; for 4c-1 we don't track time-played, so show em dashes.
        love.graphics.setFont(Theme.font("meta"))
        love.graphics.setColor(Theme.color("dim_fg"))
        local right_x = px + pw - 280
        love.graphics.print("PLAYED",      right_x,       dy + 14)
        love.graphics.print("SAVED",       right_x + 110, dy + 14)
        love.graphics.setColor(Theme.color("fg"))
        love.graphics.print("—",           right_x,       dy + 36)
        love.graphics.print("—",           right_x + 110, dy + 36)
    end

    -- Hint strip beneath the detail.
    love.graphics.setFont(Theme.font("meta"))
    love.graphics.setColor(Theme.color("dim_fg"))
    local hint = self:is_empty()
        and "ESC / B BACK"
        or "↑↓ SELECT   ENTER / C CONTINUE   ESC / B BACK"
    local hw = love.graphics.getFont():getWidth(hint)
    love.graphics.print(hint, (W - hw) * 0.5, dy + DETAIL_H + 18)
end

return Archive
