-- spec/systems/growth_spec.lua
-- Growth consumes demand + the seeded RNG to spawn, complete, and abandon
-- buildings. Determinism (same seed => same city) is the headline property.

local Growth = require("src.systems.growth")
local World = require("src.world.world")
local Roads = require("src.systems.roads")
local Power = require("src.systems.power")
local Grid = require("src.world.grid")
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

-- Lay a connected road column down the left edge (x=1, rows 1..n), install the
-- roads and power systems, and drop a plant just past the column so the whole
-- column is energised. Call BEFORE zone_patch: the x=1 tiles become road (zoning
-- then skips them), leaving the x=2 column adjacent to a connected, POWERED road
-- so it can grow and stay built under both the road and power gates. (Power is
-- now a hard requirement -- an unpowered building abandons.)
local function connect_left_edge(w, n)
    for y = 1, n do World.build_road(w, 1, y) end
    Roads.install(w)
    Power.install(w)               -- after Roads.install: the plant gate reads roads.connected
    World.build_plant(w, 1, n + 1) -- footprint touches the edge road (1,n) -> 100 MW into the column
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
        connect_left_edge(w, 8)
        zone_patch(w, 8, C.ZONE.RESIDENTIAL)
        w.demand.residential = 0.8
        local g = Growth.system()
        for _ = 1, 30 do g.tick(w) end
        assert.is_true(World.count_buildings(w, C.ZONE.RESIDENTIAL) > 0)
    end)

    it("grows industrial buildings on zoned tiles when demand is positive", function()
        local w = World.new(1)
        connect_left_edge(w, 8)
        zone_patch(w, 8, C.ZONE.INDUSTRIAL)
        w.demand.industrial = 0.8
        local g = Growth.system()
        for _ = 1, 30 do g.tick(w) end
        assert.is_true(World.count_buildings(w, C.ZONE.INDUSTRIAL) > 0)
    end)

    it("takes CONSTRUCTION_TICKS months to complete a building", function()
        local w = World.new(1)
        World.build_road(w, 2, 1) -- edge road so (1,1) is road-connected
        Roads.install(w)
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

    describe("road connectivity gate", function()
        it("never builds on a zoned tile with no road access", function()
            local w = World.new(1)
            zone_patch(w, 8, C.ZONE.RESIDENTIAL) -- no roads laid anywhere
            w.demand.residential = 0.8
            local g = Growth.system()
            for _ = 1, 30 do g.tick(w) end
            assert.are.equal(0, World.count_buildings(w, C.ZONE.RESIDENTIAL))
        end)

        it("builds once a connecting road exists", function()
            local w = World.new(1)
            connect_left_edge(w, 8) -- road at x=1; x=2 column becomes connected
            zone_patch(w, 8, C.ZONE.RESIDENTIAL)
            w.demand.residential = 0.8
            local g = Growth.system()
            for _ = 1, 30 do g.tick(w) end
            assert.is_true(World.count_buildings(w, C.ZONE.RESIDENTIAL) > 0)
        end)

        it("abandons a completed building that loses road access", function()
            local w = World.new(1)
            World.build_road(w, 2, 1) -- edge road, connected
            Roads.install(w)
            World.zone_tile(w, 2, 2, C.ZONE.RESIDENTIAL) -- adjacent to the road
            World.start_building(w, 2, 2)
            World.complete_building(w, 2, 2)
            w.demand.residential = 0.5 -- positive: NOT a demand-collapse abandon
            World.bulldoze(w, 2, 1)    -- sever the only link -> recompute
            local g = Growth.system()
            for _ = 1, 200 do g.tick(w) end
            assert.are.equal(0, World.count_buildings(w, C.ZONE.RESIDENTIAL))
        end)

        it("abandons a constructing building that loses road access", function()
            local w = World.new(1)
            World.build_road(w, 2, 1)
            Roads.install(w)
            World.zone_tile(w, 2, 2, C.ZONE.RESIDENTIAL)
            World.start_building(w, 2, 2) -- left constructing
            w.demand.residential = 0.5
            World.bulldoze(w, 2, 1)
            local g = Growth.system()
            for _ = 1, 200 do g.tick(w) end
            assert.are.equal(0, World.count_buildings(w, C.ZONE.RESIDENTIAL))
        end)
    end)

    describe("power connectivity gate", function()
        it("abandons a completed building that has no power", function()
            local w = World.new(1)
            World.build_road(w, 2, 1) -- edge road: stays road-connected
            Roads.install(w)
            Power.install(w)
            World.zone_tile(w, 2, 2, C.ZONE.RESIDENTIAL)
            World.start_building(w, 2, 2)
            World.complete_building(w, 2, 2)
            -- Zero demand: above the collapse threshold (so it is NOT a demand
            -- abandon) yet too low to rebuild once it goes -- isolating the power
            -- trigger. Road-connected, but with no plant the component is dark.
            w.demand.residential = 0
            local g = Growth.system()
            for _ = 1, 200 do g.tick(w) end
            assert.are.equal(0, World.count_buildings(w, C.ZONE.RESIDENTIAL))
        end)

        it("keeps a powered, road-connected building with positive demand", function()
            local w = World.new(1)
            for x = 1, 3 do World.build_road(w, x, 1) end -- edge chain
            Roads.install(w)
            Power.install(w)
            World.build_plant(w, 3, 2) -- footprint touches road (3,1) -> 100 MW
            World.zone_tile(w, 2, 2, C.ZONE.RESIDENTIAL)
            World.start_building(w, 2, 2)
            World.complete_building(w, 2, 2)
            w.demand.residential = 0.5
            local g = Growth.system()
            for _ = 1, 200 do g.tick(w) end
            assert.are.equal(1, World.count_buildings(w, C.ZONE.RESIDENTIAL, C.BUILD.COMPLETE))
        end)

        it("does not gate construction on power (a site completes while unpowered)", function()
            local w = World.new(1)
            World.build_road(w, 2, 1)
            Roads.install(w)
            Power.install(w)
            World.zone_tile(w, 2, 2, C.ZONE.RESIDENTIAL)
            World.start_building(w, 2, 2) -- constructing, no power anywhere
            local g = Growth.system()
            for _ = 1, C.GROWTH.CONSTRUCTION_TICKS do g.tick(w) end
            assert.are.equal(1, World.count_buildings(w, C.ZONE.RESIDENTIAL, C.BUILD.COMPLETE))
        end)

        it("does not START a building where the power component has no headroom", function()
            local w = World.new(1)
            World.build_road(w, 1, 1) -- edge road, road-connected -- but no plant => 0 supply
            Roads.install(w)
            Power.install(w)
            World.zone_tile(w, 2, 1, C.ZONE.RESIDENTIAL)
            w.demand.residential = 1.0
            local g = Growth.system()
            for _ = 1, 50 do g.tick(w) end
            assert.are.equal(0, World.count_buildings(w, C.ZONE.RESIDENTIAL)) -- power gates growth
        end)

        it("plateaus at the power ceiling instead of overshooting (no blackout loop)", function()
            local w = World.new(1)
            for y = 1, 6 do World.build_road(w, 1, y) end -- edge column
            Roads.install(w)
            Power.install(w)
            -- Pin a tiny fixed supply: room for exactly two residential (draw 2 each).
            local cid = w.power.topology.component[Grid.idx(w.grid, 1, 1)]
            w.power.topology.supply[cid] = 2 * C.POWER_DRAW[C.ZONE.RESIDENTIAL]
            for y = 1, 6 do World.zone_tile(w, 2, y, C.ZONE.RESIDENTIAL) end
            w.demand.residential = 1.0
            local g = Growth.system()
            for _ = 1, 100 do g.tick(w) end
            -- Committed load never exceeds supply, so growth settles at 2 and holds
            -- (no overshoot -> no blackout -> no abandon -> no oscillation).
            assert.are.equal(2, World.count_buildings(w, C.ZONE.RESIDENTIAL, C.BUILD.COMPLETE))
        end)
    end)

    it("is deterministic: same seed yields the same city", function()
        local function run(seed)
            Bus.clear()
            local w = World.new(seed)
            connect_left_edge(w, 10)
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

-- Land value (derived from pollution) biases WHERE res/com grow: a clean tile is
-- far likelier to start than a polluted one; industry is indifferent. The demand
-- math is untouched -- this only scales the per-tile start chance.
describe("Growth land-value bias", function()
    before_each(function() Bus.clear() end)

    -- Grow a single tall column of zoned, road+power-connected tiles for 20 months
    -- under a uniform injected pollution level; return how many buildings of `zone`
    -- exist. A 30-tile column (not a saturating 8) keeps the sample big enough that
    -- the start-chance bias shows instead of every tile filling regardless. The
    -- pollution is set directly with dirty=false, so growth's resolve is a no-op
    -- and the injected field stands (Pollution is intentionally not installed).
    local H = 30
    local function grown_under_pollution(seed, zone, demand, pollution)
        local w = World.new(seed)
        for y = 1, H do World.build_road(w, 1, y) end -- connected edge column
        Roads.install(w)
        Power.install(w)
        World.build_plant(w, 1, H + 1) -- footprint touches the edge road -> powers the column
        for y = 1, H do World.zone_tile(w, 2, y, zone) end -- the growable column, road-adjacent
        if zone == C.ZONE.RESIDENTIAL then
            w.demand.residential = demand
        elseif zone == C.ZONE.COMMERCIAL then
            w.demand.commercial = demand
        else
            w.demand.industrial = demand
        end
        for y = 1, H do
            w.pollution.field[Grid.idx(w.grid, 2, y)] = pollution
        end
        local g = Growth.system()
        for _ = 1, 20 do g.tick(w) end
        return World.count_buildings(w, zone)
    end

    it("grows fewer residential on heavily polluted land than on clean land", function()
        local clean = grown_under_pollution(1, C.ZONE.RESIDENTIAL, 0.8, 0)
        local dirty = grown_under_pollution(1, C.ZONE.RESIDENTIAL, 0.8, 50) -- land value floored
        assert.is_true(dirty < clean)
    end)

    it("leaves industrial growth unaffected by land value", function()
        local clean = grown_under_pollution(1, C.ZONE.INDUSTRIAL, 0.8, 0)
        local dirty = grown_under_pollution(1, C.ZONE.INDUSTRIAL, 0.8, 50)
        assert.are.equal(clean, dirty)
    end)

    it("resolves the pollution field each tick", function()
        local w = World.new(1)
        w.pollution.dirty = true
        Growth.system().tick(w)
        assert.is_false(w.pollution.dirty) -- growth called Pollution.resolve
    end)
end)
