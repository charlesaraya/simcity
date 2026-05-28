-- spec/ui/name_picker_spec.lua
-- The name picker is the deterministic seam between the curated content pools
-- and the charter screen. Pure module — RNG is passed in (not module state),
-- so two pickers seeded the same draw the same names. Tested headless.

local NamePicker = require("src.ui.name_picker")
local RNG = require("src.sim.rng")
local C = require("src.world.constants")
local crew_names = require("src.ui.content.crew_names")
local mission_names = require("src.ui.content.mission_names")
local traits = require("src.ui.content.traits")

describe("NamePicker.pick (deterministic single draw)", function()
    it("returns an element from the pool", function()
        local rng = RNG.new(7)
        local pool = { "a", "b", "c", "d" }
        local v = NamePicker.pick(rng, pool)
        local found = false
        for _, e in ipairs(pool) do if e == v then found = true end end
        assert.is_true(found)
    end)

    it("is deterministic for the same seed", function()
        local a = NamePicker.pick(RNG.new(42), crew_names)
        local b = NamePicker.pick(RNG.new(42), crew_names)
        assert.are.equal(a, b)
    end)

    it("advances the rng state (two consecutive picks usually differ)", function()
        local rng = RNG.new(99)
        local first = NamePicker.pick(rng, crew_names)
        local second = NamePicker.pick(rng, crew_names)
        -- They could collide by chance, but the rng state has changed.
        assert.are_not.equal(rng.state, RNG.new(99).state)
        -- Sanity: both are pool entries.
        assert.is_string(first)
        assert.is_string(second)
    end)
end)

describe("NamePicker.default_crew", function()
    it("returns exactly team_size entries", function()
        for n = 1, 5 do
            local crew = NamePicker.default_crew(RNG.new(1), n)
            assert.are.equal(n, #crew)
        end
    end)

    it("each entry has name, role, traits (table), and status='active'", function()
        local crew = NamePicker.default_crew(RNG.new(3), 5)
        for _, member in ipairs(crew) do
            assert.is_string(member.name)
            assert.is_number(member.role)
            assert.is_table(member.traits)
            assert.are.equal(C.STATUS.ACTIVE, member.status)
        end
    end)

    it("slot 1 is always Commander", function()
        for seed = 1, 5 do
            local crew = NamePicker.default_crew(RNG.new(seed), 3)
            assert.are.equal(C.ROLE.COMMANDER, crew[1].role)
        end
    end)

    it("names are unique within the crew (drawn without replacement)", function()
        local crew = NamePicker.default_crew(RNG.new(11), 5)
        local seen = {}
        for _, m in ipairs(crew) do
            assert.is_nil(seen[m.name], "duplicate crew name: " .. m.name)
            seen[m.name] = true
        end
    end)

    it("is deterministic for the same seed", function()
        local a = NamePicker.default_crew(RNG.new(123), 4)
        local b = NamePicker.default_crew(RNG.new(123), 4)
        for i = 1, #a do
            assert.are.equal(a[i].name, b[i].name)
            assert.are.equal(a[i].role, b[i].role)
        end
    end)

    it("traits are drawn from the role's trait pool", function()
        local crew = NamePicker.default_crew(RNG.new(77), 5)
        for _, m in ipairs(crew) do
            local pool = traits[m.role]
            assert.is_table(pool, "no trait pool for role " .. tostring(m.role))
            for _, t in ipairs(m.traits) do
                local found = false
                for _, p in ipairs(pool) do if p == t then found = true end end
                assert.is_true(found, ("trait %q not in role %d's pool"):format(t, m.role))
            end
        end
    end)
end)

describe("NamePicker.default_mission_name", function()
    it("returns a string from the mission_names pool", function()
        local name = NamePicker.default_mission_name(RNG.new(1))
        local found = false
        for _, e in ipairs(mission_names) do if e == name then found = true end end
        assert.is_true(found)
    end)

    it("is deterministic for the same seed", function()
        assert.are.equal(
            NamePicker.default_mission_name(RNG.new(8)),
            NamePicker.default_mission_name(RNG.new(8)))
    end)
end)

describe("content pools", function()
    it("crew_names has at least 20 entries", function()
        assert.is_true(#crew_names >= 20, "crew_names too small: " .. #crew_names)
    end)

    it("mission_names has at least 20 entries", function()
        assert.is_true(#mission_names >= 20, "mission_names too small: " .. #mission_names)
    end)

    it("traits defines a non-empty pool for every role", function()
        for _, role in pairs(C.ROLE) do
            assert.is_table(traits[role], "no traits for role " .. role)
            assert.is_true(#traits[role] > 0, "empty traits for role " .. role)
        end
    end)
end)
