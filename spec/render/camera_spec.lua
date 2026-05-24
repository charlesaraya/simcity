-- spec/render/camera_spec.lua
-- Camera touches love.graphics (dimensions) and love.keyboard (panning). We stub
-- a minimal `love` global so the transform math can be tested headless.

local C = require("src.world.constants")

-- Controllable fake input: tests flip `keys` to simulate held keys.
local keys = {}
_G.love = {
    graphics = {
        getDimensions = function() return 800, 600 end,
    },
    keyboard = {
        isDown = function(k) return keys[k] == true end,
    },
}

local Camera = require("src.render.camera")

local function near(a, b) return math.abs(a - b) < 1e-9 end

describe("Camera", function()
    before_each(function()
        keys = {} -- reset held keys between tests
    end)

    it("new() starts at zoom 1, centered on the grid", function()
        local cam = Camera.new()
        assert.are.equal(1.0, cam.scale)
        -- grid center (GRID_W/2, GRID_H/2) projected to world pixels
        local mid = C.GRID_W / 2
        assert.is_true(near((mid - mid) * (C.TILE_W / 2), cam.x))
        assert.is_true(near((mid + mid) * (C.TILE_H / 2), cam.y))
    end)

    it("screen_to_world maps screen center to the camera position", function()
        local cam = { x = 10, y = 20, scale = 2 }
        local wx, wy = Camera.screen_to_world(cam, 400, 300) -- 800x600 center
        assert.is_true(near(10, wx))
        assert.is_true(near(20, wy))
    end)

    it("update pans by PAN_SPEED/scale per second while a key is held", function()
        local cam = { x = 0, y = 0, scale = 1 }
        keys.d = true
        Camera.update(cam, 1.0)
        assert.is_true(near(C.CAM.PAN_SPEED, cam.x))
    end)

    it("zoom keeps the world point under the cursor fixed", function()
        local cam = Camera.new()
        local mx, my = 250, 175
        local wbx, wby = Camera.screen_to_world(cam, mx, my)
        Camera.zoom(cam, 1, mx, my) -- one notch in
        local wax, way = Camera.screen_to_world(cam, mx, my)
        assert.is_true(near(wbx, wax))
        assert.is_true(near(wby, way))
        assert.is_true(cam.scale > 1.0)
    end)

    it("zoom clamps to the configured range", function()
        local cam = Camera.new()
        Camera.zoom(cam, 100, 400, 300)  -- way in
        assert.are.equal(C.CAM.ZOOM_MAX, cam.scale)
        Camera.zoom(cam, -1000, 400, 300) -- way out
        assert.are.equal(C.CAM.ZOOM_MIN, cam.scale)
    end)
end)
