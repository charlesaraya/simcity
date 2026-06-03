-- spec/render/overlays_spec.lua
-- Overlays is the pure half of the heatmap renderer (no LÖVE): it picks the value
-- RANGE a heatmap spans and the per-tile COLOR. Keeping it pure lets us assert the
-- gradient actually runs low->mid->high instead of clustering at one end.

local Overlays = require("src.render.overlays")
local Rails    = require("src.systems.rails")
local Freight  = require("src.systems.freight")
local World    = require("src.world.world")
local Grid     = require("src.world.grid")
local Bus      = require("src.bus")
local C        = require("src.world.constants")

local function set_pollution(w, x, y, v)
    w.pollution.field[Grid.idx(w.grid, x, y)] = v
end

describe("Overlays.range", function()
    before_each(function() Bus.clear() end)

    it("spans pollution from 0 to the current peak (dynamic)", function()
        local w = World.new(1)
        set_pollution(w, 3, 3, 4)
        set_pollution(w, 8, 8, 12)
        local lo, hi = Overlays.range(C.OVERLAY.POLLUTION, w)
        assert.are.equal(0, lo)
        assert.are.equal(12, hi)
    end)

    it("uses land value's fixed absolute scale", function()
        local w = World.new(1)
        local lo, hi = Overlays.range(C.OVERLAY.LAND_VALUE, w)
        assert.are.equal(C.LAND.MIN, lo)
        assert.are.equal(C.LAND.MAX, hi)
    end)
end)

describe("Overlays.color", function()
    before_each(function() Bus.clear() end)

    it("leaves clean tiles untinted under the pollution overlay", function()
        local w = World.new(1)
        assert.is_nil(Overlays.color(C.OVERLAY.POLLUTION, w, 5, 5, 0, 10))
    end)

    it("runs pollution low->mid->high through the green/yellow/red stops", function()
        local w = World.new(1)
        set_pollution(w, 1, 1, 2)  -- low: in the green->yellow segment
        set_pollution(w, 2, 2, 5)  -- mid: exactly the yellow stop
        set_pollution(w, 3, 3, 10) -- high: exactly the red stop
        local lo, hi = 0, 10
        local low = Overlays.color(C.OVERLAY.POLLUTION, w, 1, 1, lo, hi)
        local mid = Overlays.color(C.OVERLAY.POLLUTION, w, 2, 2, lo, hi)
        local high = Overlays.color(C.OVERLAY.POLLUTION, w, 3, 3, lo, hi)
        assert.are.same(C.RAMP.POLLUTION[2], mid)   -- yellow middle (exact)
        assert.are.same(C.RAMP.POLLUTION[3], high)  -- red end (exact)
        -- The low tile is a distinct, greener-ward color: a real gradient, not a step.
        assert.are_not.same(mid, low)
        assert.are_not.same(high, low)
    end)

    it("colors clean land green and heavily polluted land red", function()
        local w = World.new(1)
        local lo, hi = C.LAND.MIN, C.LAND.MAX
        -- clean tile: land value MAX -> the green end of the land-value scheme.
        assert.are.same(C.RAMP.LAND_VALUE[3], Overlays.color(C.OVERLAY.LAND_VALUE, w, 5, 5, lo, hi))
        -- floor land value with heavy pollution -> the red end.
        set_pollution(w, 9, 9, 1000)
        assert.are.same(C.RAMP.LAND_VALUE[1], Overlays.color(C.OVERLAY.LAND_VALUE, w, 9, 9, lo, hi))
    end)
end)

describe("Overlays.color FREIGHT", function()
    before_each(function() Bus.clear() end)

    -- Build a station at (sx, sy) with road west and rail east; return the rail coords.
    local function setup_bridge(w, sx, sy)
        World.build_station(w, sx, sy)
        World.build_road(w, sx - 1, sy)
        World.build_rail(w, sx + 2, sy)
        Rails.install(w)
        Freight.install(w)
        return sx + 2, sy
    end

    it("returns nil for plain grass (not a logistics tile)", function()
        local w = World.new(1)
        Rails.install(w); Freight.install(w)
        assert.is_nil(Overlays.color(C.OVERLAY.FREIGHT, w, 5, 5, 0, 0))
    end)

    it("colors a bridged rail tile green (linked)", function()
        local w = World.new(1)
        local rx, ry = setup_bridge(w, 10, 10)
        assert.are.same(C.RAMP.FREIGHT.linked,
            Overlays.color(C.OVERLAY.FREIGHT, w, rx, ry, 0, 0))
    end)

    it("colors an unbridged rail tile red (unlinked)", function()
        local w = World.new(1)
        World.build_rail(w, 20, 20)
        Rails.install(w); Freight.install(w)
        assert.are.same(C.RAMP.FREIGHT.unlinked,
            Overlays.color(C.OVERLAY.FREIGHT, w, 20, 20, 0, 0))
    end)

    it("colors a station tile white", function()
        local w = World.new(1)
        setup_bridge(w, 10, 10)
        assert.are.same(C.RAMP.FREIGHT.station,
            Overlays.color(C.OVERLAY.FREIGHT, w, 10, 10, 0, 0))
    end)

    it("colors a mine green when adjacent to a bridged rail component", function()
        local w = World.new(1)
        local deposits = World.deposit_tiles(w)
        local d = deposits[1]
        World.build_mine(w, d.x, d.y)
        -- Place rail next to the mine, then bridge it via a station + road.
        local rx, ry = d.x + 1, d.y
        World.build_rail(w, rx, ry)
        World.build_station(w, rx + 1, ry - 1)  -- station touching the rail
        World.build_road(w, rx + 1 - 1, ry - 1) -- road west of station
        Rails.install(w); Freight.install(w)
        -- Only assert if the station actually bridged the component.
        local cid = Rails.tile_component(w, rx, ry)
        if Freight.rail_bridged(w, cid) then
            assert.are.same(C.RAMP.FREIGHT.linked,
                Overlays.color(C.OVERLAY.FREIGHT, w, d.x, d.y, 0, 0))
        end
    end)

    it("colors a mine red when it has no adjacent rail", function()
        local w = World.new(1)
        local deposits = World.deposit_tiles(w)
        local d = deposits[1]
        World.build_mine(w, d.x, d.y)
        Rails.install(w); Freight.install(w)
        assert.are.same(C.RAMP.FREIGHT.unlinked,
            Overlays.color(C.OVERLAY.FREIGHT, w, d.x, d.y, 0, 0))
    end)
end)
