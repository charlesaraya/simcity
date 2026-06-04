-- spec/systems/water_spec.lua
-- Water coverage: pump-adjacent pipe tiles and their cardinal radius are served.

local World = require("src.world.world")
local Water = require("src.systems.water")
local C     = require("src.world.constants")

local function tile_at(w, x, y)
    return require("src.world.grid").get(w.grid, x, y)
end

describe("Water.resolve", function()
    it("covers nothing when no pipe or pump exists", function()
        local w = World.new(1)
        Water.resolve(w)
        assert.is_false(Water.tile_covered(w, 5, 5))
    end)

    it("covers nothing when pipe exists but no pump", function()
        local w = World.new(1)
        World.build_pipe(w, 5, 5)
        Water.resolve(w)
        assert.is_false(Water.tile_covered(w, 5, 5))
        assert.is_false(Water.tile_covered(w, 5, 6))
    end)

    it("covers pipe tile and cardinal radius when pump is adjacent", function()
        local w = World.new(1)
        -- pump at (4,5), pipe at (5,5); pump touches pipe to the right
        World.build_pump(w, 4, 5)
        World.build_pipe(w, 5, 5)
        Water.resolve(w)
        -- pipe tile itself
        assert.is_true(Water.tile_covered(w, 5, 5))
        -- cardinal radius 1 and 2 from (5,5)
        assert.is_true(Water.tile_covered(w, 6, 5))
        assert.is_true(Water.tile_covered(w, 7, 5))
        assert.is_true(Water.tile_covered(w, 4, 5))  -- toward pump
        assert.is_true(Water.tile_covered(w, 3, 5))
        assert.is_true(Water.tile_covered(w, 5, 6))
        assert.is_true(Water.tile_covered(w, 5, 7))
        assert.is_true(Water.tile_covered(w, 5, 4))
        assert.is_true(Water.tile_covered(w, 5, 3))
    end)

    it("does NOT cover tiles beyond radius 2", function()
        local w = World.new(1)
        World.build_pump(w, 4, 5)
        World.build_pipe(w, 5, 5)
        Water.resolve(w)
        assert.is_false(Water.tile_covered(w, 8, 5))  -- 3 tiles away
        assert.is_false(Water.tile_covered(w, 5, 8))
    end)

    it("propagates coverage through a connected pipe run", function()
        local w = World.new(1)
        -- pump at (2,5), pipe run 3→4→5→6 on row 5
        World.build_pump(w, 2, 5)
        World.build_pipe(w, 3, 5)
        World.build_pipe(w, 4, 5)
        World.build_pipe(w, 5, 5)
        World.build_pipe(w, 6, 5)
        Water.resolve(w)
        -- tile at (8,5) is 2 tiles right of (6,5) pipe: should be covered
        assert.is_true(Water.tile_covered(w, 8, 5))
        -- tile at (9,5) is 3 tiles right of (6,5): not covered
        assert.is_false(Water.tile_covered(w, 9, 5))
    end)

    it("isolated pipe cluster (disconnected from pump) is not covered", function()
        local w = World.new(1)
        World.build_pump(w, 2, 5)
        World.build_pipe(w, 3, 5)  -- connected: pump touches it
        -- gap; connected pipe only reaches to (3+2=5,5) via coverage radius
        World.build_pipe(w, 10, 5)  -- isolated: well outside radius of (3,5)
        World.build_pipe(w, 11, 5)
        Water.resolve(w)
        assert.is_true(Water.tile_covered(w,  3, 5))
        assert.is_false(Water.tile_covered(w, 10, 5))
        assert.is_false(Water.tile_covered(w, 11, 5))
    end)
end)

describe("World.build_pipe", function()
    it("places pipe on plain grass", function()
        local w = World.new(1)
        assert.is_true(World.build_pipe(w, 5, 5))
        assert.is_true(tile_at(w, 5, 5).pipe)
    end)

    it("is a no-op on an already-piped tile", function()
        local w = World.new(1)
        World.build_pipe(w, 5, 5)
        assert.is_false(World.build_pipe(w, 5, 5))
    end)

    it("refuses a zoned tile", function()
        local w = World.new(1)
        World.zone_tile(w, 5, 5, C.ZONE.RESIDENTIAL)
        assert.is_false(World.build_pipe(w, 5, 5))
    end)
end)

describe("World.build_pump", function()
    it("places pump on plain grass", function()
        local w = World.new(1)
        assert.is_true(World.build_pump(w, 5, 5))
        assert.is_true(tile_at(w, 5, 5).pump)
    end)

    it("refuses a tile that already has a pipe", function()
        local w = World.new(1)
        World.build_pipe(w, 5, 5)
        assert.is_false(World.build_pump(w, 5, 5))
    end)
end)

describe("World.pump_count", function()
    it("returns 0 with no pumps", function()
        local w = World.new(1)
        assert.are.equal(0, World.pump_count(w))
    end)

    it("counts placed pumps", function()
        local w = World.new(1)
        World.build_pump(w, 5, 5)
        World.build_pump(w, 8, 8)
        assert.are.equal(2, World.pump_count(w))
    end)
end)
