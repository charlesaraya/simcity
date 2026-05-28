-- spec/ui/screens/new_mission_spec.lua
-- The Charter Identity screen. Form-shaped, not a menu list. Focusable fields
-- in order: mission_name, difficulty, team_size, back, charter -- matches the
-- visual top-to-bottom layout so Tab/down feels right. RNG is INJECTED
-- so charter rolls are deterministic from a seed (and the screen's RNG is
-- separate from the world's, so charter choices don't disturb growth).
--
-- The screen never imports love; its draw is the only love-touching part and
-- is run-verified, not spec'd.

local NewMission = require("src.ui.screens.new_mission")
local RNG = require("src.sim.rng")
local C = require("src.world.constants")
local difficulties = require("src.ui.content.difficulties")

-- An actions stub that records charter payloads / back hits.
local function actions_stub()
    local calls = {}
    return {
        back = function() calls[#calls + 1] = { name = "back" } end,
        charter = function(payload)
            calls[#calls + 1] = { name = "charter", payload = payload }
        end,
    }, calls
end

local function fresh(seed)
    local actions, calls = actions_stub()
    local s = NewMission.new({ rng = RNG.new(seed or 1), actions = actions })
    return s, calls
end

describe("NewMission.new (initial state)", function()
    it("focuses the first field (mission_name)", function()
        local s = fresh()
        assert.are.equal(1, s.focused)
    end)

    it("seeds the default team size and a complete crew", function()
        local s = fresh()
        assert.are.equal(C.MISSION.TEAM_SIZE_DEFAULT, s.team_size)
        assert.are.equal(C.MISSION.TEAM_SIZE_DEFAULT, #s.crew)
    end)

    it("rolls a mission name from the pool", function()
        local s = fresh()
        assert.is_string(s.mission_name)
        assert.is_true(#s.mission_name > 0)
    end)

    it("starts on a known difficulty (the '1st Mission' middle preset)", function()
        local s = fresh()
        assert.are.equal("first_mission", difficulties[s.difficulty_idx].key)
    end)

    it("is deterministic from a seed", function()
        local a = fresh(42)
        local b = fresh(42)
        assert.are.equal(a.mission_name, b.mission_name)
        assert.are.equal(a.crew[1].name, b.crew[1].name)
    end)
end)

describe("NewMission focus nav", function()
    it("Tab / down advances focus, clamped at the last field", function()
        local s = fresh()
        s:keypressed("tab"); assert.are.equal(2, s.focused)
        s:keypressed("down"); assert.are.equal(3, s.focused)
        s:keypressed("tab"); assert.are.equal(4, s.focused)
        s:keypressed("tab"); assert.are.equal(5, s.focused)
        s:keypressed("tab"); assert.are.equal(5, s.focused) -- clamped
    end)

    it("Shift-Tab / up retreats, clamped at the first field", function()
        local s = fresh()
        s.focused = 4
        s:keypressed("up"); assert.are.equal(3, s.focused)
        s:keypressed("up"); assert.are.equal(2, s.focused)
        s:keypressed("up"); assert.are.equal(1, s.focused)
        s:keypressed("up"); assert.are.equal(1, s.focused) -- clamped
    end)

    it("Esc fires back regardless of which field is focused", function()
        local s, calls = fresh()
        s.focused = 3
        s:keypressed("escape")
        assert.are.equal(1, #calls)
        assert.are.equal("back", calls[1].name)
    end)
end)

describe("NewMission re-roll (R key)", function()
    it("R re-rolls mission_name AND crew", function()
        local s = fresh(7)
        local before_name = s.mission_name
        local before_crew_1 = s.crew[1].name
        s:keypressed("r")
        -- A specific name may collide by chance, but the rng state has moved
        -- and crew[1] is a fresh roll. We check that re-roll DOES advance the rng:
        assert.is_string(s.mission_name)
        assert.are.equal(s.team_size, #s.crew)
        -- A second re-roll yields a different state again.
        local mid_name = s.mission_name
        s:keypressed("r")
        -- Across 3 rolls, at least one of (name, crew[1]) should differ from
        -- the original (collision probability across both is vanishingly low).
        local changed = s.mission_name ~= before_name
            or s.crew[1].name ~= before_crew_1
            or mid_name ~= before_name
        assert.is_true(changed)
    end)
end)

describe("NewMission team_size adjustment", function()
    -- team_size is field index 3 in the new visual focus order.
    it("Left/Right on team_size field bumps within [MIN..MAX]", function()
        local s = fresh()
        s.focused = 3
        local start = s.team_size
        s:keypressed("right")
        assert.are.equal(start + 1, s.team_size)
        s:keypressed("left")
        assert.are.equal(start, s.team_size)
    end)

    it("Right clamps at MAX", function()
        local s = fresh()
        s.focused = 3
        for _ = 1, 10 do s:keypressed("right") end
        assert.are.equal(C.MISSION.TEAM_SIZE_MAX, s.team_size)
    end)

    it("Left clamps at MIN", function()
        local s = fresh()
        s.focused = 3
        for _ = 1, 10 do s:keypressed("left") end
        assert.are.equal(C.MISSION.TEAM_SIZE_MIN, s.team_size)
    end)

    it("changing team_size re-rolls the crew to match the new size", function()
        local s = fresh()
        s.focused = 3
        s:keypressed("right")
        assert.are.equal(s.team_size, #s.crew)
        s:keypressed("left"); s:keypressed("left")
        assert.are.equal(s.team_size, #s.crew)
    end)

    it("Left/Right on OTHER fields does not change team_size", function()
        local s = fresh()
        local size = s.team_size
        s.focused = 1 -- mission_name
        s:keypressed("right"); s:keypressed("left")
        assert.are.equal(size, s.team_size)
    end)
end)

describe("NewMission difficulty cycle", function()
    -- difficulty is field index 2 in the new visual focus order.
    it("Left/Right cycles within [1..#difficulties], clamped", function()
        local s = fresh()
        s.focused = 2
        local idx = s.difficulty_idx
        s:keypressed("right"); assert.are.equal(math.min(#difficulties, idx + 1), s.difficulty_idx)
        s:keypressed("left"); assert.are.equal(idx, s.difficulty_idx)
        for _ = 1, 10 do s:keypressed("left") end
        assert.are.equal(1, s.difficulty_idx)
        for _ = 1, 10 do s:keypressed("right") end
        assert.are.equal(#difficulties, s.difficulty_idx)
    end)
end)

describe("NewMission Back / Charter actions", function()
    it("Enter on Back focus fires back", function()
        local s, calls = fresh()
        s.focused = 4
        s:keypressed("return")
        assert.are.equal(1, #calls)
        assert.are.equal("back", calls[1].name)
    end)

    it("Enter on Charter focus fires charter with {mission, crew}", function()
        local s, calls = fresh()
        s.focused = 5
        s:keypressed("return")
        assert.are.equal(1, #calls)
        assert.are.equal("charter", calls[1].name)
        local payload = calls[1].payload
        assert.is_table(payload.mission)
        assert.is_string(payload.mission.name)
        assert.are.equal("first_mission", payload.mission.difficulty)
        assert.are.equal(s.team_size, #payload.crew)
    end)

    it("kpenter also confirms a button", function()
        local s, calls = fresh()
        s.focused = 4
        s:keypressed("kpenter")
        assert.are.equal("back", calls[1].name)
    end)

    it("Enter on a non-button field does NOT fire either action", function()
        local s, calls = fresh()
        s.focused = 1
        s:keypressed("return")
        assert.are.equal(0, #calls)
    end)
end)

describe("difficulties pool", function()
    it("exposes exactly three presets in order Simulator / 1st Mission / Stellar", function()
        assert.are.equal(3, #difficulties)
        assert.are.equal("simulator", difficulties[1].key)
        assert.are.equal("first_mission", difficulties[2].key)
        assert.are.equal("stellar", difficulties[3].key)
    end)

    it("each preset has a label and a summary string", function()
        for _, d in ipairs(difficulties) do
            assert.is_string(d.label)
            assert.is_string(d.summary)
        end
    end)
end)
