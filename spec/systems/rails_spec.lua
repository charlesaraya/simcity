-- spec/systems/rails_spec.lua
-- Rail network: component labeling and adjacency queries (Phase 5 step 4).

local Rails = require("src.systems.rails")
local World = require("src.world.world")
local Bus   = require("src.bus")
local C     = require("src.world.constants")

describe("Rails", function()
    before_each(function() Bus.clear() end)

    describe("compute", function()
        it("returns empty table when no rail exists", function()
            local w = World.new(1)
            local comp = Rails.compute(w.grid)
            assert.are.same({}, comp)
        end)

        it("assigns a component id to each connected rail tile", function()
            local w = World.new(1)
            World.build_rail(w, 20, 20)
            World.build_rail(w, 21, 20)
            World.build_rail(w, 22, 20)
            local comp = Rails.compute(w.grid)
            local i1 = w.grid.width * (20 - 1) + 20
            local i2 = w.grid.width * (20 - 1) + 21
            local i3 = w.grid.width * (20 - 1) + 22
            -- All three must share the same component id.
            assert.is_not_nil(comp[i1])
            assert.are.equal(comp[i1], comp[i2])
            assert.are.equal(comp[i2], comp[i3])
        end)

        it("assigns different component ids to disconnected runs", function()
            local w = World.new(1)
            World.build_rail(w, 20, 20)
            World.build_rail(w, 25, 20) -- gap of 3 tiles
            local comp = Rails.compute(w.grid)
            local i1 = w.grid.width * (20 - 1) + 20
            local i2 = w.grid.width * (20 - 1) + 25
            assert.is_not_nil(comp[i1])
            assert.is_not_nil(comp[i2])
            assert.are_not.equal(comp[i1], comp[i2])
        end)
    end)

    describe("install", function()
        it("populates world.rails.components on install", function()
            local w = World.new(1)
            World.build_rail(w, 20, 20)
            Rails.install(w)
            local idx = w.grid.width * (20 - 1) + 20
            assert.is_not_nil(w.rails.components[idx])
        end)

        it("recomputes on RAIL_BUILT events", function()
            local w = World.new(1)
            Rails.install(w)
            local idx = w.grid.width * (20 - 1) + 20
            assert.is_nil(w.rails.components[idx])
            World.build_rail(w, 20, 20)
            assert.is_not_nil(w.rails.components[idx])
        end)

        it("recomputes on RAIL_REMOVED events", function()
            local w = World.new(1)
            World.build_rail(w, 20, 20)
            Rails.install(w)
            local idx = w.grid.width * (20 - 1) + 20
            assert.is_not_nil(w.rails.components[idx])
            World.bulldoze(w, 20, 20)
            assert.is_nil(w.rails.components[idx])
        end)

        it("initialises world.rails when missing (old save migration)", function()
            local w = World.new(1)
            w.rails = nil
            Rails.install(w)
            assert.is_not_nil(w.rails)
            assert.is_not_nil(w.rails.components)
        end)
    end)

    describe("tile_component", function()
        it("returns nil for a non-rail tile", function()
            local w = World.new(1)
            Rails.install(w)
            assert.is_nil(Rails.tile_component(w, 20, 20))
        end)

        it("returns the component id for a rail tile", function()
            local w = World.new(1)
            World.build_rail(w, 20, 20)
            Rails.install(w)
            assert.is_not_nil(Rails.tile_component(w, 20, 20))
        end)
    end)

    describe("adjacent_component", function()
        it("returns nil when no rail neighbor exists", function()
            local w = World.new(1)
            Rails.install(w)
            assert.is_nil(Rails.adjacent_component(w, 20, 20))
        end)

        it("returns the component id when a rail neighbor exists", function()
            local w = World.new(1)
            World.build_rail(w, 21, 20) -- east neighbor of (20,20)
            Rails.install(w)
            assert.is_not_nil(Rails.adjacent_component(w, 20, 20))
        end)

        it("returns the same component id as the rail tile itself", function()
            local w = World.new(1)
            World.build_rail(w, 21, 20)
            Rails.install(w)
            local from_tile = Rails.tile_component(w, 21, 20)
            local from_adj  = Rails.adjacent_component(w, 20, 20)
            assert.are.equal(from_tile, from_adj)
        end)
    end)
end)
