-- src/ui/theme.lua
-- Owns the menu-screen visual register. Here lives the PALETTE lookup and the
-- named FONTS loaded once at boot from assets/fonts. Anything else that wants
-- to draw a menu reads its color and font through this module, so the look changes
-- in one place.

local C = require("src.world.constants")

local Theme = {}

-- Role -> (path, size). The four roles cover the screens' type rhythm:
--   display = title/screen headings (slab serif, biggest)
--   heading = section headings (slab serif, mid)
--   body    = body, data, lists (mono)
--   meta    = small captions, status strips (mono, small)
local SPECS = {
    display = { "assets/fonts/IBMPlexSerif-Bold.ttf", 28 },
    heading = { "assets/fonts/IBMPlexSerif-Bold.ttf", 20 },
    body    = { "assets/fonts/IBMPlexMono-Regular.ttf", 16 },
    meta    = { "assets/fonts/IBMPlexMono-Regular.ttf", 13 },
}

local fonts = nil

-- READ: palette color by token name.
function Theme.color(name)
    return C.UI[name]
end

-- Load the four fonts via a caller-supplied loader. Production: main.lua calls
-- Theme.init(love.graphics.newFont) at love.load time. Tests pass a stub loader
-- so this module stays headless-testable. Idempotent: a second call replaces
-- the previous handles.
function Theme.init(loader)
    fonts = {}
    for role, spec in pairs(SPECS) do
        fonts[role] = loader(spec[1], spec[2])
    end
end

-- READ: the loaded font for a role, or nil if init hasn't been called yet (or
-- the role is unknown). Renderers should call init at boot before drawing.
function Theme.font(role)
    return fonts and fonts[role] or nil
end

return Theme
