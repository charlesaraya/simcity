-- src/world/constants.lua
-- Every tunable number and enum in one place.

local C = {}

-- Isometric tile footprint, in pixels. Classic 2:1 diamond (width = 2 * height).
C.TILE_W = 64
C.TILE_H = 32

-- World dimensions, in tiles.
C.GRID_W = 64
C.GRID_H = 64

-- Tile types. Plain integers (cheap to store/compare/serialize).
C.TILE = {
    GRASS = 1,
}

-- Colors as {r, g, b} in 0..1 (LÖVE's range). The checkerboard alternates these
-- so we can SEE individual tiles and catch picking bugs.
C.COLOR = {
    GRASS_A   = { 0.42, 0.60, 0.36 },
    GRASS_B   = { 0.38, 0.55, 0.33 },
    TILE_LINE = { 0.20, 0.28, 0.18 },  -- diamond outline
    HIGHLIGHT = { 1.00, 0.95, 0.50 },  -- tile under cursor (Step F)
    BG        = { 0.10, 0.11, 0.13 },
}

-- Camera tuning.
C.CAM = {
    PAN_SPEED = 600,   -- world pixels per second at zoom = 1
    ZOOM_MIN  = 0.25,  -- furthest out
    ZOOM_MAX  = 4.0,   -- closest in
    ZOOM_STEP = 1.1,   -- scale multiplier per wheel notch
}

return C
