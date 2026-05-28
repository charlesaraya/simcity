-- spec/systems/land_value_spec.lua
-- Land value is a pure facade over the pollution field: land_value =
-- clamp(BASE - K_POLLUTION * pollution, MIN, MAX). No state of its own, no
-- diffusion -- it just reads the already-diffused pollution. Tested headless by
-- setting pollution values directly on the world.

local LandValue = require("src.systems.land_value")
local World = require("src.world.world")
local Grid = require("src.world.grid")
local Bus = require("src.bus")
local C = require("src.world.constants")

-- Set the cached pollution value at (x, y) directly (bypassing diffusion).
local function set_pollution(w, x, y, value)
    w.pollution.field[Grid.idx(w.grid, x, y)] = value
end

describe("LandValue.at", function()
    before_each(function() Bus.clear() end)

    it("is BASE on a clean tile", function()
        local w = World.new(1)
        assert.are.equal(C.LAND.BASE, LandValue.at(w, 5, 5))
    end)

    it("never exceeds MAX", function()
        local w = World.new(1)
        assert.is_true(LandValue.at(w, 5, 5) <= C.LAND.MAX)
    end)

    it("drops by K_POLLUTION per unit of pollution", function()
        local w = World.new(1)
        set_pollution(w, 7, 7, 10)
        assert.are.equal(C.LAND.BASE - C.LAND.K_POLLUTION * 10, LandValue.at(w, 7, 7))
    end)

    it("floors at MIN under heavy pollution", function()
        local w = World.new(1)
        set_pollution(w, 7, 7, 100000)
        assert.are.equal(C.LAND.MIN, LandValue.at(w, 7, 7))
    end)
end)

