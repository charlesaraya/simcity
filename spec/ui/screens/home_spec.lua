-- spec/ui/screens/home_spec.lua
-- Home is the top-level menu surface: five rows (Continue Operations, New
-- Mission, Load from Archive, Operator Settings, End Transmission), keyboard
-- nav + mouse hover/click. Its draw is love-only (run-verified); everything
-- else — selection movement, action dispatch, hit-testing — is pure and
-- headless-testable. Actions are injected at construction so the screen has
-- no coupling to the manager (or to love).

local Home = require("src.ui.screens.home")

-- A bag of recorder callbacks for every Home option key.
local function actions_stub()
    local calls = {}
    local function rec(name)
        return function() calls[#calls + 1] = name end
    end
    return {
        continue         = rec("continue"),
        new_mission      = rec("new_mission"),
        archive          = rec("archive"),
        settings         = rec("settings"),
        end_transmission = rec("end_transmission"),
    }, calls
end

describe("Home.new", function()
    it("starts with the first row selected", function()
        local h = Home.new(actions_stub())
        assert.are.equal(1, h.selected)
    end)

    it("exposes the five options in the documented order", function()
        local h = Home.new(actions_stub())
        local keys = {}
        for _, opt in ipairs(h.options) do keys[#keys + 1] = opt.key end
        assert.are.same(
            { "continue", "new_mission", "archive", "settings", "end_transmission" },
            keys)
    end)

    it("each option has a label", function()
        local h = Home.new(actions_stub())
        for _, opt in ipairs(h.options) do
            assert.is_string(opt.label)
            assert.is_true(#opt.label > 0)
        end
    end)
end)

describe("Home keyboard nav", function()
    it("down increments the selection (clamped at the last row)", function()
        local h = Home.new(actions_stub())
        h:keypressed("down"); assert.are.equal(2, h.selected)
        h:keypressed("down"); assert.are.equal(3, h.selected)
        h:keypressed("down"); assert.are.equal(4, h.selected)
        h:keypressed("down"); assert.are.equal(5, h.selected)
        h:keypressed("down"); assert.are.equal(5, h.selected) -- clamped
    end)

    it("up decrements the selection (clamped at row 1)", function()
        local h = Home.new(actions_stub())
        h.selected = 3
        h:keypressed("up"); assert.are.equal(2, h.selected)
        h:keypressed("up"); assert.are.equal(1, h.selected)
        h:keypressed("up"); assert.are.equal(1, h.selected) -- clamped
    end)

    it("return fires the action for the currently selected option", function()
        local actions, calls = actions_stub()
        local h = Home.new(actions)
        h.selected = 2
        h:keypressed("return")
        assert.are.same({ "new_mission" }, calls)
    end)

    it("kpenter (numpad enter) also confirms", function()
        local actions, calls = actions_stub()
        local h = Home.new(actions)
        h:keypressed("kpenter")
        assert.are.same({ "continue" }, calls)
    end)

    it("escape from Home fires end_transmission (back-out at root = quit)", function()
        local actions, calls = actions_stub()
        local h = Home.new(actions)
        h:keypressed("escape")
        assert.are.same({ "end_transmission" }, calls)
    end)

    it("unhandled keys are a no-op (selection unchanged, no action fired)", function()
        local actions, calls = actions_stub()
        local h = Home.new(actions)
        h:keypressed("x")
        assert.are.equal(1, h.selected)
        assert.are.equal(0, #calls)
    end)
end)

describe("Home mouse", function()
    it("mousemoved over a row sets selected to that row", function()
        local h = Home.new(actions_stub())
        local _, y3 = h:row_center(3)
        h:mousemoved(100, y3)
        assert.are.equal(3, h.selected)
    end)

    it("mousemoved outside any row leaves selected unchanged", function()
        local h = Home.new(actions_stub())
        h.selected = 2
        h:mousemoved(-9999, -9999) -- well outside
        assert.are.equal(2, h.selected)
    end)

    it("left click on a row selects it AND fires its action", function()
        local actions, calls = actions_stub()
        local h = Home.new(actions)
        local _, y4 = h:row_center(4)
        h:mousepressed(100, y4, 1)
        assert.are.equal(4, h.selected)
        assert.are.same({ "settings" }, calls)
    end)

    it("right click on a row is a no-op (no action, no selection change)", function()
        local actions, calls = actions_stub()
        local h = Home.new(actions)
        h.selected = 1
        local _, y3 = h:row_center(3)
        h:mousepressed(100, y3, 2)
        assert.are.equal(1, h.selected)
        assert.are.equal(0, #calls)
    end)

    it("left click outside any row is a no-op", function()
        local actions, calls = actions_stub()
        local h = Home.new(actions)
        h:mousepressed(-9999, -9999, 1)
        assert.are.equal(0, #calls)
    end)
end)

describe("Home.row_at (pure hit-test)", function()
    it("returns nil for points above the first row", function()
        local h = Home.new(actions_stub())
        local y1_top = select(2, h:row_center(1)) - 9999
        assert.is_nil(h:row_at(100, y1_top))
    end)

    it("returns the row index for a y-coordinate inside that row", function()
        local h = Home.new(actions_stub())
        for i = 1, #h.options do
            local _, y = h:row_center(i)
            assert.are.equal(i, h:row_at(100, y))
        end
    end)
end)
