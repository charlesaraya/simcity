-- spec/input/tools_spec.lua
-- Tools map a selected tool id to the matching world writer. No state, no
-- rendering knowledge -- just dispatch.

local Tools = require("src.input.tools")
local World = require("src.world.world")
local Bus = require("src.bus")
local C = require("src.world.constants")

describe("Tools", function()
    before_each(function() Bus.clear() end)

    it("ZONE_RES zones a tile residential", function()
        local w = World.new(1)
        assert.is_true(Tools.apply(C.TOOL.ZONE_RES, w, 2, 2))
        assert.are.equal(C.ZONE.RESIDENTIAL, w.grid.tiles[w.grid.width * 1 + 2].zone)
    end)

    it("ZONE_COM zones a tile commercial", function()
        local w = World.new(1)
        assert.is_true(Tools.apply(C.TOOL.ZONE_COM, w, 2, 2))
        assert.are.equal(C.ZONE.COMMERCIAL, w.grid.tiles[w.grid.width * 1 + 2].zone)
    end)

    it("BULLDOZE clears zone and building", function()
        local w = World.new(1)
        Tools.apply(C.TOOL.ZONE_RES, w, 2, 2)
        World.start_building(w, 2, 2)
        assert.is_true(Tools.apply(C.TOOL.BULLDOZE, w, 2, 2))
        local tile = w.grid.tiles[w.grid.width * 1 + 2]
        assert.are.equal(C.ZONE.NONE, tile.zone)
        assert.is_nil(tile.building)
    end)

    it("returns false for an unknown tool", function()
        local w = World.new(1)
        assert.is_false(Tools.apply(999, w, 2, 2))
    end)
end)
