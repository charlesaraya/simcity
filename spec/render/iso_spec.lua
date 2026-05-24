-- spec/render/iso_spec.lua
-- iso is pure projection math, no LÖVE. The round-trip identity is the property
-- that guarantees correct picking.

local Iso = require("src.render.iso")
local C = require("src.world.constants")

local HW = C.TILE_W / 2
local HH = C.TILE_H / 2

describe("Iso", function()
    describe("tile_to_screen", function()
        it("places the center via the 2:1 diamond formula", function()
            -- center = ((x-y)*HW, (x+y)*HH)
            local sx, sy = Iso.tile_to_screen(1, 1)
            assert.are.equal(0, sx)
            assert.are.equal(2 * HH, sy)

            sx, sy = Iso.tile_to_screen(2, 1)
            assert.are.equal(HW, sx)
            assert.are.equal(3 * HH, sy)
        end)
    end)

    describe("screen_to_tile", function()
        it("recovers the tile from its own center", function()
            for y = 1, 20 do
                for x = 1, 20 do
                    local sx, sy = Iso.tile_to_screen(x, y)
                    local tx, ty = Iso.screen_to_tile(sx, sy)
                    assert.are.equal(x, tx)
                    assert.are.equal(y, ty)
                end
            end
        end)

        it("rounds points near a tile center to that tile", function()
            local sx, sy = Iso.tile_to_screen(5, 7)
            -- nudge a few pixels in each direction; should still pick (5,7)
            assert.are.same({ 5, 7 }, { Iso.screen_to_tile(sx + 3, sy) })
            assert.are.same({ 5, 7 }, { Iso.screen_to_tile(sx - 3, sy) })
            assert.are.same({ 5, 7 }, { Iso.screen_to_tile(sx, sy + 3) })
            assert.are.same({ 5, 7 }, { Iso.screen_to_tile(sx, sy - 3) })
        end)
    end)

    describe("tile_corners", function()
        it("returns top, right, bottom, left around the center", function()
            local cx, cy = Iso.tile_to_screen(3, 4)
            local tx, ty, rx, ry, bx, by, lx, ly = Iso.tile_corners(3, 4)
            assert.are.equal(cx, tx); assert.are.equal(cy - HH, ty) -- top
            assert.are.equal(cx + HW, rx); assert.are.equal(cy, ry) -- right
            assert.are.equal(cx, bx); assert.are.equal(cy + HH, by) -- bottom
            assert.are.equal(cx - HW, lx); assert.are.equal(cy, ly) -- left
        end)
    end)
end)
