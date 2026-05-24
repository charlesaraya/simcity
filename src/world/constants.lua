-- src/world/constants.lua
-- Every tunable number and enum in one place.

local C        = {}

-- Isometric tile footprint, in pixels. Classic 2:1 diamond (width = 2 * height).
C.TILE_W       = 64
C.TILE_H       = 32

-- World dimensions, in tiles.
C.GRID_W       = 64
C.GRID_H       = 64

-- Tile types. Plain integers (cheap to store/compare/serialize).
C.TILE         = {
    GRASS = 1,
}

-- Colors as {r, g, b} in 0..1 (LÖVE's range). The checkerboard alternates these
-- so we can SEE individual tiles and catch picking bugs.
C.COLOR        = {
    GRASS_A       = { 0.42, 0.60, 0.36 },
    GRASS_B       = { 0.38, 0.55, 0.33 },
    TILE_LINE     = { 0.20, 0.28, 0.18 }, -- diamond outline
    HIGHLIGHT     = { 1.00, 0.95, 0.50 }, -- tile under cursor
    BG            = { 0.10, 0.11, 0.13 },

    -- Zoned-but-empty tile tints (so a plan is visible before it grows).
    ZONE_RES      = { 0.30, 0.45, 0.28 },
    ZONE_COM      = { 0.26, 0.36, 0.50 },

    -- Building markers drawn on top of a tile.
    BUILD_RES     = { 0.55, 0.85, 0.45 }, -- completed residential
    BUILD_COM     = { 0.45, 0.70, 0.95 }, -- completed commercial
    BUILD_PENDING = { 0.60, 0.60, 0.60 }, -- under construction (any zone)
}

-- Camera tuning.
C.CAM          = {
    PAN_SPEED = 600,  -- world pixels per second at zoom = 1
    ZOOM_MIN  = 0.25, -- furthest out
    ZOOM_MAX  = 4.0,  -- closest in
    ZOOM_STEP = 1.1,  -- scale multiplier per wheel notch
}

-- Zone a tile can hold. NONE = unzoned grass.
C.ZONE         = {
    NONE        = 0,
    RESIDENTIAL = 1,
    COMMERCIAL  = 2,
}

-- Building lifecycle states.
C.BUILD        = {
    CONSTRUCTING = 1,
    COMPLETE     = 2,
}

-- Population / jobs contributed by one completed building.
C.POP_PER_RES  = 4
C.JOBS_PER_COM = 4

-- Demand tuning. BASE_RES seeds an empty city (residents always want in a bit),
-- otherwise nothing ever grows. SENS is the demand shift per building imbalance.
C.DEMAND       = {
    BASE_RES = 0.3,
    SENS     = 0.1,
}

-- Growth tuning. RATE scales positive demand into a per-month build chance.
-- CONSTRUCTION_TICKS months to finish. Buildings abandon only when demand drops
-- below ABANDON_THRESHOLD, at a chance scaled by ABANDON_RATE.
C.GROWTH       = {
    RATE               = 0.15,
    CONSTRUCTION_TICKS = 2,
    ABANDON_THRESHOLD  = -0.5,
    ABANDON_RATE       = 0.1,
}

-- Simulation time. One "month" is the base tick unit; the clock counts elapsed
-- months and derives a calendar date from them.
C.SIM          = {
    SECONDS_PER_MONTH = 1.0, -- sim-seconds per month at speed 1
    MONTHS_PER_YEAR   = 12,
    START_YEAR        = 1900,
}

-- Game speed factors. Real dt is multiplied by one of these.
C.SPEED        = {
    PAUSED = 0,
    NORMAL = 1,
    FAST   = 8,
}

-- Player tools.
C.TOOL         = {
    BULLDOZE = 1,
    ZONE_RES = 2,
    ZONE_COM = 3,
}

-- Event names published by world-state writers (Principle 4).
C.EVENTS       = {
    TILE_ZONED           = "tile_zoned",
    TILE_BULLDOZED       = "tile_bulldozed",
    BUILDING_CONSTRUCTED = "building_constructed",
    BUILDING_ABANDONED   = "building_abandoned",
    MONTH_ELAPSED        = "month_elapsed",
}

return C
