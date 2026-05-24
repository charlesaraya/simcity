-- spec/systems/clock_spec.lua
-- The clock is a system (interval = one month) that advances the calendar and
-- publishes month_elapsed. Date is derived from the elapsed-month count.

local Clock = require("src.systems.clock")
local Runner = require("src.systems.runner")
local World = require("src.world.world")
local Bus = require("src.bus")
local C = require("src.world.constants")

describe("Clock", function()
    before_each(function() Bus.clear() end)

    it("system() ticks on a one-month interval", function()
        assert.are.equal(C.SIM.SECONDS_PER_MONTH, Clock.system().interval)
    end)

    it("each tick advances the month and publishes month_elapsed", function()
        local w = World.new(1)
        local months = 0
        Bus.subscribe(C.EVENTS.MONTH_ELAPSED, function() months = months + 1 end)
        local sys = Clock.system()
        sys.tick(w)
        sys.tick(w)
        assert.are.equal(2, w.clock.months)
        assert.are.equal(2, months)
    end)

    it("advances correctly when driven by the runner with a large dt", function()
        local w = World.new(1)
        local r = Runner.new()
        Runner.add(r, Clock.system())
        Runner.update(r, 13 * C.SIM.SECONDS_PER_MONTH, w) -- fast-forward 13 months
        assert.are.equal(13, w.clock.months)
    end)

    describe("date", function()
        it("starts at the configured year, month 1", function()
            local w = World.new(1)
            local year, month = Clock.date(w)
            assert.are.equal(C.SIM.START_YEAR, year)
            assert.are.equal(1, month)
        end)

        it("rolls into the next year after 12 months", function()
            local w = World.new(1)
            w.clock.months = 13
            local year, month = Clock.date(w)
            assert.are.equal(C.SIM.START_YEAR + 1, year)
            assert.are.equal(2, month)
        end)
    end)
end)
