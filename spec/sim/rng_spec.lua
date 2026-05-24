-- spec/sim/rng_spec.lua
-- A deterministic pseudo-random generator: same seed => same sequence; its whole
-- state is one integer, so it serializes trivially and a reload replays exactly.

local RNG = require("src.sim.rng")

describe("RNG", function()
    it("produces floats in [0, 1)", function()
        local r = RNG.new(12345)
        for _ = 1, 1000 do
            local v = RNG.random(r)
            assert.is_true(v >= 0 and v < 1)
        end
    end)

    it("is deterministic: same seed yields the same sequence", function()
        local a, b = RNG.new(777), RNG.new(777)
        for _ = 1, 100 do
            assert.are.equal(RNG.random(a), RNG.random(b))
        end
    end)

    it("diverges for different seeds", function()
        local a, b = RNG.new(1), RNG.new(2)
        local same = true
        for _ = 1, 50 do
            if RNG.random(a) ~= RNG.random(b) then same = false break end
        end
        assert.is_false(same)
    end)

    it("restores from a captured state and replays the same values", function()
        local r = RNG.new(42)
        for _ = 1, 10 do RNG.random(r) end -- advance
        local state = r.state
        local expected = { RNG.random(r), RNG.random(r), RNG.random(r) }

        local restored = RNG.from_state(state)
        assert.are.equal(expected[1], RNG.random(restored))
        assert.are.equal(expected[2], RNG.random(restored))
        assert.are.equal(expected[3], RNG.random(restored))
    end)

    it("chance() honors the extremes", function()
        local r = RNG.new(99)
        for _ = 1, 50 do
            assert.is_false(RNG.chance(r, 0.0)) -- never
            assert.is_true(RNG.chance(r, 1.0))  -- always
        end
    end)
end)
