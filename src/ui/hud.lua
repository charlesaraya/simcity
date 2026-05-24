-- src/ui/hud.lua
-- The debug heads-up display. Reads world state (never writes) and draws the
-- stats overlay. Kept in its own module from the start because UI tends to grow
-- and tangle with everything if you let it.
--
-- main passes in transient view state (current tool, speed) via opts, since
-- those live in the input layer, not the world.

local World = require("src.world.world")
local Clock = require("src.systems.clock")
local C = require("src.world.constants")

local Hud = {}

local TOOL_NAME = {
    [C.TOOL.BULLDOZE] = "Bulldoze",
    [C.TOOL.ZONE_RES] = "Residential",
    [C.TOOL.ZONE_COM] = "Commercial",
    [C.TOOL.ZONE_IND] = "Industrial",
}

local function speed_name(speed)
    if speed == C.SPEED.PAUSED then return "Paused" end
    if speed == C.SPEED.FAST then return "Fast" end
    return "Normal"
end

function Hud.draw(world, opts)
    love.graphics.setColor(1, 1, 1)
    local year, month = Clock.date(world)
    local res_n = World.count_buildings(world, C.ZONE.RESIDENTIAL, C.BUILD.COMPLETE)
    local com_n = World.count_buildings(world, C.ZONE.COMMERCIAL, C.BUILD.COMPLETE)
    local ind_n = World.count_buildings(world, C.ZONE.INDUSTRIAL, C.BUILD.COMPLETE)

    love.graphics.print("Slow Grid - Phase 2", 16, 16)
    love.graphics.print(("Date %04d-%02d   Speed: %s   FPS %d")
        :format(year, month, speed_name(opts.speed), love.timer.getFPS()), 16, 38)
    love.graphics.print(("Pop %d    R %d    C %d    I %d")
        :format(World.population(world), res_n, com_n, ind_n), 16, 60)
    love.graphics.print(("Demand   R %+.2f    C %+.2f    I %+.2f")
        :format(world.demand.residential, world.demand.commercial, world.demand.industrial), 16, 82)
    love.graphics.print(("Treasury $%d    (%+d/mo)")
        :format(world.treasury, world.economy.last_net), 16, 104)
    love.graphics.print(("Tool: %s"):format(TOOL_NAME[opts.tool]), 16, 126)

    if opts.status then
        love.graphics.setColor(C.COLOR.HIGHLIGHT)
        love.graphics.print(opts.status, 230, 16)
        love.graphics.setColor(1, 1, 1)
    end

    love.graphics.print(
        "[1]Bulldoze [2]Res [3]Com [4]Ind  |  hold-click paint  |  space pause  +/- speed  |  F5 save  F9 load  |  WASD/scroll camera",
        16, love.graphics.getHeight() - 28)
end

return Hud
