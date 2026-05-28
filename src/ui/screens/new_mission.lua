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

-- Focus order. Matches the visual top-to-bottom layout so Tab/↓ feels right:
-- name -> difficulty (with summary) -> team_size -> crew preview (not
-- focusable) -> Back / Charter at the bottom.
local FIELDS            = {
    "mission_name",
    "difficulty",
    "team_size",
    "back",
    "charter",
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
-- stays the right length).
local function reroll(self)
    self.mission_name = NamePicker.default_mission_name(self.rng)
    self.crew = NamePicker.default_crew(self.rng, self.team_size)
end

function NewMission.new(opts)
    opts = opts or {}
    local self = setmetatable({}, NewMission)
    self.rng = assert(opts.rng, "NewMission.new requires opts.rng")
    self.actions = opts.actions or {}
    self.focused = 1
    self.team_size = C.MISSION.TEAM_SIZE_DEFAULT
    self.difficulty_idx = FIRST_MISSION_IDX
    reroll(self)
    return self
end

-- Build the {mission, crew} payload the charter action receives. started_at
-- is intentionally left for main's action handler (it's the wall-clock time
-- of acceptance, not screen time -- and keeping it out of here keeps the
-- screen pure for tests).
local function build_payload(self)
    return {
        mission = {
            name = self.mission_name,
            difficulty = difficulties[self.difficulty_idx].key,
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

-- KEYBOARD ------------------------------------------------------------------

function NewMission:keypressed(key)
    -- Esc and R are global: they work regardless of focused field.
    if key == "escape" then return fire(self, "back") end
    if key == "r" then return reroll(self) end

    -- Focus nav (clamped, no wrap -- matches Home/Pause).
    if key == "tab" or key == "down" then
        self.focused = clamp(self.focused + 1, 1, #FIELDS); return
    end
    if key == "up" then
        self.focused = clamp(self.focused - 1, 1, #FIELDS); return
    end

    -- Per-field handlers for Left/Right and Enter.
    local field = FIELDS[self.focused]
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
    elseif field == "back" then
        if key == "return" or key == "kpenter" then fire(self, "back") end
    elseif field == "charter" then
        if key == "return" or key == "kpenter" then fire(self, "charter", build_payload(self)) end
    end
    -- mission_name has no Left/Right; R is the only mutation (handled above).
end

-- DRAW (love-only; run-verified) --------------------------------------------
-- A dossier-formal layout: title strip with a leading ▶ marker; outlined panel
-- holding the form; the segmented selectors paint the active cell with a warm
-- amber fill + horizontal scanlines (the "CRT terminal" feel approximated in
-- pure rectangles -- no shader, no pixel font). Buttons follow the same
-- language: Back outlined, Charter filled when focused.

local Theme   = require("src.ui.theme")
local Widgets = require("src.ui.widgets")

-- Layout constants. y values assume a working canvas tall enough to fit the
-- whole form; the panel rectangle scales with the actual window size.
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

-- Segmented control: N evenly-divided cells across (x, w). Active cell is
-- amber-filled with scanlines; the rest are bone-outlined.
local function segmented(x, y, w, h, labels, active_idx)
    local n = #labels
    local cell_w = w / n
    love.graphics.setFont(Theme.font("body"))
    local font = love.graphics.getFont()
    for i, label in ipairs(labels) do
        local cx = x + (i - 1) * cell_w
        if i == active_idx then
            Widgets.scanline_fill(cx + 1, y + 1, cell_w - 2, h - 2)
            love.graphics.setColor(Theme.color("bg"))
        else
            Widgets.outline(cx, y, cell_w, h)
            love.graphics.setColor(Theme.color("fg"))
        end
        local tw = font:getWidth(label)
        love.graphics.print(label, cx + (cell_w - tw) * 0.5, y + (h - font:getHeight()) * 0.5)
    end
end

-- An outlined box with text inside, used for the mission name field.
local function name_box(x, y, w, h, value)
    Widgets.outline(x, y, w, h)
    love.graphics.setFont(Theme.font("body"))
    love.graphics.setColor(Theme.color("fg"))
    local font = love.graphics.getFont()
    love.graphics.print(string.upper(value), x + 14, y + (h - font:getHeight()) * 0.5)
end

-- A button: filled-amber when `filled` (focused Charter), outlined otherwise.
local function button(x, y, w, h, label, filled)
    if filled then
        Widgets.scanline_fill(x + 1, y + 1, w - 2, h - 2)
        love.graphics.setColor(Theme.color("bg"))
    else
        Widgets.outline(x, y, w, h)
        love.graphics.setColor(Theme.color("fg"))
    end
    love.graphics.setFont(Theme.font("body"))
    local font = love.graphics.getFont()
    local tw = font:getWidth(label)
    love.graphics.print(label, x + (w - tw) * 0.5, y + (h - font:getHeight()) * 0.5)
end

function NewMission:draw()
    local W, H = love.graphics.getWidth(), love.graphics.getHeight()

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
    local px = PANEL_MARGIN_X
    local py = PANEL_TOP_Y
    local pw = W - PANEL_MARGIN_X * 2
    local ph = H - PANEL_TOP_Y - PANEL_BOTTOM_PAD
    Widgets.frame(px, py, pw, ph)

    -- Content origin inside the panel
    local cx = px + PANEL_PAD
    local cy = py + PANEL_PAD
    local content_w = pw - PANEL_PAD * 2
    local field_w = math.min(content_w, 720)

    -- MISSION DESIGNATION ---------------------------------------------------
    section_label("Mission Designation", cx, cy, self.focused == 1)
    name_box(cx, cy + SECTION_GAP, field_w, 38, self.mission_name)
    local y = cy + SECTION_GAP + 38 + 28

    -- DIFFICULTY ------------------------------------------------------------
    section_label("Difficulty", cx, y, self.focused == 2)
    local diff_labels = {}
    for i, d in ipairs(difficulties) do diff_labels[i] = string.upper(d.label) end
    segmented(cx, y + SECTION_GAP, field_w, 32, diff_labels, self.difficulty_idx)
    -- Summary line beneath the segmented control (dim small caps).
    love.graphics.setFont(Theme.font("meta"))
    love.graphics.setColor(Theme.color("dim_fg"))
    love.graphics.print(string.upper(difficulties[self.difficulty_idx].summary),
        cx, y + SECTION_GAP + 32 + 8)
    y = y + SECTION_GAP + 32 + 36

    -- TEAM SIZE -------------------------------------------------------------
    section_label("Team Size", cx, y, self.focused == 3)
    local size_labels = {}
    for i = C.MISSION.TEAM_SIZE_MIN, C.MISSION.TEAM_SIZE_MAX do
        size_labels[i] = tostring(i)
    end
    segmented(cx, y + SECTION_GAP, field_w, 32, size_labels, self.team_size)
    y = y + SECTION_GAP + 32 + 28

    -- MISSION TEAM ---------------------------------------------------------
    -- Gold header (ceremonial accent on the institution-facing block); rows
    -- in mono so name + trait columns align.
    love.graphics.setFont(Theme.font("meta"))
    love.graphics.setColor(Theme.color("gold"))
    love.graphics.print("MISSION TEAM", cx, y)
    love.graphics.setFont(Theme.font("body"))
    love.graphics.setColor(Theme.color("fg"))
    for i, member in ipairs(self.crew) do
        local ry = y + 22 + (i - 1) * 22
        local role = C.ROLE_LABEL[member.role]
        local trait = member.traits[1] or ""
        local line = ("%-14s %-22s  (%s)"):format(string.upper(role), member.name, trait)
        love.graphics.print(line, cx, ry)
    end

    -- Dashed separator above the buttons, full inside-panel width.
    local sep_y = py + ph - PANEL_PAD - 56
    Widgets.dashed_hr(cx, sep_y, cx + content_w)

    -- Bottom-right Back + Charter buttons. Charter fills when focused.
    local btn_w, btn_h = 140, 36
    local btn_y = py + ph - PANEL_PAD - btn_h
    local charter_x = cx + content_w - btn_w
    local back_x = charter_x - btn_w - 16
    button(back_x, btn_y, btn_w, btn_h, "◀ BACK", self.focused == 4)
    button(charter_x, btn_y, btn_w, btn_h, "CHARTER ▶", self.focused == 5)

    -- Hint strip beneath the panel.
    love.graphics.setFont(Theme.font("meta"))
    love.graphics.setColor(Theme.color("dim_fg"))
    local hint = "TAB/↑↓ FIELD   ←→ ADJUST   R RE-ROLL   ENTER CONFIRM   ESC BACK"
    local hw = love.graphics.getFont():getWidth(hint)
    love.graphics.print(hint, (W - hw) * 0.5, py + ph + 28)
end

return NewMission
