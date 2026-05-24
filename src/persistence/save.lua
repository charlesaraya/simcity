-- src/persistence/save.lua
-- Save and load the world. Because the world is entirely plain data (the RNG is
-- a pure-Lua {state} table), serialization is just dumping the whole table --
-- no hand-written conversion. That is the dividend of the data-is-data rule.
--
-- The pure serialize/deserialize pair is testable headless. The save/load
-- wrappers add love.filesystem I/O and only run inside LÖVE.

local serpent = require("vendor.serpent")

local Save = {}

local SLOT_FMT = "save%d.lua" -- written into LÖVE's save directory (identity)

-- Pure: world table -> string (a self-contained Lua chunk).
function Save.serialize(world)
    return serpent.dump(world)
end

-- Pure: string -> world table, or nil on failure. serpent.load runs in a safe
-- environment, so malformed input fails rather than executing.
function Save.deserialize(str)
    local ok, world = serpent.load(str)
    if not ok then return nil end
    return world
end

-- LÖVE-only: write the serialized world to a save slot.
function Save.save(world, slot)
    local name = SLOT_FMT:format(slot or 1)
    return love.filesystem.write(name, Save.serialize(world))
end

-- LÖVE-only: read and deserialize a save slot, or nil if it doesn't exist.
function Save.load(slot)
    local name = SLOT_FMT:format(slot or 1)
    if not love.filesystem.getInfo(name) then return nil end
    return Save.deserialize(love.filesystem.read(name))
end

return Save
