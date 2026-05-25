-- spec/systems/economy_spec.lua
-- The economy is a pure observer: each month it taxes jobs (commerce + industry
-- are where economic activity happens) and pays flat upkeep on every building.
-- Residential earns nothing yet costs upkeep, so housing is a net liability the
-- jobs it shelters must pay for. compute() is the pure money rule; the system
-- tick is checked against built cities. The economy gates nothing.

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
        -- net = jobs * TAX_RATE - buildings * UPKEEP
        it("nets job tax minus per-building upkeep", function()
            local expected = 50 * C.ECON.TAX_RATE - 10 * C.ECON.UPKEEP
            assert.are.equal(expected, Economy.compute(50, 10))
        end)

        it("makes a jobless building a pure cost (residential)", function()
            assert.are.equal(-C.ECON.UPKEEP, Economy.compute(0, 1))
            assert.is_true(Economy.compute(0, 1) < 0)
        end)

        it("makes a commercial building earn after upkeep", function()
            -- one completed commercial building = JOBS_PER_COM jobs, 1 building
            assert.is_true(Economy.compute(C.JOBS_PER_COM, 1) > 0)
        end)

        it("makes industry earn more per building than commerce", function()
            local com = Economy.compute(C.JOBS_PER_COM, 1)
            local ind = Economy.compute(C.JOBS_PER_IND, 1)
            assert.is_true(ind > com)
        end)
    end)

    describe("system", function()
        it("ticks monthly", function()
            assert.are.equal(C.SIM.SECONDS_PER_MONTH, Economy.system().interval)
        end)

        it("applies the monthly net to the treasury and records last_net", function()
            local w = World.new(1)
            build(w, 1, 1, C.ZONE.COMMERCIAL)
            build(w, 2, 1, C.ZONE.INDUSTRIAL)
            local expected = Economy.compute(World.jobs(w), World.building_count(w))

            local before = w.treasury
            Economy.system().tick(w)
            assert.are.equal(before + expected, w.treasury)
            assert.are.equal(expected, w.economy.last_net)
        end)

        it("bleeds a residential-only city", function()
            local w = World.new(1)
            build(w, 1, 1, C.ZONE.RESIDENTIAL)
            build(w, 2, 1, C.ZONE.RESIDENTIAL)
            local before = w.treasury
            Economy.system().tick(w)
            assert.is_true(w.treasury < before)
        end)

        it("holds a balanced residential/commercial city steady", function()
            -- Two res + two com: commerce's job tax should exactly cover all four
            -- buildings' upkeep. Derive the expectation from compute so this stays
            -- honest if the constants are retuned -- the point is "balanced nets
            -- whatever compute says", and under the first-pass tuning that's zero.
            local w = World.new(1)
            build(w, 1, 1, C.ZONE.RESIDENTIAL)
            build(w, 2, 1, C.ZONE.RESIDENTIAL)
            build(w, 3, 1, C.ZONE.COMMERCIAL)
            build(w, 4, 1, C.ZONE.COMMERCIAL)
            local expected = Economy.compute(World.jobs(w), World.building_count(w))
            local before = w.treasury
            Economy.system().tick(w)
            assert.are.equal(before + expected, w.treasury)
            assert.are.equal(0, expected) -- first-pass tuning: commerce funds the housing
        end)

        it("lifts the treasury once industry is added", function()
            local w = World.new(1)
            build(w, 1, 1, C.ZONE.INDUSTRIAL)
            local before = w.treasury
            Economy.system().tick(w)
            assert.is_true(w.treasury > before)
        end)

        it("does not floor the treasury at zero (debt persists)", function()
            -- The economy gates nothing, so debt is allowed: a tick applies its
            -- net without clamping. An empty city nets 0, so a pre-existing
            -- deficit must survive the tick unchanged -- proof there's no floor.
            local w = World.new(1)
            w.treasury = -50
            Economy.system().tick(w)
            assert.are.equal(-50, w.treasury)
        end)
    end)

    describe("budget", function()
        -- A read-only forecast for the HUD: recurring income/expense for the
        -- current city. net must agree with compute (single source of formula).
        it("reports zero for an empty city", function()
            local w = World.new(1)
            local b = Economy.budget(w)
            assert.are.same({ income = 0, expense = 0, net = 0 }, b)
        end)

        it("income = job tax, expense = per-building upkeep, net = income - expense", function()
            local w = World.new(1)
            build(w, 1, 1, C.ZONE.COMMERCIAL)  -- jobs, 1 building
            build(w, 2, 1, C.ZONE.RESIDENTIAL) -- no jobs, 1 building
            local b = Economy.budget(w)
            assert.are.equal(World.jobs(w) * C.ECON.TAX_RATE, b.income)
            assert.are.equal(World.building_count(w) * C.ECON.UPKEEP, b.expense)
            assert.are.equal(b.income - b.expense, b.net)
            assert.are.equal(Economy.compute(World.jobs(w), World.building_count(w)), b.net)
        end)
    end)

    describe("install (zoning expense)", function()
        it("debits the per-zone cost when a tile is zoned", function()
            local w = World.new(1)
            Economy.install(w)
            local before = w.treasury
            World.zone_tile(w, 2, 2, C.ZONE.RESIDENTIAL)
            assert.are.equal(before - C.ZONE_COST[C.ZONE.RESIDENTIAL], w.treasury)
        end)

        it("charges each zone its own cost (reads the event's zone)", function()
            local w = World.new(1)
            Economy.install(w)
            local before = w.treasury
            World.zone_tile(w, 2, 2, C.ZONE.COMMERCIAL)
            World.zone_tile(w, 3, 2, C.ZONE.INDUSTRIAL)
            local expected = before - C.ZONE_COST[C.ZONE.COMMERCIAL] - C.ZONE_COST[C.ZONE.INDUSTRIAL]
            assert.are.equal(expected, w.treasury)
        end)

        it("does not re-charge an idempotent re-zone (no event, no debit)", function()
            local w = World.new(1)
            Economy.install(w)
            World.zone_tile(w, 2, 2, C.ZONE.RESIDENTIAL)
            local after_first = w.treasury
            World.zone_tile(w, 2, 2, C.ZONE.RESIDENTIAL) -- same zone: no-op, no event
            assert.are.equal(after_first, w.treasury)
        end)
    end)

    describe("install (road expense)", function()
        it("debits exactly ROAD.COST when a road is built", function()
            local w = World.new(1)
            Economy.install(w)
            local before = w.treasury
            World.build_road(w, 2, 2)
            assert.are.equal(before - C.ROAD.COST, w.treasury)
        end)

        it("debits once per road built", function()
            local w = World.new(1)
            Economy.install(w)
            local before = w.treasury
            World.build_road(w, 2, 2)
            World.build_road(w, 3, 2)
            assert.are.equal(before - 2 * C.ROAD.COST, w.treasury)
        end)

        it("leaves the monthly tick income unchanged", function()
            local w = World.new(1)
            Economy.install(w)
            build(w, 1, 1, C.ZONE.INDUSTRIAL)
            local expected = Economy.compute(World.jobs(w), World.building_count(w))
            local before = w.treasury
            Economy.system().tick(w)
            assert.are.equal(before + expected, w.treasury)
        end)
    end)
end)
