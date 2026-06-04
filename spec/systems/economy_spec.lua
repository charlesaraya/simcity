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

        it("makes an upkept building with no job tax a pure cost", function()
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

        it("charges fuel upkeep per plant", function()
            assert.are.equal(-C.PLANT.UPKEEP, Economy.compute(0, 0, 1))
            local expected = 10 * C.ECON.TAX_RATE - 2 * C.ECON.UPKEEP - 3 * C.PLANT.UPKEEP
            assert.are.equal(expected, Economy.compute(10, 2, 3))
        end)

        it("treats plants as zero when the arg is omitted (back-compat)", function()
            assert.are.equal(Economy.compute(50, 10), Economy.compute(50, 10, 0))
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
            local expected = Economy.compute(World.jobs(w), World.business_count(w))

            local before = w.treasury
            Economy.system().tick(w)
            assert.are.equal(before + expected, w.treasury)
            assert.are.equal(expected, w.economy.last_net)
        end)

        it("leaves a residential-only city budget-neutral (housing is free)", function()
            local w = World.new(1)
            build(w, 1, 1, C.ZONE.RESIDENTIAL)
            build(w, 2, 1, C.ZONE.RESIDENTIAL)
            local before = w.treasury
            Economy.system().tick(w)
            assert.are.equal(before, w.treasury) -- residents earn nothing and cost nothing
        end)

        it("turns a profit on commerce, with residents free", function()
            -- Two res (free) + two com: only the commercial buildings carry upkeep,
            -- and their job tax outweighs it, so the city nets positive. Derive from
            -- compute over the BUSINESS count so it tracks any later retune.
            local w = World.new(1)
            build(w, 1, 1, C.ZONE.RESIDENTIAL)
            build(w, 2, 1, C.ZONE.RESIDENTIAL)
            build(w, 3, 1, C.ZONE.COMMERCIAL)
            build(w, 4, 1, C.ZONE.COMMERCIAL)
            local expected = Economy.compute(World.jobs(w), World.business_count(w))
            local before = w.treasury
            Economy.system().tick(w)
            assert.are.equal(before + expected, w.treasury)
            assert.is_true(expected > 0) -- commerce funds itself and then some
        end)

        it("lifts the treasury once industry is added", function()
            local w = World.new(1)
            build(w, 1, 1, C.ZONE.INDUSTRIAL)
            local before = w.treasury
            Economy.system().tick(w)
            assert.is_true(w.treasury > before)
        end)

        it("burns monthly fuel for each plant", function()
            local w = World.new(1)
            World.build_plant(w, 5, 5) -- a plant, no buildings: pure fuel cost
            local expected = Economy.compute(World.jobs(w), World.business_count(w), World.plant_count(w))
            local before = w.treasury
            Economy.system().tick(w)
            assert.are.equal(before + expected, w.treasury)
            assert.are.equal(before - C.PLANT.UPKEEP, w.treasury) -- 1 plant, nothing else
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

        it("income = job tax, expense = business upkeep (residents free), net = income - expense", function()
            local w = World.new(1)
            build(w, 1, 1, C.ZONE.COMMERCIAL)  -- jobs + upkeep
            build(w, 2, 1, C.ZONE.RESIDENTIAL) -- free: no jobs, no upkeep
            local b = Economy.budget(w)
            assert.are.equal(World.jobs(w) * C.ECON.TAX_RATE, b.income)
            assert.are.equal(World.business_count(w) * C.ECON.UPKEEP, b.expense)
            assert.are.equal(C.ECON.UPKEEP, b.expense) -- the commercial building only, not the res
            assert.are.equal(b.income - b.expense, b.net)
            assert.are.equal(Economy.compute(World.jobs(w), World.business_count(w)), b.net)
        end)

        it("charges no upkeep for residential buildings", function()
            local w = World.new(1)
            build(w, 1, 1, C.ZONE.RESIDENTIAL)
            build(w, 2, 1, C.ZONE.RESIDENTIAL)
            assert.are.equal(0, Economy.budget(w).expense)
        end)

        it("folds plant fuel into the monthly expense", function()
            local w = World.new(1)
            World.build_plant(w, 5, 5) -- one plant, no buildings
            local b = Economy.budget(w)
            assert.are.equal(C.PLANT.UPKEEP, b.expense)
            assert.are.equal(-C.PLANT.UPKEEP, b.net)
            assert.are.equal(Economy.compute(World.jobs(w), World.building_count(w), World.plant_count(w)), b.net)
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
            local expected = Economy.compute(World.jobs(w), World.business_count(w))
            local before = w.treasury
            Economy.system().tick(w)
            assert.are.equal(before + expected, w.treasury)
        end)
    end)

    describe("install (mine expense)", function()
        it("debits IRON_MINE.COST when a mine is built", function()
            local w = World.new(1)
            Economy.install(w)
            local deposits = World.deposit_tiles(w)
            local before = w.treasury
            World.build_mine(w, deposits[1].x, deposits[1].y)
            assert.are.equal(before - C.IRON_MINE.COST, w.treasury)
        end)

        it("debits RAIL.COST per rail tile built", function()
            local w = World.new(1)
            Economy.install(w)
            local before = w.treasury
            World.build_rail(w, 5, 5)
            World.build_rail(w, 6, 5)
            assert.are.equal(before - 2 * C.RAIL.COST, w.treasury)
        end)

        it("debits FREIGHT_STATION.COST when a station is built", function()
            local w = World.new(1)
            Economy.install(w)
            local before = w.treasury
            World.build_station(w, 10, 10)
            assert.are.equal(before - C.FREIGHT_STATION.COST, w.treasury)
        end)
    end)

    describe("install (power expense)", function()
        it("debits PLANT.COST when a plant is built", function()
            local w = World.new(1)
            Economy.install(w)
            local before = w.treasury
            World.build_plant(w, 2, 2)
            assert.are.equal(before - C.PLANT.COST, w.treasury)
        end)

        it("debits POWER_LINE.COST when a power line is built", function()
            local w = World.new(1)
            Economy.install(w)
            local before = w.treasury
            World.build_power_line(w, 2, 2)
            assert.are.equal(before - C.POWER_LINE.COST, w.treasury)
        end)

        it("debits once per power line built", function()
            local w = World.new(1)
            Economy.install(w)
            local before = w.treasury
            World.build_power_line(w, 2, 2)
            World.build_power_line(w, 3, 2)
            assert.are.equal(before - 2 * C.POWER_LINE.COST, w.treasury)
        end)
    end)

    describe("farm upkeep", function()
        local function build_agri(w, x, y)
            World.zone_tile(w, x, y, C.ZONE.AGRICULTURAL)
            World.start_building(w, x, y)
            World.complete_building(w, x, y)
        end

        it("charges farm upkeep in compute", function()
            assert.are.equal(-C.FARM.UPKEEP, Economy.compute(0, 0, 0, 0, 1))
            local expected = 10 * C.ECON.TAX_RATE - 2 * C.ECON.UPKEEP - 2 * C.FARM.UPKEEP
            assert.are.equal(expected, Economy.compute(10, 2, 0, 0, 2))
        end)

        it("folds farm upkeep into monthly expense in budget", function()
            local w = World.new(1)
            build_agri(w, 30, 30)
            local b = Economy.budget(w)
            assert.are.equal(C.FARM.UPKEEP, b.expense)
            assert.are.equal(-C.FARM.UPKEEP, b.net)
        end)

        it("burns monthly upkeep for each completed farm in system tick", function()
            local w = World.new(1)
            build_agri(w, 30, 30)
            local expected = Economy.compute(
                World.jobs(w), World.business_count(w),
                World.plant_count(w), World.mine_count(w), World.farm_count(w))
            local before = w.treasury
            Economy.system().tick(w)
            assert.are.equal(before + expected, w.treasury)
            assert.are.equal(before - C.FARM.UPKEEP, w.treasury)
        end)

    end)

    describe("install (hospital placement debit)", function()
        it("debits HOSPITAL.COST when a hospital is built", function()
            local w = World.new(1)
            Economy.install(w)
            World.build_road(w, 1, 2)
            local before = w.treasury -- capture after road debit
            World.build_hospital(w, 2, 2)
            assert.are.equal(before - C.HOSPITAL.COST, w.treasury)
        end)
    end)
end)
