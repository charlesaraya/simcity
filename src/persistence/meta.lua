-- src/persistence/meta.lua
-- Save-metadata sidecar. The Archive screen browses saved missions by
-- reading these (cheap) instead of loading each world (expensive). Pure
-- helpers (slugify, from_world, path joiners) are headless-testable; the
-- love.filesystem-backed read / write / list are run-verified.
--
-- Layout (Phase 4c-2):
--   saves/<slug>/world.lua  -- the full serialized world
--   saves/<slug>/meta.lua   -- this sidecar
--
-- A mission's slug is derived once at charter time (from its name) and lives
-- on world.slug so subsequent saves overwrite the same directory. Conflict
-- resolution (e.g. "Janus-IV" picked twice) is the caller's responsibility:
-- main.lua picks a unique slug via Meta.unique_slug when the player charters.

local serpent = require("vendor.serpent")
local C = require("src.world.constants")

local Meta = {}

local SAVES_ROOT = "saves"

-- Lowercase alphanumeric kebab-case slug. Non-alphanumeric runs collapse to
-- single hyphens; leading/trailing hyphens trimmed. Empty results fall back
-- to "mission" so we always return something writable.
function Meta.slugify(name)
    name = tostring(name or "")
    name = name:lower()
    name = name:gsub("[^a-z0-9]+", "-")
    name = name:gsub("^%-+", ""):gsub("%-+$", "")
    if name == "" then name = "mission" end
    return name
end

-- Path helpers -- pure, deterministic.
function Meta.dir(slug)
    return SAVES_ROOT .. "/" .. slug
end

function Meta.world_path(slug)
    return Meta.dir(slug) .. "/world.lua"
end

function Meta.meta_path(slug)
    return Meta.dir(slug) .. "/meta.lua"
end

-- Extract a sidecar metadata table from a world. Callers inject saved_at,
-- time_played, population, and the resolved slug; everything else comes off
-- the world. Robust against missing fields (legacy saves with no
-- world.mission table just get nil fields, not a crash).
function Meta.from_world(world, opts)
    opts = opts or {}
    local mission = world.mission or {}
    local months = (world.clock and world.clock.months) or 0
    return {
        slug         = opts.slug,
        mission_name = mission.name,
        difficulty   = mission.difficulty,
        world_params = mission.world_params,
        cycle        = math.floor(months / C.SIM.MONTHS_PER_YEAR),
        population   = opts.population or 0,
        treasury     = world.treasury or 0,
        saved_at     = opts.saved_at,
        time_played  = opts.time_played or 0,
    }
end

-- LÖVE-only: write the sidecar. Creates the slug directory if missing.
function Meta.save(slug, meta)
    if not love.filesystem.getInfo(Meta.dir(slug)) then
        love.filesystem.createDirectory(Meta.dir(slug))
    end
    return love.filesystem.write(Meta.meta_path(slug), serpent.dump(meta))
end

-- LÖVE-only: read the sidecar for a slug. Returns nil if missing or malformed.
-- Note: love.filesystem.read returns (contents, size); the inline two-return
-- would otherwise reach serpent.load as a (str, opts=size) call and crash.
function Meta.load(slug)
    local path = Meta.meta_path(slug)
    if not love.filesystem.getInfo(path) then return nil end
    local contents = love.filesystem.read(path)
    if not contents then return nil end
    local ok, meta = serpent.load(contents)
    if not ok then return nil end
    return meta
end

-- LÖVE-only: list all saved missions' metas, sorted by saved_at descending
-- (newest first). Skips slugs whose meta file is missing or malformed.
function Meta.list()
    local out = {}
    if not love.filesystem.getInfo(SAVES_ROOT) then return out end
    for _, slug in ipairs(love.filesystem.getDirectoryItems(SAVES_ROOT)) do
        local m = Meta.load(slug)
        if m then
            m.slug = m.slug or slug -- self-heal if sidecar predates the field
            out[#out + 1] = m
        end
    end
    table.sort(out, function(a, b)
        return (a.saved_at or 0) > (b.saved_at or 0)
    end)
    return out
end

-- LÖVE-only: pick a slug not yet on disk by appending -2, -3, ... if the
-- base is taken. Lets two missions named "Janus-IV" coexist as janus-iv and
-- janus-iv-2.
function Meta.unique_slug(base)
    local slug = base
    local n = 1
    while love.filesystem.getInfo(Meta.dir(slug)) do
        n = n + 1
        slug = base .. "-" .. n
    end
    return slug
end

-- LÖVE-only: remove a saved mission's directory.
function Meta.delete(slug)
    local dir = Meta.dir(slug)
    if not love.filesystem.getInfo(dir) then return end
    love.filesystem.remove(Meta.meta_path(slug))
    love.filesystem.remove(Meta.world_path(slug))
    love.filesystem.remove(dir)
end

return Meta
