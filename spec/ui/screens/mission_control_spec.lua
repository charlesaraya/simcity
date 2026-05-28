-- spec/ui/screens/mission_control_spec.lua
-- The crew dashboard reached via Pause modal's "Mission Control". Read-only
-- in 4c-1: lists the team and the mission identity; the only interactions
-- are Back (returns to Pause) and Return to Home (kicks the player back to
-- the title menu, abandoning the active mission in memory).

local MissionControl = require("src.ui.screens.mission_control")
local C = require("src.world.constants")

local function actions_stub()
    local calls = {}
    return {
        back            = function() calls[#calls + 1] = "back" end,
        return_to_home  = function() calls[#calls + 1] = "return_to_home" end,
    }, calls
end

local function sample_mission()
    return { name = "Janus-IV", difficulty = "first_mission", started_at = 1 }
end

local function sample_crew()
    return {
        { name = "Akemi Vance", role = C.ROLE.COMMANDER, traits = { "Veteran" },    status = C.STATUS.ACTIVE },
        { name = "Salim Okoro", role = C.ROLE.ENGINEER,  traits = { "Methodical" }, status = C.STATUS.ACTIVE },
    }
end

describe("MissionControl.new", function()
    it("snapshots the mission and crew tables (read-only)", function()
        local m = MissionControl.new({
            mission = sample_mission(),
            crew = sample_crew(),
            cycle = 5,
            actions = actions_stub(),
        })
        assert.are.equal("Janus-IV", m.mission.name)
        assert.are.equal(2, #m.crew)
        assert.are.equal(5, m.cycle)
    end)

    it("accepts an empty crew without crashing", function()
        local m = MissionControl.new({ mission = {}, crew = {}, cycle = 0, actions = actions_stub() })
        assert.are.equal(0, #m.crew)
    end)
end)

describe("MissionControl keyboard", function()
    it("Esc fires back", function()
        local actions, calls = actions_stub()
        local m = MissionControl.new({ mission = sample_mission(), crew = sample_crew(), actions = actions })
        m:keypressed("escape")
        assert.are.same({ "back" }, calls)
    end)

    it("'b' fires back", function()
        local actions, calls = actions_stub()
        local m = MissionControl.new({ mission = sample_mission(), crew = sample_crew(), actions = actions })
        m:keypressed("b")
        assert.are.same({ "back" }, calls)
    end)

    it("'h' fires return_to_home", function()
        local actions, calls = actions_stub()
        local m = MissionControl.new({ mission = sample_mission(), crew = sample_crew(), actions = actions })
        m:keypressed("h")
        assert.are.same({ "return_to_home" }, calls)
    end)

    it("other keys are a no-op (4c-1 is read-only)", function()
        local actions, calls = actions_stub()
        local m = MissionControl.new({ mission = sample_mission(), crew = sample_crew(), actions = actions })
        m:keypressed("a"); m:keypressed("return"); m:keypressed("up"); m:keypressed("down")
        assert.are.equal(0, #calls)
    end)
end)
