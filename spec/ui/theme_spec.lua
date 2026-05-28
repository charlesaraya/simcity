-- spec/ui/theme_spec.lua
-- Theme owns the menu-screen visual register: the palette tokens defined in
-- C.UI, and the four named fonts loaded from assets/fonts. Tested headless --
-- the palette lookup is pure Lua; the font load is wired through an injected
-- loader so we never call love.graphics.newFont from a spec.

local Theme = require("src.ui.theme")
local C = require("src.world.constants")

describe("Theme.color", function()
    it("returns the palette tokens defined in C.UI", function()
        assert.are.same(C.UI.bg, Theme.color("bg"))
        assert.are.same(C.UI.fg, Theme.color("fg"))
        assert.are.same(C.UI.accent, Theme.color("accent"))
        assert.are.same(C.UI.gold, Theme.color("gold"))
        assert.are.same(C.UI.amber, Theme.color("amber"))
        assert.are.same(C.UI.dim_fg, Theme.color("dim_fg"))
    end)

    it("returns nil for an unknown name", function()
        assert.is_nil(Theme.color("not_a_real_color"))
    end)

    it("the palette uses 0..1 floats (LÖVE's color range)", function()
        for _, name in ipairs({ "bg", "fg", "accent", "gold", "amber", "dim_fg" }) do
            local c = Theme.color(name)
            for _, ch in ipairs(c) do
                assert.is_true(ch >= 0 and ch <= 1,
                    ("color %s channel out of range: %s"):format(name, ch))
            end
        end
    end)
end)

describe("Theme.init / Theme.font", function()
    -- A loader stub that records calls and returns a unique handle per (path, size)
    -- so we can assert which font was bound to which role.
    local function loader_stub()
        local calls = {}
        return function(path, size)
            calls[#calls + 1] = { path = path, size = size }
            return ("font<%s@%d>"):format(path, size)
        end, calls
    end

    it("returns nil for any role before init", function()
        Theme.init(function() return nil end) -- reset
        -- Re-require to drop any module-level state; busted shares state by default,
        -- so we explicitly clear by calling init with a loader that returns nil for
        -- every role. After this, font() should return nil.
        assert.is_nil(Theme.font("display"))
        assert.is_nil(Theme.font("body"))
    end)

    it("loads display + heading + body + meta fonts from the configured paths", function()
        local loader, calls = loader_stub()
        Theme.init(loader)
        assert.are.equal("font<assets/fonts/IBMPlexMono-Regular.ttf@20>", Theme.font("display"))
        assert.are.equal("font<assets/fonts/IBMPlexMono-Regular.ttf@14>", Theme.font("heading"))
        assert.are.equal("font<assets/fonts/IBMPlexMono-Regular.ttf@12>", Theme.font("body"))
        assert.are.equal("font<assets/fonts/IBMPlexMono-Regular.ttf@10>", Theme.font("meta"))
        assert.are.equal(4, #calls) -- one loader call per role
    end)

    it("is idempotent: calling init again replaces the fonts", function()
        Theme.init(function(p, s) return ("v1:%s@%d"):format(p, s) end)
        local before = Theme.font("display")
        Theme.init(function(p, s) return ("v2:%s@%d"):format(p, s) end)
        assert.are_not.equal(before, Theme.font("display"))
    end)

    it("returns nil for an unknown role", function()
        local loader, _ = loader_stub()
        Theme.init(loader)
        assert.is_nil(Theme.font("nonexistent_role"))
    end)
end)
