-- src/ui/widgets.lua
-- Low-level draw primitives shared by the menu/modal screens. Extracted once
-- charter + Home both needed them — earlier extraction would have been guessing.
-- Pure love draw helpers, no state, no event hooks; safe to call from any draw.
--
-- The "CRT terminal" feel (amber fills + scanline striping) is approximated
-- here in pure rectangles — no shader pass, no pixel font. Step 10 polish may
-- replace this with a post-process if it's worth the cost.

local Theme = require("src.ui.theme")

local Widgets = {}

local SCANLINE_STEP  = 3    -- px between horizontal scanlines on filled cells
local SCANLINE_ALPHA = 0.22 -- intensity of the dark line over the amber fill
local DASH           = 6    -- dashed_hr dash length (px)

-- A thin double-line frame: the dim panel border used by charter / Home.
function Widgets.frame(x, y, w, h, color)
    love.graphics.setColor(color or Theme.color("dim_fg"))
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x, y, w, h)
    love.graphics.rectangle("line", x + 3, y + 3, w - 6, h - 6)
end

-- A simple outlined rectangle: name box, segmented cells, inactive buttons.
function Widgets.outline(x, y, w, h, color)
    love.graphics.setColor(color or Theme.color("dim_fg"))
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x, y, w, h)
end

-- A filled cell with horizontal scanlines drawn on top at low alpha — reads as
-- a "lit-up active" state. The caller should set the next color before
-- drawing text on top.
function Widgets.scanline_fill(x, y, w, h, color)
    love.graphics.setColor(color or Theme.color("amber"))
    love.graphics.rectangle("fill", x, y, w, h)
    love.graphics.setColor(0, 0, 0, SCANLINE_ALPHA)
    for sy = y + 1, y + h - 1, SCANLINE_STEP do
        love.graphics.line(x, sy, x + w, sy)
    end
end

-- A dashed horizontal rule (separator).
function Widgets.dashed_hr(x1, y, x2, color)
    love.graphics.setColor(color or Theme.color("dim_fg"))
    love.graphics.setLineWidth(1)
    for x = x1, x2 - DASH, DASH * 2 do
        love.graphics.line(x, y, x + DASH, y)
    end
end

return Widgets
