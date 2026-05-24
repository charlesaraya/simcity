-- spec/systems/economy_spec.lua
-- The economy is a pure observer: each month it taxes occupants and pays upkeep
-- per building, moving world.treasury. It gates nothing. compute() is the pure
-- money rule, tested directly; the system tick is checked against a built city.

local Economy = require("src.systems.economy")
local World = require("src.world.world")
local Bus = require("src.bus")
local C = require("src.world.constants")

-- Zone, start, and complete a building in one call.
local function build(w, x, y, zone)
    World.zone_tile(w, x, y, zone)
    World.start_building(w, x, y)
    World.complete_building(w, x, y)
end

describe("Economy", function()
    before_each(function() Bus.clear() end)

    describe("compute", function()
        -- net = (pop + jobs) * TAX_RATE - buildings * UPKEEP
        it("nets occupant tax minus per-building upkeep", function()
            local expected = (100 + 50) * C.ECON.TAX_RATE - 10 * C.ECON.UPKEEP
            assert.are.equal(expected, Economy.compute(100, 50, 10))
        end)

        it("charges upkeep even with no occupants (net loss)", function()
            assert.are.equal(-5 * C.ECON.UPKEEP, Economy.compute(0, 0, 5))
            assert.is_true(Economy.compute(0, 0, 5) < 0)
        end)

        it("earns when occupant tax outweighs upkeep", function()
            assert.is_true(Economy.compute(100, 100, 1) > 0)
        end)
    end)

    describe("system", function()
        it("ticks monthly", function()
            assert.are.equal(C.SIM.SECONDS_PER_MONTH, Economy.system().interval)
        end)

        it("applies the monthly net to the treasury and records last_net", function()
            local w = World.new(1)
            build(w, 1, 1, C.ZONE.RESIDENTIAL) -- pop
            build(w, 2, 1, C.ZONE.INDUSTRIAL)  -- jobs
            local pop = World.population(w)
            local jobs = World.jobs(w)
            local n = World.building_count(w)
            local expected = Economy.compute(pop, jobs, n)

            local before = w.treasury
            Economy.system().tick(w)
            assert.are.equal(before + expected, w.treasury)
            assert.are.equal(expected, w.economy.last_net)
        end)

        it("lets the treasury go negative (no floor at zero)", function()
            -- A lone residential building's tax falls short of its upkeep under
            -- the first-pass constants, so a bedroom-only city bleeds.
            local w = World.new(1)
            w.treasury = 0
            build(w, 1, 1, C.ZONE.RESIDENTIAL)
            Economy.system().tick(w)
            assert.is_true(w.treasury < 0)
        end)
    end)
end)
