-- spec/systems/zoning_spec.lua
-- Zoning is event-driven, not ticked. install() wires its bus subscriptions.
-- Its responsibility: when a built tile is rezoned, demolish the stale building.

local Zoning = require("src.systems.zoning")
local World = require("src.world.world")
local Bus = require("src.bus")
local C = require("src.world.constants")

describe("Zoning", function()
    before_each(function() Bus.clear() end)

    it("demolishes the building when a built tile is rezoned to a different zone", function()
        local w = World.new(1)
        Zoning.install(w)

        World.zone_tile(w, 3, 3, C.ZONE.RESIDENTIAL)
        World.start_building(w, 3, 3)
        World.complete_building(w, 3, 3)
        assert.is_not_nil(World.count_buildings(w, C.ZONE.RESIDENTIAL, C.BUILD.COMPLETE))

        -- rezone to commercial -> the residential building must be cleared
        World.zone_tile(w, 3, 3, C.ZONE.COMMERCIAL)
        local tile = w.grid.tiles[w.grid.width * 2 + 3]
        assert.is_nil(tile.building)
        assert.are.equal(C.ZONE.COMMERCIAL, tile.zone)
    end)

    it("does nothing when zoning an empty tile", function()
        local w = World.new(1)
        Zoning.install(w)
        assert.has_no.errors(function() World.zone_tile(w, 1, 1, C.ZONE.RESIDENTIAL) end)
        assert.is_nil(w.grid.tiles[1].building)
    end)
end)
