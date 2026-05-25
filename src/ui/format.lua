-- src/ui/format.lua
-- Pure presentation helpers, kept out of the HUD so they're testable headless.

local Format = {}

-- Group an integer's digits in threes: 1234567 -> "1,234,567".
-- Sign preserved outside the grouping; fractional part dropped.
function Format.commas(n)
    local sign = n < 0 and "-" or ""
    local digits = tostring(math.abs(math.floor(n)))
    -- Reverse, insert a comma after every 3 digits, reverse back, drop a stray
    -- leading comma left when the length is an exact multiple of 3.
    local grouped = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return sign .. grouped
end

return Format
