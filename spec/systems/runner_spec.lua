-- spec/systems/runner_spec.lua
-- The runner sub-steps each system on its own interval. The fast-forward
-- guarantee lives here: a big dt fires as many ticks as elapsed, never skipping.

local Runner = require("src.systems.runner")

describe("Runner", function()
    it("fires a system once when accumulated dt reaches its interval", function()
        local r = Runner.new()
        local n = 0
        Runner.add(r, { interval = 1.0, tick = function() n = n + 1 end })
        Runner.update(r, 0.4, nil)
        assert.are.equal(0, n) -- not yet
        Runner.update(r, 0.7, nil)
        assert.are.equal(1, n) -- 0.4 + 0.7 = 1.1 >= 1.0
    end)

    it("sub-steps: one big dt fires multiple ticks and keeps the remainder", function()
        local r = Runner.new()
        local n = 0
        local sys = Runner.add(r, { interval = 1.0, tick = function() n = n + 1 end })
        Runner.update(r, 3.5, nil)
        assert.are.equal(3, n)              -- floor(3.5 / 1.0)
        assert.is_true(math.abs(sys.accumulator - 0.5) < 1e-9) -- remainder carried
    end)

    it("is equivalent whether time arrives in one chunk or many (fast-forward determinism)", function()
        local big, small = Runner.new(), Runner.new()
        local nb, ns = 0, 0
        Runner.add(big, { interval = 1.0, tick = function() nb = nb + 1 end })
        Runner.add(small, { interval = 1.0, tick = function() ns = ns + 1 end })

        Runner.update(big, 10.0, nil)            -- one fast-forward frame
        for _ = 1, 10 do Runner.update(small, 1.0, nil) end -- ten normal frames
        assert.are.equal(nb, ns)
        assert.are.equal(10, nb)
    end)

    it("runs systems with independent intervals", function()
        local r = Runner.new()
        local fast, slow = 0, 0
        Runner.add(r, { interval = 0.5, tick = function() fast = fast + 1 end })
        Runner.add(r, { interval = 2.0, tick = function() slow = slow + 1 end })
        Runner.update(r, 2.0, nil)
        assert.are.equal(4, fast)
        assert.are.equal(1, slow)
    end)

    it("passes the world through to tick", function()
        local r = Runner.new()
        local seen
        local world = { tag = "w" }
        Runner.add(r, { interval = 1.0, tick = function(w) seen = w end })
        Runner.update(r, 1.0, world)
        assert.are.equal(world, seen)
    end)
end)
