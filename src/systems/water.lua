-- src/systems/water.lua
-- Water coverage: BFS from pump-adjacent pipe tiles, then marks every tile
-- within COVERAGE_RADIUS cardinal steps as served. Called once per growth tick
-- (same cadence as Power.resolve and Pollution.resolve).
--
-- A pump injects into any pipe tile it touches. The full connected pipe cluster
-- reachable from any pump is "active". Each active pipe tile radiates coverage
-- in the four cardinal directions up to C.PIPE.COVERAGE_RADIUS tiles.

local Grid = require("src.world.grid")
local C    = require("src.world.constants")

local Water = {}

local DIRS = { {1,0}, {-1,0}, {0,1}, {0,-1} }

function Water.resolve(world)
    local covered = {}
    local visited = {}

    Grid.each(world.grid, function(px, py, ptile)
        if not ptile.pump then return end
        -- Seed BFS from every pipe tile adjacent to this pump.
        for _, d in ipairs(DIRS) do
            local nx, ny = px + d[1], py + d[2]
            local nt = Grid.get(world.grid, nx, ny)
            if nt and nt.pipe then
                local sidx = Grid.idx(world.grid, nx, ny)
                if not visited[sidx] then
                    local q = { {nx, ny} }
                    while #q > 0 do
                        local pos = table.remove(q, 1)
                        local cx, cy = pos[1], pos[2]
                        local cidx = Grid.idx(world.grid, cx, cy)
                        if not visited[cidx] then
                            visited[cidx] = true
                            covered[cidx] = true
                            -- Radiate coverage in each cardinal direction.
                            for _, dd in ipairs(DIRS) do
                                for dist = 1, C.PIPE.COVERAGE_RADIUS do
                                    local tx, ty = cx + dd[1]*dist, cy + dd[2]*dist
                                    local tt = Grid.get(world.grid, tx, ty)
                                    if tt then
                                        covered[Grid.idx(world.grid, tx, ty)] = true
                                    end
                                end
                            end
                            -- BFS: expand along connected pipe tiles.
                            for _, dd in ipairs(DIRS) do
                                local ax, ay = cx + dd[1], cy + dd[2]
                                local at = Grid.get(world.grid, ax, ay)
                                if at and at.pipe then
                                    local aidx = Grid.idx(world.grid, ax, ay)
                                    if not visited[aidx] then
                                        q[#q+1] = {ax, ay}
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end)

    world.water.covered = covered
end

function Water.tile_covered(world, x, y)
    return world.water.covered[Grid.idx(world.grid, x, y)] == true
end

return Water
