-- spec/systems/power_spec.lua
-- Power.compute_topology is the eager cache (the roads-twin): flood-fill the
-- conducting medium (roads UNION power lines UNION plant footprints) into
-- connected components, and total the supply each component receives from its
-- plants. A plant only feeds the grid when its footprint touches an edge-
-- connected road (workers must be able to reach it), so it reuses the road
-- connectivity cache. Pure: reads world.grid + world.roads.connected, returns a
-- fresh topology table. Tested headless on small hand-built worlds.

local Power = require("src.systems.power")
local Roads = require("src.systems.roads")
local World = require("src.world.world")
local Grid = require("src.world.grid")
local Bus = require("src.bus")
local C = require("src.world.constants")

-- The component id labelling the conducting tile at (x, y).
local function comp(topo, grid, x, y)
    return topo.component[Grid.idx(grid, x, y)]
end

-- The supply (MW) of the component that the tile at (x, y) belongs to.
local function supply_at(topo, grid, x, y)
    return topo.supply[comp(topo, grid, x, y)]
end

describe("Power.compute_topology", function()
    before_each(function() Bus.clear() end)

    describe("components", function()
        it("labels a connected run of conductors as one component", function()
            local w = World.new(1)
            World.build_road(w, 1, 4)
            World.build_road(w, 2, 4)
            World.build_road(w, 3, 4)
            local topo = Power.compute_topology(w)
            local c = comp(topo, w.grid, 1, 4)
            assert.is_not_nil(c)
            assert.are.equal(c, comp(topo, w.grid, 2, 4))
            assert.are.equal(c, comp(topo, w.grid, 3, 4))
        end)

        it("gives disjoint conductor groups distinct components", function()
            local w = World.new(1)
            World.build_road(w, 1, 2) -- group A
            World.build_road(w, 2, 2)
            World.build_road(w, 1, 6) -- group B, rows away
            World.build_road(w, 2, 6)
            local topo = Power.compute_topology(w)
            assert.are_not.equal(comp(topo, w.grid, 1, 2), comp(topo, w.grid, 1, 6))
        end)

        it("a power line bridges two road groups into one component", function()
            local w = World.new(1)
            World.build_road(w, 2, 2)
            World.build_road(w, 2, 6)
            World.build_power_line(w, 2, 3) -- vertical line bridging the gap
            World.build_power_line(w, 2, 4)
            World.build_power_line(w, 2, 5)
            local topo = Power.compute_topology(w)
            assert.are.equal(comp(topo, w.grid, 2, 2), comp(topo, w.grid, 2, 6))
        end)

        it("a road and an adjacent power line share a component (both conduct)", function()
            local w = World.new(1)
            World.build_road(w, 3, 3)
            World.build_power_line(w, 4, 3)
            local topo = Power.compute_topology(w)
            assert.are.equal(comp(topo, w.grid, 3, 3), comp(topo, w.grid, 4, 3))
        end)

        it("a plant footprint joins the component of an adjacent conductor", function()
            local w = World.new(1)
            World.build_road(w, 3, 4)
            World.build_plant(w, 3, 5) -- footprint tile (3,5) is adjacent to road (3,4)
            local topo = Power.compute_topology(w)
            assert.are.equal(comp(topo, w.grid, 3, 4), comp(topo, w.grid, 3, 5))
            assert.is_not_nil(comp(topo, w.grid, 4, 6)) -- the far footprint corner is labelled too
        end)
    end)

    describe("supply", function()
        it("a road-connected plant feeds CAPACITY into its component", function()
            local w = World.new(1)
            Roads.install(w)
            World.build_road(w, 1, 4) -- x=1 is the map edge
            World.build_road(w, 2, 4)
            World.build_road(w, 3, 4)
            World.build_plant(w, 3, 5) -- footprint touches the edge-connected road
            local topo = Power.compute_topology(w)
            assert.are.equal(C.PLANT.CAPACITY, supply_at(topo, w.grid, 3, 5))
        end)

        it("a plant with no road at all contributes zero supply", function()
            local w = World.new(1)
            Roads.install(w)
            World.build_plant(w, 4, 4) -- interior, unreachable
            local topo = Power.compute_topology(w)
            assert.are.equal(0, supply_at(topo, w.grid, 4, 4))
        end)

        it("a plant beside an isolated interior road contributes zero (road not edge-connected)", function()
            local w = World.new(1)
            Roads.install(w)
            World.build_road(w, 10, 10) -- interior, never reaches an edge
            World.build_plant(w, 10, 11) -- footprint touches that road, but it's stranded
            local topo = Power.compute_topology(w)
            assert.are.equal(0, supply_at(topo, w.grid, 10, 11))
        end)

        it("two road-connected plants in one component sum their capacity", function()
            local w = World.new(1)
            Roads.install(w)
            for x = 1, 5 do World.build_road(w, x, 4) end -- edge chain
            World.build_plant(w, 2, 5) -- adjacent to road (2,4)
            World.build_plant(w, 5, 5) -- adjacent to road (5,4)
            local topo = Power.compute_topology(w)
            assert.are.equal(comp(topo, w.grid, 2, 5), comp(topo, w.grid, 5, 5)) -- merged via the roads
            assert.are.equal(2 * C.PLANT.CAPACITY, supply_at(topo, w.grid, 2, 5))
        end)

        it("conductors with no plant have zero supply", function()
            local w = World.new(1)
            World.build_road(w, 1, 4)
            World.build_road(w, 2, 4)
            local topo = Power.compute_topology(w)
            assert.are.equal(0, supply_at(topo, w.grid, 1, 4))
        end)
    end)
end)

-- A completed building of `zone` on the tile at (x, y), adjacent to the network.
local function complete_building(w, x, y, zone)
    World.zone_tile(w, x, y, zone)
    World.start_building(w, x, y)
    World.complete_building(w, x, y)
end

-- The component id of the conductor at (x, y).
local function cid_at(w, x, y)
    return w.power.topology.component[Grid.idx(w.grid, x, y)]
end

describe("Power.resolve", function()
    before_each(function() Bus.clear() end)

    -- A small road network with the topology cached, ready for supply tweaks.
    -- resolve consumes world.power.topology (the eager cache), so these tests set
    -- supply directly rather than building plants -- plant supply is Step 3's job.
    local function networked_world()
        local w = World.new(1)
        World.build_road(w, 1, 4)
        World.build_road(w, 2, 4)
        World.build_road(w, 3, 4)
        w.power.topology = Power.compute_topology(w)
        return w
    end

    it("lights a component when supply covers demand", function()
        local w = networked_world()
        local cid = cid_at(w, 1, 4)
        complete_building(w, 1, 3, C.ZONE.RESIDENTIAL) -- draws 2, adjacent to road (1,4)
        complete_building(w, 2, 3, C.ZONE.RESIDENTIAL)
        complete_building(w, 3, 3, C.ZONE.RESIDENTIAL)
        w.power.topology.supply[cid] = 6 -- exactly the 3 * 2 draw
        Power.resolve(w)
        assert.is_true(Power.building_powered(w, 1, 3))
        assert.is_true(Power.building_powered(w, 3, 3))
    end)

    it("blacks out the WHOLE component when demand exceeds supply", function()
        local w = networked_world()
        local cid = cid_at(w, 1, 4)
        complete_building(w, 1, 3, C.ZONE.RESIDENTIAL)
        complete_building(w, 2, 3, C.ZONE.RESIDENTIAL)
        complete_building(w, 3, 3, C.ZONE.RESIDENTIAL)
        w.power.topology.supply[cid] = 5 -- one MW short of the 6 demand
        Power.resolve(w)
        assert.is_false(Power.building_powered(w, 1, 3))
        assert.is_false(Power.building_powered(w, 2, 3)) -- all dark, not just the marginal one
        assert.is_false(Power.building_powered(w, 3, 3))
    end)

    it("sums demand by zone (res 2 + com 3 + ind 5)", function()
        local w = networked_world()
        local cid = cid_at(w, 1, 4)
        complete_building(w, 1, 3, C.ZONE.RESIDENTIAL) -- 2
        complete_building(w, 2, 3, C.ZONE.COMMERCIAL)  -- 3
        complete_building(w, 3, 3, C.ZONE.INDUSTRIAL)  -- 5
        w.power.topology.supply[cid] = 10              -- exactly 2+3+5
        Power.resolve(w)
        assert.is_true(Power.building_powered(w, 2, 3))
        w.power.topology.supply[cid] = 9 -- one short
        Power.resolve(w)
        assert.is_false(Power.building_powered(w, 2, 3))
    end)

    it("does not count buildings still under construction", function()
        local w = networked_world()
        local cid = cid_at(w, 1, 4)
        World.zone_tile(w, 1, 3, C.ZONE.INDUSTRIAL)
        World.start_building(w, 1, 3) -- constructing, NOT complete
        w.power.topology.supply[cid] = 1 -- far below an industrial draw of 5
        Power.resolve(w)
        assert.is_true(Power.building_powered(w, 1, 3)) -- still lit: no load from the site
    end)

    it("never lights a component with no supply, even at zero demand", function()
        local w = networked_world() -- roads only, no plant => supply 0
        complete_building(w, 1, 3, C.ZONE.RESIDENTIAL)
        Power.resolve(w)
        assert.is_false(Power.building_powered(w, 1, 3)) -- dead wires, no source
    end)

    it("is idempotent: resolving twice yields the same powered set (no oscillation)", function()
        local w = networked_world()
        local cid = cid_at(w, 1, 4)
        complete_building(w, 1, 3, C.ZONE.RESIDENTIAL)
        w.power.topology.supply[cid] = 10
        Power.resolve(w)
        local first = {}
        for idx in pairs(w.power.powered) do first[idx] = true end
        Power.resolve(w)
        assert.are.same(first, w.power.powered)
    end)
end)

describe("Power.building_powered", function()
    before_each(function() Bus.clear() end)

    it("is true for a tile adjacent to a lit conductor", function()
        local w = World.new(1)
        World.build_road(w, 1, 4)
        w.power.topology = Power.compute_topology(w)
        w.power.topology.supply[cid_at(w, 1, 4)] = 50
        Power.resolve(w)
        assert.is_true(Power.building_powered(w, 1, 3))
    end)

    it("is false for a tile adjacent only to a dark (unsupplied) conductor", function()
        local w = World.new(1)
        World.build_road(w, 1, 4)
        w.power.topology = Power.compute_topology(w) -- supply 0
        Power.resolve(w)
        assert.is_false(Power.building_powered(w, 1, 3))
    end)

    it("is false for a tile with no adjacent conductor", function()
        local w = World.new(1)
        w.power.topology = Power.compute_topology(w)
        Power.resolve(w)
        assert.is_false(Power.building_powered(w, 30, 30))
    end)
end)
