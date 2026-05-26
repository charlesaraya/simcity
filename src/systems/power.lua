-- src/systems/power.lua
-- The power network: the second networked utility, and the deliberate second
-- instance of the roads compute/install/query pattern (a NetworkedUtility will be
-- extracted once this exists). It diverges from roads in one way: capacity
-- and that divergence is split across two stages:
--
--   1. compute_topology: flood-fill the conducting medium into connected components
--      and total each component's supply.
--   2. resolve: allocate finite supply against the buildings' demand and decide which
--      components are lit.
--
-- The conducting medium is roads UNION power lines UNION plant footprints; all
-- three carry electricity. A plant only feeds the grid when its footprint touches
-- an edge-connected road (workers must be able to reach it), so supply reuses
-- the road connectivity cache.

local Grid = require("src.world.grid")
local Roads = require("src.systems.roads")
local Bus = require("src.bus")
local C = require("src.world.constants")

local Power = {}

-- Every tile that carries current: a road, a power line, or any part of a plant.
local function is_conductor(tile)
    return tile ~= nil and (tile.road or tile.power_line or tile.plant or tile.plant_part)
end

-- Does this plant (anchor) touch an edge-connected road? Reuses the
-- road query over every footprint tile.
local function plant_has_road(world, ax, ay)
    local n = C.PLANT.FOOTPRINT
    for dy = 0, n - 1 do
        for dx = 0, n - 1 do
            if Roads.building_connected(world, ax + dx, ay + dy) then
                return true
            end
        end
    end
    return false
end

-- Per-component demand (MW): each COMPLETED building adds its zone's draw to
-- every component it borders (a building straddling two networks loads each once;
-- construction sites draw nothing). Shared by resolve and stats so the two never
-- disagree on what the load is.
local function tally_demand(world, topo)
    local grid = world.grid
    local demand = {}
    Grid.each(grid, function(x, y, tile)
        if tile.building and tile.building.state == C.BUILD.COMPLETE then
            local draw = C.POWER_DRAW[tile.zone] or 0
            local seen = {}
            for _, nb in ipairs(Grid.neighbors(grid, x, y)) do
                local cid = topo.component[Grid.idx(grid, nb.x, nb.y)]
                if cid and not seen[cid] then
                    seen[cid] = true
                    demand[cid] = (demand[cid] or 0) + draw
                end
            end
        end
    end)
    return demand
end

-- Flood-fill the conducting graph into components and sum each one's supply.
function Power.compute_topology(world)
    local grid = world.grid
    local component = {}
    local supply = {}
    local next_id = 0

    -- Label every conducting tile with its component, flooding over 4-neighbors.
    Grid.each(grid, function(x, y, tile)
        local idx = Grid.idx(grid, x, y)
        if is_conductor(tile) and not component[idx] then
            next_id = next_id + 1
            supply[next_id] = 0
            component[idx] = next_id
            local stack = { { x, y } }
            while #stack > 0 do
                local cell = table.remove(stack)
                for _, nb in ipairs(Grid.neighbors(grid, cell[1], cell[2])) do
                    local nidx = Grid.idx(grid, nb.x, nb.y)
                    if is_conductor(Grid.get(grid, nb.x, nb.y)) and not component[nidx] then
                        component[nidx] = next_id
                        stack[#stack + 1] = { nb.x, nb.y }
                    end
                end
            end
        end
    end)

    -- Add each road-connected plant's capacity to its component's supply. Only
    -- the anchor tile carries the plant record, so each plant is counted once.
    Grid.each(grid, function(x, y, tile)
        if tile.plant then
            local cid = component[Grid.idx(grid, x, y)]
            if cid and plant_has_road(world, x, y) then
                supply[cid] = supply[cid] + C.PLANT.CAPACITY
            end
        end
    end)

    return { component = component, supply = supply }
end

-- Reads the cached topology, totals each completed building's draw into every
-- component it borders, then lights a component all-or-nothing. The result is
-- a set of conducting tile indices that are actually energised.
--
-- Demand is the POTENTIAL load of completed buildings computed independently
-- of the current powered state
function Power.resolve(world)
    local topo = world.power.topology or { component = {}, supply = {} }
    local demand = tally_demand(world, topo)

    local powered = {}
    for idx, cid in pairs(topo.component) do
        local sup = topo.supply[cid] or 0
        if sup > 0 and (demand[cid] or 0) <= sup then
            powered[idx] = true
        end
    end

    world.power.powered = powered
    return powered
end

-- READ: is (x, y) served? True if any 4-neighbor is an energised conducting tile.
function Power.building_powered(world, x, y)
    for _, nb in ipairs(Grid.neighbors(world.grid, x, y)) do
        if world.power.powered[Grid.idx(world.grid, nb.x, nb.y)] then
            return true
        end
    end
    return false
end

-- READ: grid totals in MW plus the count of "dark areas" components whose demand
-- outruns their supply (over-subscribed, or loaded with no source).
function Power.stats(world)
    local topo = world.power.topology or { component = {}, supply = {} }
    local demand = tally_demand(world, topo)
    local supply_total, demand_total, dark = 0, 0, 0
    for _, sup in pairs(topo.supply) do
        supply_total = supply_total + sup
    end
    for cid, dem in pairs(demand) do
        demand_total = demand_total + dem
        if dem > (topo.supply[cid] or 0) then dark = dark + 1 end
    end
    return { supply = supply_total, demand = demand_total, dark = dark }
end

-- Event-driven: the topology cache (components + supply) is recomputed only when
-- the conducting graph changes. Subscribes to road events as well as power events
-- MUST be installed AFTER Roads.install so the plant-supply gate reads a fresh
-- road-connectivity cache. Resolving once at the end seeds a powered
-- snapshot, so a freshly loaded city is correctly lit before the first sim tick.
function Power.install(world)
    local function recompute()
        world.power.topology = Power.compute_topology(world)
    end
    local events = {
        C.EVENTS.ROAD_BUILT, C.EVENTS.ROAD_REMOVED,
        C.EVENTS.POWER_LINE_BUILT, C.EVENTS.POWER_LINE_REMOVED,
        C.EVENTS.PLANT_BUILT, C.EVENTS.PLANT_REMOVED,
    }
    for _, ev in ipairs(events) do
        Bus.subscribe(ev, recompute)
    end
    recompute()
    Power.resolve(world)
end

return Power
