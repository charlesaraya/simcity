-- src/ui/screens/new_mission.lua
-- The Charter Identity screen.
--
-- The RNG is INJECTED at construction so two screens seeded the same yield
-- the same initial roll. Separated from the world's RNG: charter choices
-- don't disturb growth, and re-rolling the mission name on the screen doesn't
-- shift the simulated city's first dice.
--
-- Step 6 scope (declared in commit notes): no inline rename, no world params,
-- no mouse — those land in step 10 polish. R re-rolls everything (mission +
-- crew); Left/Right adjusts the focused enum/int; Enter activates a button;
-- Tab/arrow keys move focus.

local C                 = require("src.world.constants")
local NamePicker        = require("src.ui.name_picker")
local difficulties      = require("src.ui.content.difficulties")

local NewMission        = {}
NewMission.__index      = NewMission

-- Focus order. Matches visual reading order: name -> difficulty -> team_size
-- -> world params (2x2 grid: size, climate, hostility, funds in reading
-- order) -> Back / Charter. Crew preview sits visually between team_size and
-- the world params but isn't focusable (it's derived).
local FIELDS            = {
    "mission_name", -- 1
    "difficulty",   -- 2
    "team_size",    -- 3
    "size",         -- 4 \
    "climate",      -- 5  | world params (2x2 grid in reading order)
    "hostility",    -- 6  |
    "funds",        -- 7 /
    "back",         -- 8
    "charter",      -- 9
}

-- Ordered list of world-param keys + their display labels. The 2x2 grid walks
-- WP_KEYS in this order: row 1 (size, climate), row 2 (hostility, funds).
local WP_KEYS           = { "size", "climate", "hostility", "funds" }
local WP_LABELS         = {
    size      = "World Size",
    climate   = "Climate",
    hostility = "Hostility",
    funds     = "Starting Funds",
}

local FIRST_MISSION_IDX = 2 -- the middle preset; starts focused

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function fire(self, name, payload)
    local fn = self.actions[name]
    if fn then fn(payload) end
end

-- (RE)ROLL: refresh both mission name and crew from the current rng state.
-- Called on init, on R, and whenever team_size changes (so the crew preview
-- stays the right length). Resets the caret to the end of the new name.
local function reroll(self)
    self.mission_name = NamePicker.default_mission_name(self.rng)
    self.crew = NamePicker.default_crew(self.rng, self.team_size)
    self.caret = #self.mission_name
end

function NewMission.new(opts)
    opts = opts or {}
    local self = setmetatable({}, NewMission)
    self.rng = assert(opts.rng, "NewMission.new requires opts.rng")
    self.actions = opts.actions or {}
    self.focused = 1
    self.hovered = nil  -- {id, key/idx} for the widget under the cursor (mouse polish)
    self.caret = 0      -- byte position in mission_name; 0..#name. Used while editing.
    self.team_size = C.MISSION.TEAM_SIZE_DEFAULT
    self.difficulty_idx = FIRST_MISSION_IDX
    -- World params: each field starts on the configured default index. Stored
    -- as a single table keyed by WP_KEYS so keypressed/draw can iterate without
    -- a per-field switch.
    self.wp_idx = {}
    for _, key in ipairs(WP_KEYS) do
        self.wp_idx[key] = C.WORLD_PARAMS[key].default
    end
    reroll(self)
    -- After reroll, the caret sits at the end of the freshly rolled name so
    -- the player can immediately edit from the right.
    self.caret = #self.mission_name
    return self
end

-- Build the {mission, crew} payload the charter action receives. started_at
-- is intentionally left for main's action handler (it's the wall-clock time
-- of acceptance, not screen time -- and keeping it out of here keeps the
-- screen pure for tests). world_params are stored as keyed strings (not
-- indices) so legacy saves stay readable even if the choices table shifts.
local function build_payload(self)
    local wp = {}
    for _, key in ipairs(WP_KEYS) do
        wp[key] = C.WORLD_PARAMS[key].choices[self.wp_idx[key]]
    end
    return {
        mission = {
            name = self.mission_name,
            difficulty = difficulties[self.difficulty_idx].key,
            world_params = wp,
        },
        crew = self.crew,
    }
end

-- FIELD ADJUSTERS -----------------------------------------------------------

local function bump_team_size(self, delta)
    local new = clamp(self.team_size + delta, C.MISSION.TEAM_SIZE_MIN, C.MISSION.TEAM_SIZE_MAX)
    if new == self.team_size then return end
    self.team_size = new
    -- Resizing rerolls the crew so the preview shows ACTUAL N members at the
    -- ACTUAL N roles (slot 1 always Commander, etc). The mission name is
    -- preserved -- only the crew refreshes.
    self.crew = NamePicker.default_crew(self.rng, self.team_size)
end

local function bump_difficulty(self, delta)
    self.difficulty_idx = clamp(self.difficulty_idx + delta, 1, #difficulties)
end

-- World-param Left/Right bump: clamp within the field's choices list.
local function bump_wp(self, key, delta)
    local n = #C.WORLD_PARAMS[key].choices
    self.wp_idx[key] = clamp(self.wp_idx[key] + delta, 1, n)
end

local function is_wp_field(field)
    return field == "size" or field == "climate"
        or field == "hostility" or field == "funds"
end

-- KEYBOARD ------------------------------------------------------------------

function NewMission:keypressed(key)
    local field = FIELDS[self.focused]

    -- Esc is always Back. R re-rolls except while the name field is focused.
    if key == "escape" then return fire(self, "back") end
    if key == "r" and field ~= "mission_name" then return reroll(self) end

    -- Mission-name edit. Backspace deletes the character to the LEFT of the
    -- caret; Left/Right moves the caret; Home/End jump to ends. The actual
    -- character insertion comes via love.textinput, not keypressed.
    if field == "mission_name" then
        if key == "backspace" then
            if self.caret > 0 then
                local n = self.mission_name
                self.mission_name = n:sub(1, self.caret - 1) .. n:sub(self.caret + 1)
                self.caret = self.caret - 1
            end
            return
        elseif key == "delete" then
            local n = self.mission_name
            if self.caret < #n then
                self.mission_name = n:sub(1, self.caret) .. n:sub(self.caret + 2)
            end
            return
        elseif key == "left" then
            self.caret = math.max(0, self.caret - 1); return
        elseif key == "right" then
            self.caret = math.min(#self.mission_name, self.caret + 1); return
        elseif key == "home" then
            self.caret = 0; return
        elseif key == "end" then
            self.caret = #self.mission_name; return
        end
    end

    -- Focus nav.
    if key == "tab" or key == "down" then
        self.focused = clamp(self.focused + 1, 1, #FIELDS); return
    end
    if key == "up" then
        self.focused = clamp(self.focused - 1, 1, #FIELDS); return
    end

    -- Per-field handlers for Left/Right and Enter.
    if field == "team_size" then
        if key == "right" then
            bump_team_size(self, 1)
        elseif key == "left" then
            bump_team_size(self, -1)
        end
    elseif field == "difficulty" then
        if key == "right" then
            bump_difficulty(self, 1)
        elseif key == "left" then
            bump_difficulty(self, -1)
        end
    elseif is_wp_field(field) then
        if key == "right" then
            bump_wp(self, field, 1)
        elseif key == "left" then
            bump_wp(self, field, -1)
        end
    elseif field == "back" then
        if key == "return" or key == "kpenter" then fire(self, "back") end
    elseif field == "charter" then
        if key == "return" or key == "kpenter" then fire(self, "charter", build_payload(self)) end
    end
    -- mission_name has no Left/Right.
end

-- love.textinput delivery (locale-aware typed characters). Insert at the
-- caret while the name field is focused; ignore otherwise. Caret advances
-- past the inserted text. A max length keeps the buffer bounded.
local NAME_MAX_LEN = 32
function NewMission:textinput(text)
    if FIELDS[self.focused] ~= "mission_name" then return end
    if #self.mission_name + #text > NAME_MAX_LEN then return end
    local n = self.mission_name
    self.mission_name = n:sub(1, self.caret) .. text .. n:sub(self.caret + 1)
    self.caret = self.caret + #text
end

-- DRAW --------------------------------------------
-- A dossier-formal layout: title strip with a leading ▶ marker; outlined panel
-- holding the form; the segmented selectors paint the active cell with a warm
-- amber fill + horizontal scanlines (the "CRT terminal" feel approximated in
-- pure rectangles -- no shader, no pixel font). Buttons follow the same
-- language: Back outlined, Charter filled when focused.

local Theme            = require("src.ui.theme")
local Widgets          = require("src.ui.widgets")

-- Layout constants.
local TITLE_X          = 56
local TITLE_Y          = 36
local PANEL_MARGIN_X   = 48
local PANEL_TOP_Y      = 100
local PANEL_BOTTOM_PAD = 90
local PANEL_PAD        = 32 -- inner padding
local SECTION_GAP      = 22 -- gap between label and control

-- Section label drawn in dim small caps above its control. If `focused` is
-- true, gets a leading ▶ marker in accent so the keyboard focus is visible
-- BEFORE the user touches the control.
local function section_label(text, x, y, focused)
    love.graphics.setFont(Theme.font("meta"))
    if focused then
        love.graphics.setColor(Theme.color("accent"))
        love.graphics.print("▶ ", x - 14, y)
    end
    love.graphics.setColor(Theme.color("dim_fg"))
    love.graphics.print(string.upper(text), x, y)
end

-- A subtle hover fill: a low-alpha bone wash over the widget. Drawn beneath
-- whatever the widget's primary fill/outline is, so it reads as "cursor is
-- here, not yet engaged". Declared before its consumers (Lua local lookup).
local function hover_wash(x, y, w, h)
    local fg = Theme.color("fg")
    love.graphics.setColor(fg[1], fg[2], fg[3], 0.08)
    love.graphics.rectangle("fill", x, y, w, h)
end

-- Segmented control: N evenly-divided cells across (x, w). Active cell is
-- amber-filled with scanlines; outline is ALWAYS drawn so the active cell
-- doesn't appear shrunk by 1 px. `hovered_idx` adds a subtle bone wash to
-- the hovered cell (independent of active).
local function segmented(x, y, w, h, labels, active_idx, hovered_idx)
    local n = #labels
    local cell_w = w / n
    love.graphics.setFont(Theme.font("body"))
    local font = love.graphics.getFont()
    for i, label in ipairs(labels) do
        local cx = x + (i - 1) * cell_w
        if i == hovered_idx and i ~= active_idx then
            hover_wash(cx, y, cell_w, h)
        end
        if i == active_idx then
            Widgets.scanline_fill(cx + 1, y + 1, cell_w - 2, h - 2)
        end
        Widgets.outline(cx, y, cell_w, h)
        if i == active_idx then
            love.graphics.setColor(Theme.color("bg"))
        else
            love.graphics.setColor(Theme.color("fg"))
        end
        local tw = font:getWidth(label)
        love.graphics.print(label, cx + (cell_w - tw) * 0.5, y + (h - font:getHeight()) * 0.5)
    end
end

-- An outlined box with text inside, used for the mission name field. When
-- `editing` is true, render a blinking caret at the byte position `caret`
-- so the player can see where insertions and backspaces land. The blink
-- is driven by love.timer.getTime() (no state inside the screen).
local function name_box(x, y, w, h, value, editing, caret, hovered)
    if hovered and not editing then hover_wash(x, y, w, h) end
    Widgets.outline(x, y, w, h)
    love.graphics.setFont(Theme.font("body"))
    love.graphics.setColor(Theme.color("fg"))
    local font = love.graphics.getFont()
    local text = string.upper(value)
    local text_y = y + (h - font:getHeight()) * 0.5
    love.graphics.print(text, x + 14, text_y)
    if editing then
        local t = love.timer and love.timer.getTime() or 0
        if (t * 2) % 2 < 1 then
            local prefix = text:sub(1, caret)
            local cx = x + 14 + font:getWidth(prefix)
            love.graphics.setColor(Theme.color("amber"))
            love.graphics.rectangle("fill", cx + 1, text_y, 2, font:getHeight())
        end
    end
end

-- A button: filled-amber when `filled` (focused Charter), outlined otherwise.
-- The outline is ALWAYS drawn so the box's footprint stays consistent (no
-- 1-px shrink between unfocused and focused states). `hovered` adds a subtle
-- bone wash when the cursor is over the button.
local function button(x, y, w, h, label, filled, hovered)
    if hovered and not filled then hover_wash(x, y, w, h) end
    if filled then
        Widgets.scanline_fill(x + 1, y + 1, w - 2, h - 2)
    end
    Widgets.outline(x, y, w, h)
    if filled then
        love.graphics.setColor(Theme.color("bg"))
    else
        love.graphics.setColor(Theme.color("fg"))
    end
    love.graphics.setFont(Theme.font("body"))
    local font = love.graphics.getFont()
    local tw = font:getWidth(label)
    love.graphics.print(label, x + (w - tw) * 0.5, y + (h - font:getHeight()) * 0.5)
end

-- Pure layout: given the window size, return rectangles for every interactive
-- widget. Used by BOTH draw and the mouse hit-test, so they can't drift apart
-- the way they would if each computed its own geometry.
local function compute_layout(W, H)
    local px = PANEL_MARGIN_X
    local py = PANEL_TOP_Y
    local pw = W - PANEL_MARGIN_X * 2
    local ph = H - PANEL_TOP_Y - PANEL_BOTTOM_PAD
    local cx = px + PANEL_PAD
    local cy = py + PANEL_PAD
    local content_w = pw - PANEL_PAD * 2

    -- Two-column split: left = editable form, right = mission summary (crew
    -- preview now, planet/climate later). All form fields shrink to fit the
    -- left only; the right column reads off the right side.
    local COL_GAP    = 32
    local LEFT_RATIO = 0.58
    local left_w     = math.floor((content_w - COL_GAP) * LEFT_RATIO)
    local right_w    = content_w - left_w - COL_GAP
    local left_x     = cx
    local right_x    = cx + left_w + COL_GAP
    local field_w    = left_w

    -- Mission Designation
    local y_name = cy
    local name_rect = { x = left_x, y = y_name + SECTION_GAP, w = field_w, h = 38 }
    local y = y_name + SECTION_GAP + 38 + 28

    -- Difficulty (3 cells)
    local y_diff = y
    local diff_y = y + SECTION_GAP
    local diff_h = 32
    local diff_cells = {}
    local diff_cell_w = field_w / 3
    for i = 1, 3 do
        diff_cells[i] = { x = cx + (i - 1) * diff_cell_w, y = diff_y, w = diff_cell_w, h = diff_h }
    end
    y = y + SECTION_GAP + diff_h + 36

    -- Team Size (5 cells)
    local y_team = y
    local team_y = y + SECTION_GAP
    local team_cells = {}
    local team_cell_w = field_w / 5
    for i = 1, 5 do
        team_cells[i] = { x = cx + (i - 1) * team_cell_w, y = team_y, w = team_cell_w, h = 32 }
    end
    y = y + SECTION_GAP + 32 + 28

    -- World Parameters (2x2 grid). Reading order:
    --   row 1: size, climate
    --   row 2: hostility, funds
    -- Each cell is a 3-cell segmented control. The two columns share a small
    -- horizontal gap; row heights repeat the section pattern (label + control).
    local WP_COL_GAP = 24
    local wp_col_w = (field_w - WP_COL_GAP) / 2
    local WP_ROW_H = 32
    local WP_LABEL_GAP = SECTION_GAP
    local WP_ROW_SPACING = 32 -- gap between row 1 and row 2

    local wp = {}             -- keyed by WP key (size/climate/hostility/funds)
    for ri = 0, 1 do
        local row_y = y + ri * (WP_LABEL_GAP + WP_ROW_H + WP_ROW_SPACING)
        for ci = 0, 1 do
            local key = WP_KEYS[ri * 2 + ci + 1]
            local n = #C.WORLD_PARAMS[key].choices
            local origin_x = cx + ci * (wp_col_w + WP_COL_GAP)
            local cells = {}
            local cell_w = wp_col_w / n
            for j = 1, n do
                cells[j] = {
                    x = origin_x + (j - 1) * cell_w,
                    y = row_y + WP_LABEL_GAP,
                    w = cell_w,
                    h = WP_ROW_H,
                }
            end
            wp[key] = {
                label_x = origin_x,
                label_y = row_y,
                cells = cells,
            }
        end
    end
    y = y + 2 * (WP_LABEL_GAP + WP_ROW_H) + WP_ROW_SPACING + 24

    -- Crew preview anchors at the TOP of the right column (its own visual
    -- block rather than stacked under the form).
    local y_crew = cy

    -- Bottom buttons (Back / Charter)
    local btn_w, btn_h = 140, 36
    local btn_y        = py + ph - PANEL_PAD - btn_h
    local charter_rect = { x = cx + content_w - btn_w, y = btn_y, w = btn_w, h = btn_h }
    local back_rect    = { x = charter_rect.x - btn_w - 16, y = btn_y, w = btn_w, h = btn_h }

    return {
        panel = { x = px, y = py, w = pw, h = ph },
        content = {
            cx = cx, cy = cy, content_w = content_w, field_w = field_w,
            left_x = left_x, left_w = left_w,
            right_x = right_x, right_w = right_w,
        },
        sep_y          = py + ph - PANEL_PAD - 56,
        y_name         = y_name,
        name           = name_rect,
        y_diff         = y_diff,
        diff_cells     = diff_cells,
        diff_summary_y = diff_y + diff_h + 8,
        y_team         = y_team,
        team_cells     = team_cells,
        wp             = wp,
        y_crew         = y_crew,
        back           = back_rect,
        charter        = charter_rect,
    }
end

local function in_rect(x, y, r)
    return x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h
end

-- Hit-test: return widget id (and an optional index for segmented cells), or
-- nil if (x, y) isn't over an interactive surface. For world-param cells,
-- returns "wp_cell" with the WP key (second return) AND the cell index
-- (third return).
local function widget_at(L, x, y)
    if in_rect(x, y, L.name) then return "name" end
    for i, r in ipairs(L.diff_cells) do
        if in_rect(x, y, r) then return "diff_cell", i end
    end
    for i, r in ipairs(L.team_cells) do
        if in_rect(x, y, r) then return "team_cell", i end
    end
    for _, key in ipairs(WP_KEYS) do
        for i, r in ipairs(L.wp[key].cells) do
            if in_rect(x, y, r) then return "wp_cell", key, i end
        end
    end
    if in_rect(x, y, L.back) then return "back" end
    if in_rect(x, y, L.charter) then return "charter" end
    return nil
end

-- Map a WP key to its FIELDS focus index.
local WP_FOCUS_INDEX = { size = 4, climate = 5, hostility = 6, funds = 7 }

-- MOUSE ---------------------------------------------------------------------
-- Hit-tests use the same compute_layout the draw uses, so mouse and visuals
-- can't drift. We cache the last computed layout on self after each draw, so
-- mousemoved/pressed can hit-test against the geometry the player is seeing
-- (love guarantees draw before input on the first frame).

function NewMission:mousemoved(x, y)
    local L = self._layout
        or compute_layout(love.graphics.getWidth(), love.graphics.getHeight())
    local id, a, b = widget_at(L, x, y)
    self.hovered = id and { id = id, a = a, b = b } or nil
    if id == "name" then
        self.focused = 1
    elseif id == "diff_cell" then
        self.focused = 2
    elseif id == "team_cell" then
        self.focused = 3
    elseif id == "wp_cell" then
        self.focused = WP_FOCUS_INDEX[a]
    elseif id == "back" then
        self.focused = 8
    elseif id == "charter" then
        self.focused = 9
    end
end

function NewMission:mousepressed(x, y, button)
    if button ~= 1 then return end
    local L = self._layout
        or compute_layout(love.graphics.getWidth(), love.graphics.getHeight())
    local id, a, b = widget_at(L, x, y)
    if id == "name" then
        self.focused = 1
    elseif id == "diff_cell" then
        self.focused = 2
        if a then self.difficulty_idx = a end
    elseif id == "team_cell" then
        self.focused = 3
        if a and a ~= self.team_size then
            self.team_size = a
            self.crew = NamePicker.default_crew(self.rng, self.team_size)
        end
    elseif id == "wp_cell" then
        self.focused = WP_FOCUS_INDEX[a]
        if b then self.wp_idx[a] = b end
    elseif id == "back" then
        self.focused = 8
        fire(self, "back")
    elseif id == "charter" then
        self.focused = 9
        fire(self, "charter", build_payload(self))
    end
end

function NewMission:draw()
    local W, H = love.graphics.getWidth(), love.graphics.getHeight()
    local L = compute_layout(W, H)
    self._layout = L -- cache for mouse hit-tests

    -- Title strip: ▶ NEW MISSION  with dim subtitle below.
    love.graphics.setFont(Theme.font("heading"))
    love.graphics.setColor(Theme.color("amber"))
    love.graphics.print("▶", TITLE_X, TITLE_Y)
    love.graphics.setColor(Theme.color("fg"))
    love.graphics.print("NEW MISSION", TITLE_X + 24, TITLE_Y)
    love.graphics.setFont(Theme.font("meta"))
    love.graphics.setColor(Theme.color("dim_fg"))
    love.graphics.print("-- CHARTER IDENTITY --", TITLE_X + 24, TITLE_Y + 28)

    -- Outer panel
    Widgets.frame(L.panel.x, L.panel.y, L.panel.w, L.panel.h)
    local cx = L.content.cx
    local content_w = L.content.content_w
    local field_w = L.content.field_w

    -- MISSION DESIGNATION ---------------------------------------------------
    section_label("Mission Designation", cx, L.y_name, self.focused == 1)
    local name_hover = self.hovered and self.hovered.id == "name" or false
    name_box(L.name.x, L.name.y, L.name.w, L.name.h, self.mission_name,
        self.focused == 1, self.caret, name_hover)

    -- Hover helpers: extract per-widget hover state once.
    local hv = self.hovered
    local diff_hover = (hv and hv.id == "diff_cell") and hv.a or nil
    local team_hover = (hv and hv.id == "team_cell") and hv.a or nil

    -- DIFFICULTY ------------------------------------------------------------
    section_label("Difficulty", L.content.left_x, L.y_diff, self.focused == 2)
    local diff_labels = {}
    for i, d in ipairs(difficulties) do diff_labels[i] = string.upper(d.label) end
    segmented(L.diff_cells[1].x, L.diff_cells[1].y, field_w, L.diff_cells[1].h,
        diff_labels, self.difficulty_idx, diff_hover)
    love.graphics.setFont(Theme.font("meta"))
    love.graphics.setColor(Theme.color("dim_fg"))
    love.graphics.print(string.upper(difficulties[self.difficulty_idx].summary),
        L.content.left_x, L.diff_summary_y)

    -- TEAM SIZE -------------------------------------------------------------
    section_label("Team Size", L.content.left_x, L.y_team, self.focused == 3)
    local size_labels = {}
    for i = C.MISSION.TEAM_SIZE_MIN, C.MISSION.TEAM_SIZE_MAX do
        size_labels[i] = tostring(i)
    end
    segmented(L.team_cells[1].x, L.team_cells[1].y, field_w, L.team_cells[1].h,
        size_labels, self.team_size, team_hover)

    -- WORLD PARAMETERS (2x2 grid: size + climate, then hostility + funds) --
    for _, key in ipairs(WP_KEYS) do
        local block = L.wp[key]
        section_label(WP_LABELS[key], block.label_x, block.label_y,
            self.focused == WP_FOCUS_INDEX[key])
        local labels = {}
        for i, c in ipairs(C.WORLD_PARAMS[key].choices) do
            labels[i] = string.upper(c)
        end
        local row = block.cells[1]
        local total_w = row.w * #block.cells
        local wp_hover = (hv and hv.id == "wp_cell" and hv.a == key) and hv.b or nil
        segmented(row.x, row.y, total_w, row.h, labels, self.wp_idx[key], wp_hover)
    end

    -- MISSION TEAM (right column read-only summary) ------------------------
    local rx, rw = L.content.right_x, L.content.right_w
    love.graphics.setFont(Theme.font("meta"))
    love.graphics.setColor(Theme.color("gold"))
    love.graphics.print("MISSION TEAM", rx, L.y_crew)
    Widgets.dashed_hr(rx, L.y_crew + 16, rx + rw)
    love.graphics.setFont(Theme.font("body"))
    love.graphics.setColor(Theme.color("fg"))
    for i, member in ipairs(self.crew) do
        local ry = L.y_crew + 28 + (i - 1) * 22
        love.graphics.setColor(Theme.color("dim_fg"))
        love.graphics.print(string.upper(C.ROLE_LABEL[member.role] or "—"), rx, ry)
        love.graphics.setColor(Theme.color("fg"))
        love.graphics.print(member.name, rx + 110, ry)
        love.graphics.setColor(Theme.color("dim_fg"))
        love.graphics.print("(" .. (member.traits[1] or "") .. ")",
            rx + 240, ry)
    end

    -- Dashed separator above the buttons, full inside-panel width.
    Widgets.dashed_hr(cx, L.sep_y, cx + content_w)

    -- Bottom-right Back + Charter buttons.
    local back_hover = hv and hv.id == "back" or false
    local charter_hover = hv and hv.id == "charter" or false
    button(L.back.x, L.back.y, L.back.w, L.back.h, "◀ BACK",
        self.focused == 8, back_hover)
    button(L.charter.x, L.charter.y, L.charter.w, L.charter.h, "CHARTER ▶",
        self.focused == 9, charter_hover)

    -- Hint strip beneath the panel.
    love.graphics.setFont(Theme.font("meta"))
    love.graphics.setColor(Theme.color("dim_fg"))
    local hint = "TAB/↑↓ FIELD   ←→ ADJUST   R RE-ROLL   ENTER CONFIRM   ESC BACK"
    local hw = love.graphics.getFont():getWidth(hint)
    love.graphics.print(hint, (W - hw) * 0.5, L.panel.y + L.panel.h + 28)
end

return NewMission
