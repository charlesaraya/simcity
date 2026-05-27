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
    GRASS_A         = { 0.42, 0.60, 0.36 },
    GRASS_B         = { 0.38, 0.55, 0.33 },
    TILE_LINE       = { 0.20, 0.28, 0.18 }, -- diamond outline
    HIGHLIGHT       = { 1.00, 0.95, 0.50 }, -- tile under cursor
    BG              = { 0.10, 0.11, 0.13 },

    -- Zoned-but-empty tile tints (so a plan is visible before it grows).
    ZONE_RES        = { 0.30, 0.45, 0.28 },
    ZONE_COM        = { 0.26, 0.36, 0.50 },
    ZONE_IND        = { 0.46, 0.40, 0.20 }, -- dim amber

    -- Building markers drawn on top of a tile.
    BUILD_RES       = { 0.55, 0.85, 0.45 }, -- completed residential
    BUILD_COM       = { 0.45, 0.70, 0.95 }, -- completed commercial
    BUILD_IND       = { 0.92, 0.78, 0.30 }, -- completed industrial (bright amber)
    BUILD_PENDING   = { 0.60, 0.60, 0.60 }, -- under construction (any zone)

    ROAD            = { 0.32, 0.32, 0.35 }, -- asphalt gray (programmer art)

    -- Power network.
    POWER_LINE      = { 0.55, 0.60, 0.78 }, -- steel-blue cable
    PLANT           = { 0.48, 0.40, 0.60 }, -- slate-purple, reads as special infra
    UNPOWERED       = { 0.95, 0.78, 0.20 }, -- amber dotted outline on dark buildings

    -- Drag-preview overlays (drawn translucent).
    PREVIEW_ROAD    = { 0.85, 0.78, 0.35 }, -- yellowish shadow
    PREVIEW_INVALID = { 0.85, 0.30, 0.30 }, -- can't build here / can't afford
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
    INDUSTRIAL  = 3,
}

-- Building lifecycle states.
C.BUILD        = {
    CONSTRUCTING = 1,
    COMPLETE     = 2,
}

-- Population / jobs contributed by one completed building.
C.POP_PER_RES  = 4
C.JOBS_PER_COM = 4
C.JOBS_PER_IND = 6 -- factories employ more than shops (first-pass, tunable)

-- Demand tuning.
-- BASE_RES seeds an empty city (residents always want in a bit),
--   otherwise nothing ever grows.
-- SENS is the demand shift per building imbalance.
-- COM_PER_RES / IND_PER_COM size each downstream tier as a FRACTION of the one
--   above (one shop serves several homes; one factory supplies several shops), so
--   the city settles around a 4:2:1 res:com:ind ratio.
-- JOB_PULL pulls more than one resident's worth of demand (>1), so the
--   loop gain exceeds 1: the city grows perpetually, in ratio.
C.DEMAND       = {
    BASE_RES    = 0.3,
    SENS        = 0.1,
    COM_PER_RES = 0.5,
    IND_PER_COM = 0.5,
    JOB_PULL    = 1.5,
}

-- Growth tuning.
-- RATE scales positive demand into a per-month build chance.
-- CONSTRUCTION_TICKS months to finish.
-- ABANDON_THRESHOLD: Buildings abandon only when demand drops below this threshold,
-- at a chance scaled by ABANDON_RATE.
-- LV_MIN_FACTOR floors the land-value bias on res/com starts: even the dirtiest
--   land grows, just slowly (factor ramps LV_MIN_FACTOR..1 with land value).
-- POLLUTION_ABANDON_THRESHOLD: completed res/com over this pollution level roll to
--   abandon (the 4th trigger); industry is immune.
C.GROWTH       = {
    RATE                        = 0.15,
    CONSTRUCTION_TICKS          = 2,
    ABANDON_THRESHOLD           = -0.5,
    ABANDON_RATE                = 0.1,
    LV_MIN_FACTOR               = 0.25,
    POLLUTION_ABANDON_THRESHOLD = 40,
}

-- Economy tuning.
-- Tax comes from JOBS (commerce + industry: where economic activity happens), and
-- UPKEEP falls only on those businesses (plus plant fuel). Residential housing is
-- FREE -- no tax, no upkeep -- so population is pure upside and the budget tracks
-- the commercial/industrial base. A res-only town is break-even; commerce and
-- industry turn the profit that funds everything else.
C.ECON         = {
    TAX_RATE       = 1, -- per job, per month
    UPKEEP         = 2, -- per completed BUSINESS (commerce/industry), per month
    START_TREASURY = 1500, -- runway to lay roads + a first plant before tax income ramps
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
    BULLDOZE   = 1,
    ZONE_RES   = 2,
    ZONE_COM   = 3,
    ZONE_IND   = 4,
    ROAD       = 5,
    POWER_LINE = 6,
    PLANT      = 7,
}

-- Road tuning. COST is a one-time charge per tile laid (no recurring upkeep).
C.ROAD         = {
    COST = 10,
}

-- One-time cost to zone a tile, charged at zoning.
-- Housing is cheap to encourage settlement; industry is priciest.
C.ZONE_COST    = {
    [C.ZONE.RESIDENTIAL] = 10,
    [C.ZONE.COMMERCIAL]  = 25,
    [C.ZONE.INDUSTRIAL]  = 40,
}

-- Power network tuning.
C.PLANT        = {
    FOOTPRINT = 2,   -- side length, in tiles (2 => a 2x2 footprint)
    CAPACITY  = 150, -- MW produced, only when road-connected (one plant covers a sizable district)
    COST      = 150, -- one-time build cost (affordable as an early purchase)
    UPKEEP    = 4,   -- monthly fuel, per plant (a real liability, not a budget-killer)
}

C.POWER_LINE   = {
    COST = 5, -- one-time, per tile; no upkeep (like roads)
}

-- MW drawn by one completed building of each zone. The zoning mix sizes the grid.
C.POWER_DRAW   = {
    [C.ZONE.RESIDENTIAL] = 2,
    [C.ZONE.COMMERCIAL]  = 3,
    [C.ZONE.INDUSTRIAL]  = 5,
}

-- Pollution diffusion (first-pass, tunable). Sources are completed industrial
-- buildings and power plants. Each source paints tiles within RADIUS with
-- strength * (1 - dist/RADIUS) [linear falloff]; overlapping sources add.
C.POLLUTION    = {
    IND_EMIT   = 10, -- strength at an industrial building's own tile
    PLANT_EMIT = 8,  -- strength at a plant's anchor tile
    RADIUS     = 6,  -- tiles; beyond this a source contributes nothing
}

-- Land value = clamp(BASE - K_POLLUTION * pollution, MIN, MAX). A pure read over
-- the pollution field; no diffusion of its own (Phase 5 amenities add a + term).
C.LAND         = {
    BASE        = 100,
    K_POLLUTION = 1.0, -- softened from 2.0: land value degrades gradually, so the
    MIN         = 0,   --   heatmap shows a real green->yellow->red gradient instead
    MAX         = 100, --   of snapping to red around any industry
}

-- Map overlay views (derived-state heatmaps). NONE = normal terrain render.
C.OVERLAY      = {
    NONE       = 0,
    POLLUTION  = 1,
    LAND_VALUE = 2,
    POWER      = 3,
}

-- Heatmap color stops (green -> yellow -> red). Pollution reads high = bad (red);
-- land value is the inverse (high = good = green), so its stops are reversed.
C.RAMP         = {
    POLLUTION  = { { 0.25, 0.65, 0.30 }, { 0.90, 0.80, 0.25 }, { 0.80, 0.25, 0.20 } },
    LAND_VALUE = { { 0.80, 0.25, 0.20 }, { 0.90, 0.80, 0.25 }, { 0.25, 0.65, 0.30 } },
}

-- Event names published by world-state writers (Principle 4).
C.EVENTS       = {
    TILE_ZONED           = "tile_zoned",
    TILE_BULLDOZED       = "tile_bulldozed",
    BUILDING_CONSTRUCTED = "building_constructed",
    BUILDING_ABANDONED   = "building_abandoned",
    MONTH_ELAPSED        = "month_elapsed",
    ROAD_BUILT           = "road_built",
    ROAD_REMOVED         = "road_removed",
    PLANT_BUILT          = "plant_built",
    PLANT_REMOVED        = "plant_removed",
    POWER_LINE_BUILT     = "power_line_built",
    POWER_LINE_REMOVED   = "power_line_removed",
}

return C
