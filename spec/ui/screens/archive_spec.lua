-- spec/ui/screens/archive_spec.lua
-- The Load from Archive screen lists saved missions and surfaces a Continue
-- action. Slot metadata is computed by main.lua (it reads the persistence
-- layer); the screen takes pre-built slot tables -- so the screen is pure
-- and headless-testable.
--
-- 4c-1 ships single-slot semantics (the existing F5 slot). The screen
-- handles 0 or N slot entries uniformly; 4c-2 will just pass more rows.

local Archive = require("src.ui.screens.archive")

local function actions_stub()
    local calls = {}
    return {
        back     = function() calls[#calls + 1] = { name = "back" } end,
        continue = function(slot) calls[#calls + 1] = { name = "continue", slot = slot } end,
    }, calls
end

local function slot(n, overrides)
    local s = {
        slot = n,
        mission_name = "Janus-IV",
        cycle = 3,
        population = 48,
        treasury = 1500,
        difficulty = "first_mission",
        world = { fake = true },
    }
    for k, v in pairs(overrides or {}) do s[k] = v end
    return s
end

describe("Archive.new", function()
    it("with no slots: selected = 0, marks the screen empty", function()
        local actions = actions_stub()
        local a = Archive.new({ slots = {}, actions = actions })
        assert.are.equal(0, a.selected)
        assert.is_true(a:is_empty())
    end)

    it("with one slot: selected = 1, not empty", function()
        local a = Archive.new({ slots = { slot(1) }, actions = actions_stub() })
        assert.are.equal(1, a.selected)
        assert.is_false(a:is_empty())
    end)

    it("with N slots: selected = 1 initially", function()
        local a = Archive.new({ slots = { slot(1), slot(2), slot(3) }, actions = actions_stub() })
        assert.are.equal(1, a.selected)
    end)
end)

describe("Archive keyboard nav", function()
    it("down/up clamp within [1..#slots]", function()
        local a = Archive.new({ slots = { slot(1), slot(2), slot(3) }, actions = actions_stub() })
        a:keypressed("down"); assert.are.equal(2, a.selected)
        a:keypressed("down"); assert.are.equal(3, a.selected)
        a:keypressed("down"); assert.are.equal(3, a.selected) -- clamped
        a:keypressed("up");   assert.are.equal(2, a.selected)
        a:keypressed("up");   assert.are.equal(1, a.selected)
        a:keypressed("up");   assert.are.equal(1, a.selected) -- clamped
    end)

    it("up/down are no-ops on an empty archive", function()
        local a = Archive.new({ slots = {}, actions = actions_stub() })
        a:keypressed("down"); a:keypressed("up")
        assert.are.equal(0, a.selected)
    end)

    it("Enter on a selected slot fires continue(slot)", function()
        local s = slot(1)
        local actions, calls = actions_stub()
        local a = Archive.new({ slots = { s }, actions = actions })
        a:keypressed("return")
        assert.are.equal(1, #calls)
        assert.are.equal("continue", calls[1].name)
        assert.are.same(s, calls[1].slot)
    end)

    it("Enter on an empty archive is a no-op", function()
        local actions, calls = actions_stub()
        local a = Archive.new({ slots = {}, actions = actions })
        a:keypressed("return")
        assert.are.equal(0, #calls)
    end)

    it("Esc fires back", function()
        local actions, calls = actions_stub()
        local a = Archive.new({ slots = { slot(1) }, actions = actions })
        a:keypressed("escape")
        assert.are.equal(1, #calls)
        assert.are.equal("back", calls[1].name)
    end)

    it("kpenter also confirms Continue", function()
        local actions, calls = actions_stub()
        local a = Archive.new({ slots = { slot(1) }, actions = actions })
        a:keypressed("kpenter")
        assert.are.equal("continue", calls[1].name)
    end)
end)

describe("Archive direct hotkeys", function()
    it("'b' fires back", function()
        local actions, calls = actions_stub()
        local a = Archive.new({ slots = { slot(1) }, actions = actions })
        a:keypressed("b")
        assert.are.equal("back", calls[1].name)
    end)

    it("'c' fires continue(slot) when non-empty", function()
        local s = slot(1)
        local actions, calls = actions_stub()
        local a = Archive.new({ slots = { s }, actions = actions })
        a:keypressed("c")
        assert.are.equal("continue", calls[1].name)
        assert.are.same(s, calls[1].slot)
    end)

    it("'c' is a no-op on empty archive", function()
        local actions, calls = actions_stub()
        local a = Archive.new({ slots = {}, actions = actions })
        a:keypressed("c")
        assert.are.equal(0, #calls)
    end)
end)

describe("Archive mouse", function()
    it("mousemoved over a visible slot row sets selected", function()
        local a = Archive.new({ slots = { slot(1), slot(2), slot(3) }, actions = actions_stub() })
        local _, y2 = a:row_center(2)
        a:mousemoved(100, y2)
        assert.are.equal(2, a.selected)
    end)

    it("left click on a slot row selects AND fires continue", function()
        local actions, calls = actions_stub()
        local a = Archive.new({ slots = { slot(1), slot(2) }, actions = actions })
        local _, y2 = a:row_center(2)
        a:mousepressed(100, y2, 1)
        assert.are.equal(2, a.selected)
        assert.are.equal("continue", calls[1].name)
        assert.are.equal(2, calls[1].slot.slot)
    end)

    it("mouse hover is a no-op on empty archive", function()
        local a = Archive.new({ slots = {}, actions = actions_stub() })
        a:mousemoved(100, 9999)
        assert.are.equal(0, a.selected)
    end)
end)

describe("Archive scroll (fixed-height panel)", function()
    -- The panel renders a fixed window of VISIBLE_ROWS rows. When the slot
    -- list exceeds it, navigation scrolls so the selected row stays visible.
    -- For 4c-1 single-slot reality this never engages; the test surface is
    -- the contract for 4c-2's multi-slot saves.

    local function many_slots(n)
        local s = {}
        for i = 1, n do s[i] = slot(i, { mission_name = ("M-%02d"):format(i) }) end
        return s
    end

    it("scroll_offset starts at 1", function()
        local a = Archive.new({ slots = many_slots(3), actions = actions_stub() })
        assert.are.equal(1, a.scroll_offset)
    end)

    it("navigating down past the visible window scrolls forward", function()
        local a = Archive.new({ slots = many_slots(20), actions = actions_stub() })
        local visible = a.VISIBLE_ROWS
        for _ = 1, visible do a:keypressed("down") end
        -- After moving 'visible' steps, selected has crossed the window edge,
        -- so scroll_offset advanced to keep selected on the last visible row.
        assert.is_true(a.scroll_offset > 1, "scroll_offset should have advanced; got " .. a.scroll_offset)
        assert.are.equal(a.selected, a.scroll_offset + visible - 1)
    end)

    it("navigating up past the window's top scrolls backward", function()
        local a = Archive.new({ slots = many_slots(20), actions = actions_stub() })
        local visible = a.VISIBLE_ROWS
        -- Jump near the end first, then walk back up.
        a.selected = 15
        a.scroll_offset = 15 - visible + 1
        for _ = 1, visible + 2 do a:keypressed("up") end
        assert.are.equal(a.selected, a.scroll_offset)
    end)

    it("with fewer slots than the window, scroll_offset stays 1", function()
        local a = Archive.new({ slots = many_slots(2), actions = actions_stub() })
        a:keypressed("down")
        assert.are.equal(1, a.scroll_offset)
    end)
end)
