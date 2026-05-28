-- spec/ui/screens/pause_modal_spec.lua
-- Pause modal: in-game overlay with five options (Resume Operation, Save to
-- Archive, Load from Archive, Mission Control, End Transmission). Same
-- structural shape as Home — selection, action dispatch, keyboard + mouse —
-- but Esc means RESUME here, not quit. Actions are injected at construction,
-- so the modal is fully decoupled from the manager and from love.

local PauseModal = require("src.ui.screens.pause_modal")

local function actions_stub()
    local calls = {}
    local function rec(name)
        return function() calls[#calls + 1] = name end
    end
    return {
        resume             = rec("resume"),
        save_to_archive    = rec("save_to_archive"),
        load_from_archive  = rec("load_from_archive"),
        mission_control    = rec("mission_control"),
        end_transmission   = rec("end_transmission"),
    }, calls
end

describe("PauseModal.new", function()
    it("starts with the first row (Resume Operation) selected", function()
        local m = PauseModal.new(actions_stub())
        assert.are.equal(1, m.selected)
    end)

    it("exposes the five options in the documented order", function()
        local m = PauseModal.new(actions_stub())
        local keys = {}
        for _, opt in ipairs(m.options) do keys[#keys + 1] = opt.key end
        assert.are.same(
            { "resume", "save_to_archive", "load_from_archive",
              "mission_control", "end_transmission" },
            keys)
    end)
end)

describe("PauseModal keyboard nav", function()
    it("down/up clamp at the ends, same as Home", function()
        local m = PauseModal.new(actions_stub())
        for _ = 1, 6 do m:keypressed("down") end
        assert.are.equal(5, m.selected)
        for _ = 1, 6 do m:keypressed("up") end
        assert.are.equal(1, m.selected)
    end)

    it("return fires the action for the selected option", function()
        local actions, calls = actions_stub()
        local m = PauseModal.new(actions)
        m.selected = 2
        m:keypressed("return")
        assert.are.same({ "save_to_archive" }, calls)
    end)

    it("kpenter also confirms", function()
        local actions, calls = actions_stub()
        local m = PauseModal.new(actions)
        m:keypressed("kpenter")
        assert.are.same({ "resume" }, calls)
    end)

    it("escape fires RESUME (modal-close), NOT end_transmission", function()
        local actions, calls = actions_stub()
        local m = PauseModal.new(actions)
        m:keypressed("escape")
        assert.are.same({ "resume" }, calls)
    end)

    it("unhandled keys are a no-op", function()
        local actions, calls = actions_stub()
        local m = PauseModal.new(actions)
        m:keypressed("x")
        assert.are.equal(1, m.selected)
        assert.are.equal(0, #calls)
    end)
end)

describe("PauseModal direct hotkeys", function()
    local HOTKEYS = {
        { hotkey = "r", key = "resume",            index = 1 },
        { hotkey = "s", key = "save_to_archive",   index = 2 },
        { hotkey = "l", key = "load_from_archive", index = 3 },
        { hotkey = "m", key = "mission_control",   index = 4 },
        { hotkey = "q", key = "end_transmission",  index = 5 },
    }

    for _, spec in ipairs(HOTKEYS) do
        it(("%q fires %s from any focus"):format(spec.hotkey, spec.key), function()
            local actions, calls = actions_stub()
            local m = PauseModal.new(actions)
            m.selected = 1
            m:keypressed(spec.hotkey)
            assert.are.same({ spec.key }, calls)
            assert.are.equal(spec.index, m.selected)
        end)
    end

    it("every option exposes a single-letter hotkey", function()
        local m = PauseModal.new(actions_stub())
        for _, opt in ipairs(m.options) do
            assert.is_string(opt.hotkey)
            assert.are.equal(1, #opt.hotkey)
        end
    end)
end)

describe("PauseModal mouse", function()
    it("mousemoved over a row sets selected", function()
        local m = PauseModal.new(actions_stub())
        local _, y3 = m:row_center(3)
        m:mousemoved(100, y3)
        assert.are.equal(3, m.selected)
    end)

    it("left click on a row selects AND fires its action", function()
        local actions, calls = actions_stub()
        local m = PauseModal.new(actions)
        local _, y5 = m:row_center(5)
        m:mousepressed(100, y5, 1)
        assert.are.equal(5, m.selected)
        assert.are.same({ "end_transmission" }, calls)
    end)

    it("right click is a no-op", function()
        local actions, calls = actions_stub()
        local m = PauseModal.new(actions)
        local _, y2 = m:row_center(2)
        m:mousepressed(100, y2, 2)
        assert.are.equal(0, #calls)
    end)

    it("click outside any row is a no-op", function()
        local actions, calls = actions_stub()
        local m = PauseModal.new(actions)
        m:mousepressed(-9999, -9999, 1)
        assert.are.equal(0, #calls)
    end)
end)
