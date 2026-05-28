-- spec/ui/screens/settings_spec.lua
-- Operator Settings is a stub in 4c-1: the screen exists so the Home nav is
-- complete, but its only behavior is Back. Content (window mode, audio,
-- key remap, save management) lands later.

local Settings = require("src.ui.screens.settings")

local function actions_stub()
    local calls = {}
    return { back = function() calls[#calls + 1] = "back" end }, calls
end

describe("Settings", function()
    it("Esc fires back", function()
        local actions, calls = actions_stub()
        local s = Settings.new(actions)
        s:keypressed("escape")
        assert.are.same({ "back" }, calls)
    end)

    it("'b' fires back", function()
        local actions, calls = actions_stub()
        local s = Settings.new(actions)
        s:keypressed("b")
        assert.are.same({ "back" }, calls)
    end)

    it("other keys are a no-op", function()
        local actions, calls = actions_stub()
        local s = Settings.new(actions)
        s:keypressed("a"); s:keypressed("return"); s:keypressed("up")
        assert.are.equal(0, #calls)
    end)
end)
