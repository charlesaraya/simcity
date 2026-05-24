-- spec/world/world_spec.lua
-- World is the database (Principle 2): read + write functions only, no logic
-- about meaning. The defining behavior is that every write publishes an event,
-- which we assert by subscribing a test handler to the bus.

local World = require("src.world.world")
local Bus = require("src.bus")
local C = require("src.world.constants")

-- Capture the last payload published for an event.
local function spy_on(event)
    local box = { called = 0 }
    Bus.subscribe(event, function(data)
        box.called = box.called + 1
        box.data = data
    end)
    return box
end

describe("World", function()
    before_each(function() Bus.clear() end)

    it("new() builds a grid, an RNG, and zeroed demand", function()
        local w = World.new(123)
        assert.are.equal(C.GRID_W, w.grid.width)
        assert.is_not_nil(w.rng)
        assert.are.equal(0, w.demand.residential)
        assert.are.equal(0, w.demand.commercial)
    end)

    describe("zone_tile", function()
        it("sets the tile's zone and publishes tile_zoned", function()
            local w = World.new(1)
            local spy = spy_on(C.EVENTS.TILE_ZONED)
            assert.is_true(World.zone_tile(w, 5, 6, C.ZONE.RESIDENTIAL))
            assert.are.equal(C.ZONE.RESIDENTIAL, w.grid.tiles[w.grid.width * 5 + 5].zone)
            assert.are.equal(1, spy.called)
            assert.are.same({ x = 5, y = 6, zone = C.ZONE.RESIDENTIAL }, spy.data)
        end)

        it("rejects out-of-bounds and publishes nothing", function()
            local w = World.new(1)
            local spy = spy_on(C.EVENTS.TILE_ZONED)
            assert.is_false(World.zone_tile(w, 999, 999, C.ZONE.RESIDENTIAL))
            assert.are.equal(0, spy.called)
        end)
    end)

    describe("bulldoze", function()
        it("clears zone and building and publishes tile_bulldozed", function()
            local w = World.new(1)
            World.zone_tile(w, 2, 2, C.ZONE.COMMERCIAL)
            World.start_building(w, 2, 2)
            local spy = spy_on(C.EVENTS.TILE_BULLDOZED)
            assert.is_true(World.bulldoze(w, 2, 2))
            local tile = w.grid.tiles[w.grid.width * 1 + 2]
            assert.are.equal(C.ZONE.NONE, tile.zone)
            assert.is_nil(tile.building)
            assert.are.equal(1, spy.called)
        end)
    end)

    describe("building lifecycle", function()
        it("start_building marks a tile constructing", function()
            local w = World.new(1)
            assert.is_true(World.start_building(w, 3, 3))
            assert.are.equal(C.BUILD.CONSTRUCTING, w.grid.tiles[w.grid.width * 2 + 3].building.state)
        end)

        it("complete_building marks complete and publishes building_constructed", function()
            local w = World.new(1)
            World.zone_tile(w, 4, 4, C.ZONE.RESIDENTIAL)
            World.start_building(w, 4, 4)
            local spy = spy_on(C.EVENTS.BUILDING_CONSTRUCTED)
            assert.is_true(World.complete_building(w, 4, 4))
            assert.are.equal(C.BUILD.COMPLETE, w.grid.tiles[w.grid.width * 3 + 4].building.state)
            assert.are.equal(1, spy.called)
            assert.are.equal(C.ZONE.RESIDENTIAL, spy.data.zone)
        end)

        it("abandon_building removes it and publishes building_abandoned with its zone", function()
            local w = World.new(1)
            World.zone_tile(w, 4, 4, C.ZONE.COMMERCIAL)
            World.start_building(w, 4, 4)
            World.complete_building(w, 4, 4)
            local spy = spy_on(C.EVENTS.BUILDING_ABANDONED)
            assert.is_true(World.abandon_building(w, 4, 4))
            assert.is_nil(w.grid.tiles[w.grid.width * 3 + 4].building)
            assert.are.equal(C.ZONE.COMMERCIAL, spy.data.zone)
        end)
    end)

    describe("counters", function()
        local function build(w, x, y, zone)
            World.zone_tile(w, x, y, zone)
            World.start_building(w, x, y)
            World.complete_building(w, x, y)
        end

        it("count_buildings filters by zone and state", function()
            local w = World.new(1)
            build(w, 1, 1, C.ZONE.RESIDENTIAL)
            build(w, 2, 1, C.ZONE.RESIDENTIAL)
            build(w, 3, 1, C.ZONE.COMMERCIAL)
            World.zone_tile(w, 4, 1, C.ZONE.RESIDENTIAL)
            World.start_building(w, 4, 1) -- still constructing

            assert.are.equal(2, World.count_buildings(w, C.ZONE.RESIDENTIAL, C.BUILD.COMPLETE))
            assert.are.equal(1, World.count_buildings(w, C.ZONE.COMMERCIAL, C.BUILD.COMPLETE))
            assert.are.equal(3, World.count_buildings(w, C.ZONE.RESIDENTIAL)) -- any state
        end)

        it("population scales completed residential buildings", function()
            local w = World.new(1)
            build(w, 1, 1, C.ZONE.RESIDENTIAL)
            build(w, 2, 1, C.ZONE.RESIDENTIAL)
            assert.are.equal(2 * C.POP_PER_RES, World.population(w))
        end)
    end)
end)
