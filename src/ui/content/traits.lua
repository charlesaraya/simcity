-- src/ui/content/traits.lua
-- Per-role trait pools: short flavor descriptors (1-2 words) that color the
-- specialist before mechanics arrive in Phase 5+.

local C = require("src.world.constants")

return {
    [C.ROLE.COMMANDER]     = { "Veteran", "Decisive", "Cautious", "Charismatic" },
    [C.ROLE.ENGINEER]      = { "Methodical", "Resourceful", "Field-rated", "Pragmatic" },
    [C.ROLE.AGRONOMIST]    = { "Patient", "Soil-trained", "Botanical", "Frugal" },
    [C.ROLE.QUARTERMASTER] = { "Precise", "Ledger-keen", "Tight-fisted", "Trader" },
    [C.ROLE.SCIENTIST]     = { "Inquisitive", "Theorist", "Empirical", "Iconoclast" },
    [C.ROLE.MEDIC]         = { "Steady", "Triage-trained", "Calm", "Compassionate" },
}
