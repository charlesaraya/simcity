-- src/ui/content/difficulties.lua
-- Three operational-difficulty presets. Cosmetic in 4c-1 (the charter screen
-- stores the key on world.mission and shows the summary); 4c-2 wires each
-- preset to actual sim tunables (starting funds + 1-2 more).

return {
    { key = "simulator",     label = "Simulator",   abbr = "SIM", summary = "Practice run. Generous funding. Forgiving thresholds." },
    { key = "first_mission", label = "1st Mission", abbr = "1ST", summary = "Default tuning. The mission you trained for." },
    { key = "stellar",       label = "Stellar",     abbr = "STL", summary = "Lean charter. Tight constraints. For experienced operators." },
}
