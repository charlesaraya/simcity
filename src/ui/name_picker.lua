-- src/ui/name_picker.lua
-- Deterministic seam between the curated content pools and the New Mission
-- charter screen. Pure module: the rng is PASSED IN (caller owns its state),
-- so the same rng state produces the same crew + mission name across runs --
-- making the charter screen testable headless and reproducible from a seed.
--
-- API:
--   pick(rng, pool)                -> one entry; advances rng by one step
--   default_crew(rng, team_size)   -> N crew tables, slot 1 always Commander,
--                                     names drawn without replacement, one
--                                     trait per member from the role's pool
--   default_mission_name(rng)      -> a string from mission_names

local C = require("src.world.constants")
local RNG = require("src.sim.rng")
local crew_names = require("src.ui.content.crew_names")
local mission_names = require("src.ui.content.mission_names")
local traits = require("src.ui.content.traits")

local NamePicker = {}

-- Single deterministic draw. RNG.random returns [0, 1); the floor + 1 maps to
-- a 1-based pool index.
local function pick_index(rng, n)
    return math.floor(RNG.random(rng) * n) + 1
end

function NamePicker.pick(rng, pool)
    return pool[pick_index(rng, #pool)]
end

-- Draw `count` distinct entries from `pool`. Bounded-loop reservoir: pick an
-- index, retry on collision -- fine because count is small (<=5) and the
-- crew_names pool is ~30 long, so collision odds stay tiny.
local function pick_distinct(rng, pool, count)
    local taken = {}
    local out = {}
    for i = 1, count do
        local idx
        repeat idx = pick_index(rng, #pool) until not taken[idx]
        taken[idx] = true
        out[i] = pool[idx]
    end
    return out
end

-- Default crew composition. Slot 1 is always Commander; slots 2..N take roles
-- in C.ROLE_ORDER order. Each member gets one trait drawn from their role's
-- pool. Status starts as ACTIVE (the only status 4c writes).
function NamePicker.default_crew(rng, team_size)
    local names = pick_distinct(rng, crew_names, team_size)
    local crew = {}
    for i = 1, team_size do
        local role = C.ROLE_ORDER[i]
        local trait = NamePicker.pick(rng, traits[role])
        crew[i] = {
            name = names[i],
            role = role,
            traits = { trait },
            status = C.STATUS.ACTIVE,
        }
    end
    return crew
end

function NamePicker.default_mission_name(rng)
    return NamePicker.pick(rng, mission_names)
end

return NamePicker
