-- spec/persistence/save_meta_spec.lua
-- The meta sidecar: a small table written alongside the world so the Archive
-- can browse saved missions without loading each world. Pure parts (slugify,
-- from_world, path helpers) are spec'd here; the love.filesystem-backed read
-- / write / list are run-verified.

local Meta = require("src.persistence.meta")
local C = require("src.world.constants")

describe("Meta.slugify", function()
    it("lowercases and converts non-alphanumerics to hyphens", function()
        assert.are.equal("janus-iv", Meta.slugify("Janus-IV"))
        assert.are.equal("tabr-khel", Meta.slugify("Tabr Khel"))
        assert.are.equal("arrakeen-mn", Meta.slugify("ARRAKEEN-MN"))
    end)

    it("collapses runs of hyphens and trims leading/trailing", function()
        assert.are.equal("hello-world", Meta.slugify("  Hello!!--World  "))
    end)

    it("falls back to 'mission' for empty / all-punct input", function()
        assert.are.equal("mission", Meta.slugify(""))
        assert.are.equal("mission", Meta.slugify("!!!"))
    end)
end)

describe("Meta.path helpers", function()
    it("dir(slug) returns saves/<slug>", function()
        assert.are.equal("saves/janus-iv", Meta.dir("janus-iv"))
    end)

    it("world_path / meta_path live inside dir", function()
        assert.are.equal("saves/x/world.lua", Meta.world_path("x"))
        assert.are.equal("saves/x/meta.lua",  Meta.meta_path("x"))
    end)
end)

describe("Meta.from_world", function()
    local function fake_world()
        return {
            clock    = { months = 36 },
            treasury = 1500,
            mission  = {
                name = "Janus-IV",
                difficulty = "first_mission",
                world_params = { size = "Medium", climate = "Temperate" },
            },
        }
    end

    -- Stub World.population so the spec doesn't depend on the full world shape.
    -- Meta uses a small read function it accepts; we inject a count here.
    it("captures mission name, slug, cycle, treasury, difficulty, world_params", function()
        local m = Meta.from_world(fake_world(), {
            slug         = "janus-iv",
            saved_at     = 12345,
            time_played  = 87,
            population   = 48,
        })
        assert.are.equal("Janus-IV", m.mission_name)
        assert.are.equal("janus-iv", m.slug)
        assert.are.equal(3, m.cycle) -- 36 / 12
        assert.are.equal(48, m.population)
        assert.are.equal(1500, m.treasury)
        assert.are.equal("first_mission", m.difficulty)
        assert.are.equal(12345, m.saved_at)
        assert.are.equal(87, m.time_played)
        assert.is_table(m.world_params)
        assert.are.equal("Medium", m.world_params.size)
    end)

    it("tolerates a world with no mission table (legacy save)", function()
        local w = { clock = { months = 0 }, treasury = 0 }
        local m = Meta.from_world(w, { slug = "legacy_1", saved_at = 1, time_played = 0, population = 0 })
        assert.is_nil(m.mission_name)
        assert.are.equal("legacy_1", m.slug)
        assert.are.equal(0, m.cycle)
    end)
end)
