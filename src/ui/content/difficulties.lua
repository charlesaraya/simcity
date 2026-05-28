-- src/ui/content/difficulties.lua
-- Three operational-difficulty presets. Each carries an `overrides` table
-- that World.new applies at construction (Phase 4c-2): currently just
-- start_treasury (PRD: "at minimum starting funds + 1-2 more"). Adding more
-- tunables means giving the consuming system a per-world override path; the
-- balance pass after 4c-2 widens this.

local C = require("src.world.constants")

return {
    {
        key      = "simulator",
        label    = "Simulator",
        abbr     = "SIM",
        summary  = "Practice run. Generous funding. Forgiving thresholds.",
        overrides = { start_treasury = 5000 },
    },
    {
        key      = "first_mission",
        label    = "1st Mission",
        abbr     = "1ST",
        summary  = "Default tuning. The mission you trained for.",
        overrides = { start_treasury = C.ECON.START_TREASURY },
    },
    {
        key      = "stellar",
        label    = "Stellar",
        abbr     = "STL",
        summary  = "Lean charter. Tight constraints. For experienced operators.",
        overrides = { start_treasury = 500 },
    },
}
