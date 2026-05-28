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
        assert.are.equal(0, w.demand.industrial)
        assert.are.same({}, w.roads.connected)
        assert.are.same({}, w.pollution.field)
        assert.is_false(w.pollution.dirty)
        -- 4c-1 step 5: charter slots exist on a fresh world but are empty
        -- until World.charter populates them.
        assert.are.same({}, w.crew)
        assert.are.same({}, w.mission)
    end)

    it("new(seed, opts) applies opts.start_treasury when given", function()
        local w = World.new(1, { start_treasury = 5000 })
        assert.are.equal(5000, w.treasury)
    end)

    it("new(seed) without opts uses the default start treasury", function()
        local w = World.new(1)
        assert.are.equal(C.ECON.START_TREASURY, w.treasury)
    end)

    describe("charter", function()
        it("sets mission and crew atomically and publishes mission_chartered", function()
            local w = World.new(1)
            local spy = spy_on(C.EVENTS.MISSION_CHARTERED)
            local mission = { name = "Janus-IV", difficulty = "first_mission", started_at = 1234 }
            local crew = {
                { name = "Akemi Vance",   role = C.ROLE.COMMANDER, traits = { "Veteran" },    status = C.STATUS.ACTIVE },
                { name = "Salim Okoro",   role = C.ROLE.ENGINEER,  traits = { "Methodical" }, status = C.STATUS.ACTIVE },
            }
            assert.is_true(World.charter(w, mission, crew))
            assert.are.same(mission, w.mission)
            assert.are.same(crew, w.crew)
            assert.are.equal(1, spy.called)
        end)

        it("a subsequent charter REPLACES mission + crew (re-roll allowed in charter screen)", function()
            local w = World.new(1)
            World.charter(w, { name = "First" }, { { name = "A" } })
            World.charter(w, { name = "Second" }, { { name = "B" }, { name = "C" } })
            assert.are.equal("Second", w.mission.name)
            assert.are.equal(2, #w.crew)
        end)
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

        it("is idempotent: zoning to the same zone is a no-op", function()
            local w = World.new(1)
            World.zone_tile(w, 5, 6, C.ZONE.RESIDENTIAL)
            local spy = spy_on(C.EVENTS.TILE_ZONED)
            assert.is_false(World.zone_tile(w, 5, 6, C.ZONE.RESIDENTIAL))
            assert.are.equal(0, spy.called)
        end)
    end)

    describe("build_road", function()
        local function tile_at(w, x, y)
            return w.grid.tiles[w.grid.width * (y - 1) + x]
        end

        it("lays a road on plain grass and publishes road_built", function()
            local w = World.new(1)
            local spy = spy_on(C.EVENTS.ROAD_BUILT)
            assert.is_true(World.build_road(w, 5, 6))
            assert.is_true(tile_at(w, 5, 6).road)
            assert.are.equal(1, spy.called)
            assert.are.same({ x = 5, y = 6 }, spy.data)
        end)

        it("refuses a zoned tile and publishes nothing", function()
            local w = World.new(1)
            World.zone_tile(w, 5, 6, C.ZONE.RESIDENTIAL)
            local spy = spy_on(C.EVENTS.ROAD_BUILT)
            assert.is_false(World.build_road(w, 5, 6))
            assert.is_nil(tile_at(w, 5, 6).road)
            assert.are.equal(0, spy.called)
        end)

        it("refuses a tile that already has a building", function()
            local w = World.new(1)
            World.start_building(w, 5, 6)
            local spy = spy_on(C.EVENTS.ROAD_BUILT)
            assert.is_false(World.build_road(w, 5, 6))
            assert.are.equal(0, spy.called)
        end)

        it("is idempotent: re-roading a road tile is a no-op", function()
            local w = World.new(1)
            World.build_road(w, 5, 6)
            local spy = spy_on(C.EVENTS.ROAD_BUILT)
            assert.is_false(World.build_road(w, 5, 6))
            assert.are.equal(0, spy.called)
        end)

        it("rejects out-of-bounds", function()
            local w = World.new(1)
            assert.is_false(World.build_road(w, 999, 999))
        end)

        it("zone_tile refuses a road tile and publishes nothing", function()
            local w = World.new(1)
            World.build_road(w, 5, 6)
            local spy = spy_on(C.EVENTS.TILE_ZONED)
            assert.is_false(World.zone_tile(w, 5, 6, C.ZONE.RESIDENTIAL))
            assert.are.equal(C.ZONE.NONE, tile_at(w, 5, 6).zone)
            assert.are.equal(0, spy.called)
        end)

        it("bulldoze clears a road and publishes road_removed (not tile_bulldozed)", function()
            local w = World.new(1)
            World.build_road(w, 5, 6)
            local removed = spy_on(C.EVENTS.ROAD_REMOVED)
            local bulldozed = spy_on(C.EVENTS.TILE_BULLDOZED)
            assert.is_true(World.bulldoze(w, 5, 6))
            assert.is_nil(tile_at(w, 5, 6).road)
            assert.are.equal(1, removed.called)
            assert.are.equal(0, bulldozed.called)
        end)
    end)

    describe("build_power_line", function()
        local function tile_at(w, x, y)
            return w.grid.tiles[w.grid.width * (y - 1) + x]
        end

        it("lays a power line on plain grass and publishes power_line_built", function()
            local w = World.new(1)
            local spy = spy_on(C.EVENTS.POWER_LINE_BUILT)
            assert.is_true(World.build_power_line(w, 5, 6))
            assert.is_true(tile_at(w, 5, 6).power_line)
            assert.are.equal(1, spy.called)
            assert.are.same({ x = 5, y = 6 }, spy.data)
        end)

        it("refuses a road tile and publishes nothing", function()
            local w = World.new(1)
            World.build_road(w, 5, 6)
            local spy = spy_on(C.EVENTS.POWER_LINE_BUILT)
            assert.is_false(World.build_power_line(w, 5, 6))
            assert.are.equal(0, spy.called)
        end)

        it("refuses a zoned tile and publishes nothing", function()
            local w = World.new(1)
            World.zone_tile(w, 5, 6, C.ZONE.RESIDENTIAL)
            local spy = spy_on(C.EVENTS.POWER_LINE_BUILT)
            assert.is_false(World.build_power_line(w, 5, 6))
            assert.are.equal(0, spy.called)
        end)

        it("is idempotent: re-lining a power-line tile is a no-op", function()
            local w = World.new(1)
            World.build_power_line(w, 5, 6)
            local spy = spy_on(C.EVENTS.POWER_LINE_BUILT)
            assert.is_false(World.build_power_line(w, 5, 6))
            assert.are.equal(0, spy.called)
        end)

        it("build_road and zone_tile both refuse a power-line tile", function()
            local w = World.new(1)
            World.build_power_line(w, 5, 6)
            assert.is_false(World.build_road(w, 5, 6))
            assert.is_false(World.zone_tile(w, 5, 6, C.ZONE.RESIDENTIAL))
            assert.is_true(tile_at(w, 5, 6).power_line)
        end)

        it("bulldoze clears a power line and publishes power_line_removed only", function()
            local w = World.new(1)
            World.build_power_line(w, 5, 6)
            local removed = spy_on(C.EVENTS.POWER_LINE_REMOVED)
            local bulldozed = spy_on(C.EVENTS.TILE_BULLDOZED)
            local road_removed = spy_on(C.EVENTS.ROAD_REMOVED)
            assert.is_true(World.bulldoze(w, 5, 6))
            assert.is_nil(tile_at(w, 5, 6).power_line)
            assert.are.equal(1, removed.called)
            assert.are.equal(0, bulldozed.called)
            assert.are.equal(0, road_removed.called)
        end)
    end)

    describe("build_plant (2x2 footprint)", function()
        local function tile_at(w, x, y)
            return w.grid.tiles[w.grid.width * (y - 1) + x]
        end
        local function idx(w, x, y)
            return w.grid.width * (y - 1) + x
        end

        it("occupies a 2x2 footprint: anchor tile + 3 part back-references", function()
            local w = World.new(1)
            local spy = spy_on(C.EVENTS.PLANT_BUILT)
            assert.is_true(World.build_plant(w, 5, 6))
            local anchor = idx(w, 5, 6)
            assert.is_truthy(tile_at(w, 5, 6).plant)         -- anchor
            assert.are.equal(anchor, tile_at(w, 6, 6).plant_part)
            assert.are.equal(anchor, tile_at(w, 5, 7).plant_part)
            assert.are.equal(anchor, tile_at(w, 6, 7).plant_part)
            assert.are.equal(1, spy.called)
            assert.are.same({ x = 5, y = 6 }, spy.data)
        end)

        it("refuses placement when any footprint tile is occupied, leaving all four untouched", function()
            local w = World.new(1)
            World.build_road(w, 6, 7) -- one corner blocked
            local spy = spy_on(C.EVENTS.PLANT_BUILT)
            assert.is_false(World.build_plant(w, 5, 6))
            assert.is_nil(tile_at(w, 5, 6).plant)
            assert.is_nil(tile_at(w, 6, 6).plant_part)
            assert.is_nil(tile_at(w, 5, 7).plant_part)
            assert.is_true(tile_at(w, 6, 7).road) -- the road is undisturbed
            assert.are.equal(0, spy.called)
        end)

        it("refuses placement when the footprint runs off the grid", function()
            local w = World.new(1)
            local spy = spy_on(C.EVENTS.PLANT_BUILT)
            assert.is_false(World.build_plant(w, w.grid.width, 6))  -- x+1 off-grid
            assert.is_false(World.build_plant(w, 6, w.grid.height)) -- y+1 off-grid
            assert.are.equal(0, spy.called)
        end)

        it("build_road, build_power_line and zone_tile all refuse a plant or plant_part tile", function()
            local w = World.new(1)
            World.build_plant(w, 5, 6)
            assert.is_false(World.build_road(w, 5, 6))       -- anchor
            assert.is_false(World.build_power_line(w, 6, 6)) -- part
            assert.is_false(World.zone_tile(w, 5, 7, C.ZONE.RESIDENTIAL)) -- part
        end)

        it("bulldoze on the anchor removes all four tiles and publishes plant_removed", function()
            local w = World.new(1)
            World.build_plant(w, 5, 6)
            local removed = spy_on(C.EVENTS.PLANT_REMOVED)
            local bulldozed = spy_on(C.EVENTS.TILE_BULLDOZED)
            assert.is_true(World.bulldoze(w, 5, 6))
            assert.is_nil(tile_at(w, 5, 6).plant)
            assert.is_nil(tile_at(w, 6, 6).plant_part)
            assert.is_nil(tile_at(w, 5, 7).plant_part)
            assert.is_nil(tile_at(w, 6, 7).plant_part)
            assert.are.equal(1, removed.called)
            assert.are.same({ x = 5, y = 6 }, removed.data)
            assert.are.equal(0, bulldozed.called)
        end)

        it("bulldoze on a part tile removes the whole plant, reporting the anchor", function()
            local w = World.new(1)
            World.build_plant(w, 5, 6)
            local removed = spy_on(C.EVENTS.PLANT_REMOVED)
            assert.is_true(World.bulldoze(w, 6, 7)) -- the far corner part
            assert.is_nil(tile_at(w, 5, 6).plant)
            assert.is_nil(tile_at(w, 6, 7).plant_part)
            assert.are.same({ x = 5, y = 6 }, removed.data)
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

        it("jobs sum completed commercial and industrial at their per-zone rates", function()
            local w = World.new(1)
            build(w, 1, 1, C.ZONE.COMMERCIAL)
            build(w, 2, 1, C.ZONE.COMMERCIAL)
            build(w, 3, 1, C.ZONE.INDUSTRIAL)
            assert.are.equal(2 * C.JOBS_PER_COM + 1 * C.JOBS_PER_IND, World.jobs(w))
        end)

        it("building_count totals completed buildings across all zones", function()
            local w = World.new(1)
            build(w, 1, 1, C.ZONE.RESIDENTIAL)
            build(w, 2, 1, C.ZONE.COMMERCIAL)
            build(w, 3, 1, C.ZONE.INDUSTRIAL)
            World.zone_tile(w, 4, 1, C.ZONE.RESIDENTIAL)
            World.start_building(w, 4, 1) -- constructing, not counted
            assert.are.equal(3, World.building_count(w))
        end)
    end)
end)
