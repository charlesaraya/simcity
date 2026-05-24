-- spec/bus_spec.lua
-- The event bus is the heart of Principle 4: systems talk through events, never
-- direct references. These tests pin down its contract before it exists (RED).

local Bus = require("src.bus")

describe("Bus", function()
    before_each(function()
        Bus.clear() -- each test starts with no subscribers
    end)

    it("calls a subscribed handler when its event is published", function()
        local got
        Bus.subscribe("ping", function(data) got = data end)
        Bus.publish("ping", 42)
        assert.are.equal(42, got)
    end)

    it("passes the published payload through to the handler", function()
        local seen
        Bus.subscribe("tile_zoned", function(data) seen = data end)
        Bus.publish("tile_zoned", { x = 3, y = 4, zone = "residential" })
        assert.are.same({ x = 3, y = 4, zone = "residential" }, seen)
    end)

    it("calls multiple handlers in subscription order", function()
        local order = {}
        Bus.subscribe("ev", function() order[#order + 1] = "first" end)
        Bus.subscribe("ev", function() order[#order + 1] = "second" end)
        Bus.publish("ev")
        assert.are.same({ "first", "second" }, order)
    end)

    it("only calls handlers for the published event", function()
        local a_calls, b_calls = 0, 0
        Bus.subscribe("a", function() a_calls = a_calls + 1 end)
        Bus.subscribe("b", function() b_calls = b_calls + 1 end)
        Bus.publish("a")
        assert.are.equal(1, a_calls)
        assert.are.equal(0, b_calls)
    end)

    it("treats publishing an event with no subscribers as a no-op", function()
        assert.has_no.errors(function() Bus.publish("nobody_listening", 1) end)
    end)

    it("clear() removes all subscribers", function()
        local calls = 0
        Bus.subscribe("ev", function() calls = calls + 1 end)
        Bus.clear()
        Bus.publish("ev")
        assert.are.equal(0, calls)
    end)
end)
