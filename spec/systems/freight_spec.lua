-- spec/systems/freight_spec.lua
-- Freight system: bridge detection between rail and road networks (Phase 5 step 5).

local Freight = require("src.systems.freight")
local Rails   = require("src.systems.rails")
local World   = require("src.world.world")
local Bus     = require("src.bus")
local C       = require("src.world.constants")

-- Build a 2×2 station at (x, y), road just west of it, rail just east.
-- Returns the rail tile coords.
local function setup_bridged_station(w, x, y)
    World.build_station(w, x, y)
    World.build_road(w, x - 1, y)     -- west perimeter
    World.build_rail(w, x + 2, y)     -- east perimeter (footprint is x..x+1)
    return x + 2, y
end

describe("Freight", function()
    before_each(function() Bus.clear() end)

    describe("compute_bridged", function()
        it("returns empty table when no stations exist", function()
            local w = World.new(1)
            Rails.install(w)
            assert.are.same({}, Freight.compute_bridged(w))
        end)

        it("returns empty table when station has no rail neighbor", function()
            local w = World.new(1)
            World.build_station(w, 20, 20)
            World.build_road(w, 19, 20) -- road only, no rail
            Rails.install(w)
            assert.are.same({}, Freight.compute_bridged(w))
        end)

        it("returns empty table when station has rail but no road neighbor", function()
            local w = World.new(1)
            World.build_station(w, 20, 20)
            World.build_rail(w, 22, 20) -- rail only, no road
            Rails.install(w)
            assert.are.same({}, Freight.compute_bridged(w))
        end)

        it("marks the rail component bridged when station touches both rail and road", function()
            local w = World.new(1)
            local rx, ry = setup_bridged_station(w, 20, 20)
            Rails.install(w)
            local cid = Rails.tile_component(w, rx, ry)
            assert.is_not_nil(cid)
            local bridged = Freight.compute_bridged(w)
            assert.is_true(bridged[cid])
        end)

        it("can bridge two separate rail components through two stations", function()
            local w = World.new(1)
            local rx1, ry1 = setup_bridged_station(w, 10, 10)
            local rx2, ry2 = setup_bridged_station(w, 30, 30)
            Rails.install(w)
            local cid1 = Rails.tile_component(w, rx1, ry1)
            local cid2 = Rails.tile_component(w, rx2, ry2)
            assert.is_not_nil(cid1)
            assert.is_not_nil(cid2)
            assert.are_not.equal(cid1, cid2)
            local bridged = Freight.compute_bridged(w)
            assert.is_true(bridged[cid1])
            assert.is_true(bridged[cid2])
        end)
    end)

    describe("install", function()
        it("populates world.freight.bridged on install", function()
            local w = World.new(1)
            local rx, ry = setup_bridged_station(w, 20, 20)
            Rails.install(w)
            Freight.install(w)
            local cid = Rails.tile_component(w, rx, ry)
            assert.is_true(w.freight.bridged[cid])
        end)

        it("recomputes on STATION_BUILT", function()
            local w = World.new(1)
            Rails.install(w)
            Freight.install(w)
            -- Initially no station: no bridged components.
            assert.are.same({}, w.freight.bridged)
            -- Build station + rail + road (STATION_BUILT fires via build_station).
            local rx, ry = setup_bridged_station(w, 20, 20)
            -- Rail was built AFTER Freight.install, so recompute triggered by RAIL_BUILT.
            local cid = Rails.tile_component(w, rx, ry)
            assert.is_true(w.freight.bridged[cid])
        end)

        it("recomputes on STATION_REMOVED", function()
            local w = World.new(1)
            local rx, ry = setup_bridged_station(w, 20, 20)
            Rails.install(w)
            Freight.install(w)
            local cid = Rails.tile_component(w, rx, ry)
            assert.is_true(w.freight.bridged[cid])
            World.bulldoze(w, 20, 20) -- removes station
            assert.is_nil(w.freight.bridged[cid])
        end)

        it("recomputes on RAIL_REMOVED", function()
            local w = World.new(1)
            local rx, ry = setup_bridged_station(w, 20, 20)
            Rails.install(w)
            Freight.install(w)
            local cid = Rails.tile_component(w, rx, ry)
            assert.is_true(w.freight.bridged[cid])
            World.bulldoze(w, rx, ry) -- removes the bridging rail tile
            assert.is_nil(w.freight.bridged[cid])
        end)

        it("initialises world.freight when missing (old save migration)", function()
            local w = World.new(1)
            w.freight = nil
            Freight.install(w)
            assert.is_not_nil(w.freight)
            assert.is_not_nil(w.freight.bridged)
        end)
    end)

    describe("rail_bridged", function()
        it("returns false for an unbridged component", function()
            local w = World.new(1)
            Rails.install(w)
            Freight.install(w)
            assert.is_false(Freight.rail_bridged(w, 99))
        end)

        it("returns true for a bridged component", function()
            local w = World.new(1)
            local rx, ry = setup_bridged_station(w, 20, 20)
            Rails.install(w)
            Freight.install(w)
            local cid = Rails.tile_component(w, rx, ry)
            assert.is_true(Freight.rail_bridged(w, cid))
        end)

        it("returns false when world.freight is nil", function()
            local w = World.new(1)
            w.freight = nil
            assert.is_false(Freight.rail_bridged(w, 1))
        end)
    end)
end)
