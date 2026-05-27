-- src/render/ramp.lua
-- Pure value->color interpolation for the overlay heatmaps. Extracted from the
-- overlay renderer so the mapping is unit-tested headless (no LÖVE), like iso.lua.
-- Knows nothing about pollution or land value -- it just walks color stops.

local Ramp = {}

local function lerp(a, b, t)
    return a + (b - a) * t
end

-- Map `value` in [lo, hi] onto an ordered list of {r,g,b} `stops` (>= 1),
-- interpolating linearly across the equal-width segments between them. Values
-- outside [lo, hi] clamp to the end stops.
function Ramp.color(value, lo, hi, stops)
    local n = #stops
    if n == 1 then
        return { stops[1][1], stops[1][2], stops[1][3] }
    end

    local t = (hi > lo) and (value - lo) / (hi - lo) or 0
    if t < 0 then t = 0 elseif t > 1 then t = 1 end

    local pos = t * (n - 1) -- position along the (n-1) segments
    local i = math.floor(pos)
    if i >= n - 1 then
        return { stops[n][1], stops[n][2], stops[n][3] }
    end

    local f = pos - i
    local a, b = stops[i + 1], stops[i + 2]
    return { lerp(a[1], b[1], f), lerp(a[2], b[2], f), lerp(a[3], b[3], f) }
end

return Ramp
