-- spec/ui/screens/confirm_modal_spec.lua
-- A generic 3-button confirm dialog: Yes / No / Cancel. Used in 4c-2 for
-- save-before-abandoning prompts (End Transmission, Mission Control's
-- Return to Home). Actions are injected; the screen has no coupling to
-- the persistence layer.

local ConfirmModal = require("src.ui.screens.confirm_modal")

local function actions_stub()
    local calls = {}
    return {
        yes    = function() calls[#calls + 1] = "yes" end,
        no     = function() calls[#calls + 1] = "no" end,
        cancel = function() calls[#calls + 1] = "cancel" end,
    }, calls
end

local function fresh()
    local actions, calls = actions_stub()
    return ConfirmModal.new({
        title = "Save first?",
        body  = "Unsaved progress will be lost.",
        actions = actions,
    }), calls
end

describe("ConfirmModal.new", function()
    it("starts with Yes selected (index 1 of 3)", function()
        local m = fresh()
        assert.are.equal(1, m.selected)
    end)

    it("exposes title and body", function()
        local m = fresh()
        assert.are.equal("Save first?", m.title)
        assert.are.equal("Unsaved progress will be lost.", m.body)
    end)
end)

describe("ConfirmModal keyboard", function()
    it("Enter on default focus fires yes", function()
        local m, calls = fresh()
        m:keypressed("return")
        assert.are.same({ "yes" }, calls)
    end)

    it("left/right move selection clamped within 1..3", function()
        local m = fresh()
        m:keypressed("right"); assert.are.equal(2, m.selected)
        m:keypressed("right"); assert.are.equal(3, m.selected)
        m:keypressed("right"); assert.are.equal(3, m.selected) -- clamped
        m:keypressed("left");  assert.are.equal(2, m.selected)
        m:keypressed("left");  assert.are.equal(1, m.selected)
        m:keypressed("left");  assert.are.equal(1, m.selected) -- clamped
    end)

    it("Esc fires cancel", function()
        local m, calls = fresh()
        m:keypressed("escape")
        assert.are.same({ "cancel" }, calls)
    end)

    it("hotkeys Y / N / C fire yes / no / cancel from any focus", function()
        for _, spec in ipairs({
            { key = "y", action = "yes" },
            { key = "n", action = "no" },
            { key = "c", action = "cancel" },
        }) do
            local m, calls = fresh()
            m:keypressed(spec.key)
            assert.are.same({ spec.action }, calls)
        end
    end)

    it("Enter on No or Cancel focus fires that action", function()
        local m, calls = fresh()
        m.selected = 2; m:keypressed("return")
        assert.are.equal("no", calls[#calls])
        m.selected = 3; m:keypressed("return")
        assert.are.equal("cancel", calls[#calls])
    end)
end)

describe("ConfirmModal mouse", function()
    it("left click on a button fires its action", function()
        local m, calls = fresh()
        local x, y = m:row_center(2)
        m:mousepressed(x, y, 1)
        assert.are.same({ "no" }, calls)
    end)

    it("right click is a no-op", function()
        local m, calls = fresh()
        local x, y = m:row_center(1)
        m:mousepressed(x, y, 2)
        assert.are.equal(0, #calls)
    end)
end)
