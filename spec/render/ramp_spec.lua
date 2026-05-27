-- spec/render/ramp_spec.lua
-- Ramp is pure value->color math, extracted from the overlay renderer so the
-- heatmap mapping is testable headless (no LÖVE). It interpolates a {r,g,b} across
-- an ordered list of color stops for a value in [lo, hi], clamping out of range.

local Ramp = require("src.render.ramp")
local C = require("src.world.constants")

local BW = { { 0, 0, 0 }, { 1, 1, 1 } } -- black -> white, for clean arithmetic

describe("Ramp.color", function()
    it("returns the first stop at lo", function()
        assert.are.same({ 0, 0, 0 }, Ramp.color(0, 0, 10, BW))
    end)

    it("returns the last stop at hi", function()
        assert.are.same({ 1, 1, 1 }, Ramp.color(10, 0, 10, BW))
    end)

    it("interpolates the midpoint", function()
        assert.are.same({ 0.5, 0.5, 0.5 }, Ramp.color(5, 0, 10, BW))
    end)

    it("clamps a value below lo to the first stop", function()
        assert.are.same({ 0, 0, 0 }, Ramp.color(-100, 0, 10, BW))
    end)

    it("clamps a value above hi to the last stop", function()
        assert.are.same({ 1, 1, 1 }, Ramp.color(100, 0, 10, BW))
    end)

    it("lands on the middle stop of a 3-stop scheme at the midpoint", function()
        local three = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }
        assert.are.same({ 0, 1, 0 }, Ramp.color(5, 0, 10, three))
    end)
end)

describe("Ramp schemes", function()
    it("the land-value scheme is the inverse of the pollution scheme", function()
        local p, lv = C.RAMP.POLLUTION, C.RAMP.LAND_VALUE
        assert.are.equal(#p, #lv)
        for i = 1, #p do
            assert.are.same(p[i], lv[#lv - i + 1])
        end
    end)

    it("low pollution and high land value share the same (good) color", function()
        -- clean = low pollution = green; high land value = green.
        assert.are.same(
            Ramp.color(0, 0, 100, C.RAMP.POLLUTION),
            Ramp.color(100, 0, 100, C.RAMP.LAND_VALUE)
        )
    end)
end)
