-- src/sim/rng.lua
-- Deterministic pseudo-random generator (xorshift32). The entire state is a
-- single 32-bit integer, so it serializes trivially and a reload replays the
-- exact same sequence -- the basis for reproducible growth and lossless saves.
--
-- Uses LuaJIT's `bit` library (bit.bxor/lshift/rshift). This is why the test
-- runtime is pinned to LuaJIT to match LÖVE: plain Lua 5.1 has no bit ops.

local bit = require("bit")

local RNG = {}

local DEFAULT_SEED = 0x2545F491 -- arbitrary nonzero; xorshift is stuck at 0
local TWO32 = 4294967296        -- 2^32

-- Wrap an existing state integer (used by load() to restore a saved generator).
function RNG.from_state(state)
    return { state = state }
end

-- New generator from a seed. Seed 0 is replaced because xorshift cannot leave 0.
function RNG.new(seed)
    local s = seed or DEFAULT_SEED
    if s == 0 then s = DEFAULT_SEED end
    return { state = bit.tobit(s) } -- normalize to a 32-bit value
end

-- Advance the state and return a float in [0, 1).
function RNG.random(rng)
    local x = rng.state
    x = bit.bxor(x, bit.lshift(x, 13))
    x = bit.bxor(x, bit.rshift(x, 17))
    x = bit.bxor(x, bit.lshift(x, 5))
    rng.state = x
    -- bit ops yield a signed 32-bit number; floored mod makes it non-negative.
    return (x % TWO32) / TWO32
end

-- Convenience: true with probability p. p<=0 never, p>=1 always.
function RNG.chance(rng, p)
    return RNG.random(rng) < p
end

return RNG
