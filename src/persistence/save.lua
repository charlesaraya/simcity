-- src/persistence/save.lua
-- Save and load the world. Because the world is entirely plain data (the RNG
-- is a pure-Lua {state} table), serialization is just dumping the whole table
-- -- no hand-written conversion.
--
-- Phase 4c-2: the on-disk layout is slug-based:
--   saves/<slug>/world.lua  -- this module writes / reads here
--   saves/<slug>/meta.lua   -- the metadata sidecar (see Meta module)
-- A migration helper moves legacy save1.lua..save6.lua flat files into the
-- new layout on first launch.

local serpent = require("vendor.serpent")
local Meta = require("src.persistence.meta")

local Save = {}

-- Pure: world table -> string.
function Save.serialize(world)
    return serpent.dump(world)
end

-- Pure: string -> world table, or nil on failure.
function Save.deserialize(str)
    local ok, world = serpent.load(str)
    if not ok then return nil end
    return world
end

-- LÖVE-only: write the serialized world to saves/<slug>/world.lua. Creates
-- the slug directory if missing.
function Save.save(world, slug)
    if not love.filesystem.getInfo(Meta.dir(slug)) then
        love.filesystem.createDirectory(Meta.dir(slug))
    end
    return love.filesystem.write(Meta.world_path(slug), Save.serialize(world))
end

-- LÖVE-only: read and deserialize the world for a slug, or nil if missing.
-- love.filesystem.read returns (contents, size); capture the first only so
-- the second arg doesn't leak into anything we pass it to.
function Save.load(slug)
    local path = Meta.world_path(slug)
    if not love.filesystem.getInfo(path) then return nil end
    local contents = love.filesystem.read(path)
    if not contents then return nil end
    return Save.deserialize(contents)
end

-- LÖVE-only: one-shot migration of legacy slot files (save1.lua..save6.lua
-- at the root of love.filesystem) into the slug-based layout. For each legacy
-- file, deserialize, mint a slug ("legacy-N"), write saves/<slug>/world.lua,
-- synthesize a minimal meta sidecar (no time_played; saved_at = now), and
-- remove the legacy file. Idempotent: re-running after migration is a no-op.
function Save.migrate_legacy()
    for i = 1, 6 do
        local legacy = ("save%d.lua"):format(i)
        if love.filesystem.getInfo(legacy) then
            local data = love.filesystem.read(legacy)
            local world = Save.deserialize(data)
            if world then
                local slug = "legacy-" .. i
                Save.save(world, slug)
                Meta.save(slug, Meta.from_world(world, {
                    slug       = slug,
                    saved_at   = os.time(),
                    time_played = 0,
                    population = 0, -- legacy saves get a 0 placeholder; first
                                    -- F5 after load will recompute.
                }))
            end
            love.filesystem.remove(legacy)
        end
    end
end

return Save
