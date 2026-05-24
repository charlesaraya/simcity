-- spec/systems/growth_spec.lua
-- Growth consumes demand + the seeded RNG to spawn, complete, and abandon
-- buildings. Determinism (same seed => same city) is the headline property.

local Growth = require("src.systems.growth")
local World = require("src.world.world")
local Bus = require("src.bus")
local C = require("src.world.constants")

-- Zone a square patch of one zone.
local function zone_patch(w, n, zone)
    for x = 1, n do
        for y = 1, n do
            World.zone_tile(w, x, y, zone)
        end
    end
end

describe("Growth", function()
    before_each(function() Bus.clear() end)

    it("ticks monthly", function()
        assert.are.equal(C.SIM.SECONDS_PER_MONTH, Growth.system().interval)
    end)

    it("does not build when demand is non-positive", function()
        local w = World.new(1)
        zone_patch(w, 8, C.ZONE.RESIDENTIAL)
        w.demand.residential = 0
        local g = Growth.system()
        for _ = 1, 30 do g.tick(w) end
        assert.are.equal(0, World.count_buildings(w, C.ZONE.RESIDENTIAL))
    end)

    it("grows buildings on zoned tiles when demand is positive", function()
        local w = World.new(1)
        zone_patch(w, 8, C.ZONE.RESIDENTIAL)
        w.demand.residential = 0.8
        local g = Growth.system()
        for _ = 1, 30 do g.tick(w) end
        assert.is_true(World.count_buildings(w, C.ZONE.RESIDENTIAL) > 0)
    end)

    it("takes CONSTRUCTION_TICKS months to complete a building", function()
        local w = World.new(1)
        World.zone_tile(w, 1, 1, C.ZONE.RESIDENTIAL)
        World.start_building(w, 1, 1) -- force a construction site
        local g = Growth.system()
        for _ = 1, C.GROWTH.CONSTRUCTION_TICKS do g.tick(w) end
        assert.are.equal(1, World.count_buildings(w, C.ZONE.RESIDENTIAL, C.BUILD.COMPLETE))
    end)

    it("abandons completed buildings when demand collapses", function()
        local w = World.new(1)
        World.zone_tile(w, 1, 1, C.ZONE.COMMERCIAL)
        World.start_building(w, 1, 1)
        World.complete_building(w, 1, 1)
        w.demand.commercial = -1.0
        local g = Growth.system()
        for _ = 1, 200 do g.tick(w) end -- abandonment is probabilistic
        assert.are.equal(0, World.count_buildings(w, C.ZONE.COMMERCIAL))
    end)

    it("is deterministic: same seed yields the same city", function()
        local function run(seed)
            Bus.clear()
            local w = World.new(seed)
            zone_patch(w, 10, C.ZONE.RESIDENTIAL)
            w.demand.residential = 0.8
            local g = Growth.system()
            for _ = 1, 25 do g.tick(w) end
            return w
        end

        local a, b = run(2024), run(2024)
        -- compare the full building layout, not just totals
        local function layout(w)
            local t = {}
            for i = 1, #w.grid.tiles do
                local bld = w.grid.tiles[i].building
                t[i] = bld and bld.state or 0
            end
            return t
        end
        assert.are.same(layout(a), layout(b))
        assert.is_true(World.count_buildings(a, C.ZONE.RESIDENTIAL) > 0) -- something grew
    end)
end)
