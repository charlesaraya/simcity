-- spec/persistence/save_spec.lua
-- Save/load is split: serialize/deserialize are pure (tested here); the
-- love.filesystem save/load wrappers are LÖVE-only and exercised by running the
-- game. Because the world is 100% plain data (pure-Lua RNG), a round-trip must
-- reproduce it exactly -- including rng state, so the reloaded city replays the
-- same future. That is the data-is-data proof.

local Save = require("src.persistence.save")
local World = require("src.world.world")
local Growth = require("src.systems.growth")
local Roads = require("src.systems.roads")
local Power = require("src.systems.power")
local RNG = require("src.sim.rng")
local Bus = require("src.bus")
local C = require("src.world.constants")

-- The building layout as a comparable table: tile index -> state (0 = none).
local function layout(w)
    local t = {}
    for i = 1, #w.grid.tiles do
        local b = w.grid.tiles[i].building
        t[i] = b and b.state or 0
    end
    return t
end

describe("Save", function()
    before_each(function() Bus.clear() end)

    it("round-trips a world, including rng state, clock, demand, economy, and grid", function()
        local w = World.new(42)
        World.zone_tile(w, 1, 1, C.ZONE.RESIDENTIAL)
        World.start_building(w, 1, 1)
        World.complete_building(w, 1, 1)
        w.demand.residential = 0.5
        w.clock.months = 7
        w.treasury = 1234
        w.economy.last_net = -7
        RNG.random(w.rng); RNG.random(w.rng) -- advance the generator

        local w2 = Save.deserialize(Save.serialize(w))

        assert.are.equal(w.rng.state, w2.rng.state)
        assert.are.equal(w.clock.months, w2.clock.months)
        assert.are.same(w.demand, w2.demand)
        assert.are.equal(w.treasury, w2.treasury)
        assert.are.same(w.economy, w2.economy)
        assert.are.same(w.grid, w2.grid)
    end)

    it("reloaded world replays identical growth", function()
        local function seeded()
            local w = World.new(2024)
            for y = 1, 8 do World.build_road(w, 1, y) end -- connected left-edge road
            Roads.install(w)
            Power.install(w)
            World.build_plant(w, 1, 9) -- powers the road column (growth now needs power)
            for x = 1, 8 do
                for y = 1, 8 do World.zone_tile(w, x, y, C.ZONE.RESIDENTIAL) end
            end
            w.demand.residential = 0.8
            local g = Growth.system()
            for _ = 1, 5 do g.tick(w) end -- diverge from a fresh seed
            return w
        end

        local w = seeded()
        local w2 = Save.deserialize(Save.serialize(w)) -- save & reload mid-game

        -- Run the same future on both; they must stay identical.
        local g = Growth.system()
        for _ = 1, 10 do g.tick(w) end
        for _ = 1, 10 do g.tick(w2) end

        assert.are.same(layout(w), layout(w2))
        assert.is_true(World.count_buildings(w, C.ZONE.RESIDENTIAL) > 0)
    end)

    it("deserialize reports failure on garbage input", function()
        local ok = Save.deserialize("this is not lua {{{")
        assert.is_nil(ok)
    end)
end)
