-- src/systems/clock.lua
-- The simulation calendar, expressed as a system so it ticks through the runner
-- like everything else. Each tick is one month: it advances the elapsed-month
-- count in world state and publishes month_elapsed, which calendar-driven
-- features (HUD, future disasters, economy) can subscribe to.

local Bus = require("src.bus")
local C = require("src.world.constants")

local Clock = {}

-- Build the clock system. State lives in world.clock (so it serializes with the
-- world); the system itself is stateless beyond its accumulator.
function Clock.system()
    return {
        interval = C.SIM.SECONDS_PER_MONTH,
        accumulator = 0,
        tick = function(world)
            world.clock.months = world.clock.months + 1
            Bus.publish(C.EVENTS.MONTH_ELAPSED, { months = world.clock.months })
        end,
    }
end

-- Derive a (year, month) calendar date from the elapsed-month count.
-- month is 1-based within the year.
function Clock.date(world)
    local m = world.clock.months
    local year = C.SIM.START_YEAR + math.floor(m / C.SIM.MONTHS_PER_YEAR)
    local month = (m % C.SIM.MONTHS_PER_YEAR) + 1
    return year, month
end

return Clock
