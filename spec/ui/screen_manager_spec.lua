-- spec/ui/screen_manager_spec.lua
-- The screen state machine owns: which menu screen is current, the modal stack
-- (Pause modal pushes here), an in_game flag for the running mission, and the
-- dispatch order. It's a pure module, headless-testable: handlers are stub
-- tables that record calls. The manager itself never touches love.
--
-- The sim-tick gate: when in_game is true AND the modal stack is empty, the
-- runner ticks. Any open modal (or being on a menu screen) pauses the sim.

local ScreenManager = require("src.ui.screen_manager")

-- A tiny screen stub that records its callback hits in call order. Manager is
-- supposed to invoke methods with method-call syntax (screen:method(args)), so
-- the stub's recorded args drop self.
local function screen_stub()
    local s = { hits = {} }
    local function record(name)
        return function(self, ...)
            s.hits[#s.hits + 1] = { name = name, args = { ... } }
        end
    end
    s.update         = record("update")
    s.draw           = record("draw")
    s.keypressed     = record("keypressed")
    s.mousepressed   = record("mousepressed")
    s.mousereleased  = record("mousereleased")
    s.wheelmoved     = record("wheelmoved")
    return s
end

describe("ScreenManager.new", function()
    it("returns a fresh manager with empty state", function()
        local mgr = ScreenManager.new()
        assert.is_nil(mgr:current_id())
        assert.are.equal(0, mgr:modal_count())
        assert.is_false(mgr.in_game)
    end)

    it("yields independent instances (no shared state across managers)", function()
        local a, b = ScreenManager.new(), ScreenManager.new()
        a:register("home", screen_stub())
        a:set_current("home")
        assert.is_nil(b:current_id())
    end)
end)

describe("ScreenManager.register / set_current", function()
    it("set_current updates current_id when the id is registered", function()
        local mgr = ScreenManager.new()
        mgr:register("home", screen_stub())
        mgr:set_current("home")
        assert.are.equal("home", mgr:current_id())
    end)

    it("set_current with an unregistered id errors loudly", function()
        local mgr = ScreenManager.new()
        assert.has_error(function() mgr:set_current("nope") end)
    end)

    it("register replaces an existing screen under the same id", function()
        local mgr = ScreenManager.new()
        local s1, s2 = screen_stub(), screen_stub()
        mgr:register("home", s1)
        mgr:register("home", s2)
        mgr:set_current("home")
        mgr:keypressed("space")
        assert.are.equal(0, #s1.hits)
        assert.are.equal(1, #s2.hits)
    end)
end)

describe("ScreenManager modal stack", function()
    it("push_modal grows the stack; pop_modal shrinks it", function()
        local mgr = ScreenManager.new()
        mgr:register("pause", screen_stub())
        mgr:push_modal("pause")
        assert.are.equal(1, mgr:modal_count())
        mgr:pop_modal()
        assert.are.equal(0, mgr:modal_count())
    end)

    it("push_modal with an unregistered id errors", function()
        local mgr = ScreenManager.new()
        assert.has_error(function() mgr:push_modal("nope") end)
    end)

    it("pop_modal on an empty stack is a no-op (no error)", function()
        local mgr = ScreenManager.new()
        assert.has_no.errors(function() mgr:pop_modal() end)
        assert.are.equal(0, mgr:modal_count())
    end)

    it("stacks multiple modals; pop returns to the previous one", function()
        local mgr = ScreenManager.new()
        local outer, inner = screen_stub(), screen_stub()
        mgr:register("outer", outer)
        mgr:register("inner", inner)
        mgr:push_modal("outer")
        mgr:push_modal("inner")
        mgr:keypressed("a") -- routed to top (inner)
        assert.are.equal(1, #inner.hits)
        assert.are.equal(0, #outer.hits)
        mgr:pop_modal()
        mgr:keypressed("b") -- now routed to outer
        assert.are.equal(1, #outer.hits)
        assert.are.equal(1, #inner.hits)
    end)
end)

describe("ScreenManager.should_tick (sim-tick gate)", function()
    it("is false when in_game is false (on a menu screen)", function()
        local mgr = ScreenManager.new()
        mgr.in_game = false
        assert.is_false(mgr:should_tick())
    end)

    it("is true when in_game is true and no modal is open", function()
        local mgr = ScreenManager.new()
        mgr.in_game = true
        assert.is_true(mgr:should_tick())
    end)

    it("is false when in_game is true but a modal is on the stack", function()
        local mgr = ScreenManager.new()
        mgr:register("pause", screen_stub())
        mgr.in_game = true
        mgr:push_modal("pause")
        assert.is_false(mgr:should_tick())
    end)
end)

describe("ScreenManager dispatch (update / input)", function()
    it("routes update/key/mouse to current screen when no modal is open", function()
        local mgr = ScreenManager.new()
        local home = screen_stub()
        mgr:register("home", home)
        mgr:set_current("home")
        mgr:update(0.016)
        mgr:keypressed("up")
        mgr:mousepressed(10, 20, 1)
        mgr:mousereleased(10, 20, 1)
        mgr:wheelmoved(0, 1)
        local names = {}
        for _, h in ipairs(home.hits) do names[#names + 1] = h.name end
        assert.are.same(
            { "update", "keypressed", "mousepressed", "mousereleased", "wheelmoved" },
            names)
    end)

    it("routes to the top modal only when one is open (current is NOT called)", function()
        local mgr = ScreenManager.new()
        local home, pause = screen_stub(), screen_stub()
        mgr:register("home", home)
        mgr:register("pause", pause)
        mgr:set_current("home")
        mgr:push_modal("pause")
        mgr:update(0.016)
        mgr:keypressed("esc")
        assert.are.equal(0, #home.hits)
        assert.are.equal(2, #pause.hits)
    end)

    it("is a no-op when there is no current screen and no modal", function()
        local mgr = ScreenManager.new()
        assert.has_no.errors(function()
            mgr:update(0.016)
            mgr:keypressed("a")
            mgr:mousepressed(0, 0, 1)
            mgr:mousereleased(0, 0, 1)
            mgr:wheelmoved(0, 0)
        end)
    end)

    it("forwards dt to update with method-call semantics (self dropped)", function()
        local mgr = ScreenManager.new()
        local s = screen_stub()
        mgr:register("x", s)
        mgr:set_current("x")
        mgr:update(0.5)
        assert.are.same({ 0.5 }, s.hits[1].args)
    end)

    it("tolerates screens missing a callback (no crash)", function()
        local mgr = ScreenManager.new()
        local sparse = {} -- no methods at all
        mgr:register("sparse", sparse)
        mgr:set_current("sparse")
        assert.has_no.errors(function()
            mgr:update(0.016)
            mgr:keypressed("a")
            mgr:mousepressed(0, 0, 1)
            mgr:mousereleased(0, 0, 1)
            mgr:wheelmoved(0, 0)
        end)
    end)
end)

describe("ScreenManager.draw (layered, modals over current)", function()
    it("draws the current screen, then each modal in stack order", function()
        local mgr = ScreenManager.new()
        local order = {}
        local function recorder(tag)
            return { draw = function() order[#order + 1] = tag end }
        end
        mgr:register("home", recorder("home"))
        mgr:register("outer", recorder("outer"))
        mgr:register("inner", recorder("inner"))
        mgr:set_current("home")
        mgr:push_modal("outer")
        mgr:push_modal("inner")
        mgr:draw()
        assert.are.same({ "home", "outer", "inner" }, order)
    end)

    it("when in_game is true and the current screen is nil, only modals draw", function()
        local mgr = ScreenManager.new()
        local order = {}
        mgr:register("pause", { draw = function() order[#order + 1] = "pause" end })
        mgr.in_game = true
        mgr:push_modal("pause")
        mgr:draw()
        assert.are.same({ "pause" }, order)
    end)

    it("draws nothing when there is no current screen and no modal", function()
        local mgr = ScreenManager.new()
        assert.has_no.errors(function() mgr:draw() end)
    end)
end)
