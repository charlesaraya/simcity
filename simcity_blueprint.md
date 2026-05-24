# The Slow Grid — A SimCity-Inspired Blueprint for Lua & LÖVE

*A phased development plan for building a 2D isometric city simulation as a learning vehicle and architectural foundation for future genre exploration.*

---

## Purpose of this document

This blueprint is not a tutorial and it is not a final design document. It is something more useful for your situation: a structured plan that gives you enough scaffolding to start building immediately, while leaving deliberate room for you to make the small decisions yourself, because those small decisions are where the real learning happens.

You already know how to write decoupled code and avoid spaghetti architectures. What this document gives you is the *shape* of the problem space, so that when you sit down to code you know which problems to solve in which order, what each one is supposed to teach you, and how each piece connects to the others. By the time you finish Phase 3, you will have built something that genuinely feels like a tiny SimCity. By the time you finish Phase 5, you will have a foundation flexible enough to mutate into entirely new sub-genres — survival city-builders, ecological restoration games, narrative management games, anything in that adjacent design space.

Read this document once end to end before you write any code. Then return to it phase by phase as you build.

---

## Part 1 — Game design principles

Before talking about systems and code, we need to agree on what the game is actually about, because every architectural decision downstream depends on it. These principles serve two purposes: they keep the scope tight while you build the foundation, and they explicitly mark out the design surfaces you will later push against to evolve the game into more interesting sub-genres.

### Principle 1: The grid is the world

Everything that exists in the game lives on a discrete 2D grid of tiles. There are no free-floating entities, no continuous physics, no off-grid simulation. This is not a limitation, it is a discipline. Working on a grid keeps your data structures simple, makes spatial queries trivial, and makes the whole simulation deterministic and testable. Cellular-automata-style emergent behavior is also easiest to reason about on a grid, which matters because much of what makes SimCity feel alive is exactly that kind of emergence.

When you later evolve the game, the grid stays. What changes is what lives on it and how cells influence each other.

### Principle 2: Simulation is data plus rules, never objects with behavior

The city is a big pile of data. The systems that operate on that data are stateless functions that read the world, compute changes, and write back. There are no "Building" objects that know how to update themselves. There is a list of buildings (data) and a system (rules) that knows how to evolve them.

This separation is the single most important architectural commitment in this project. If you preserve it religiously through Phase 5, you will be able to do things that feel like magic: serialize and reload the entire game from a single table, run the simulation headlessly for testing, fast-forward a hundred turns in a frame, and most importantly, swap out gameplay systems without touching anything else. The moment you give a building a `:update()` method that mutates the world, you have started building the spaghetti you said you wanted to avoid.

### Principle 3: Time is a first-class resource, and different systems live on different clocks

Real-time games update everything sixty times per second. Simulation games cannot afford to do that and do not need to. Population growth does not care about frames. Economic recalculation does not care about frames. Pollution diffusion does not need to run more than a few times per second. Only the camera, input, and animation truly need frame-rate updates.

You will build a simulation clock that advances in discrete ticks, decoupled from the rendering clock, and every system will declare its own tick cadence. This single architectural choice gives you performance, pause and fast-forward for free, and deterministic replays — and it costs you essentially nothing once you understand the pattern.

### Principle 4: Systems communicate through events, never through direct references

When a building is constructed, the construction system does not call the economy system to register taxes, and it does not call the renderer to add a sprite. It emits an event like `building_constructed` with the relevant data, and any system that cares subscribes. The economy hears it and updates revenue. The demand system hears it and updates job counts. The renderer hears it and adds a sprite to its draw list.

This is publish-subscribe, and it is the pattern that lets your game grow without collapsing under its own weight. The cost is one small event bus module, perhaps thirty lines of Lua. The benefit is that every new system you add in Phase 4 or Phase 5 plugs into the existing game without you having to modify a single existing system.

### Principle 5: Feedback loops, not features, are what make a city sim feel alive

A long list of features (zones, power, water, pollution, traffic, crime, education, fire, health) does not make a city simulation. What makes it feel alive is that those features feed back into each other. Pollution lowers land value. Low land value attracts industry, which raises pollution. High pollution drives away residents, which lowers demand for commerce, which closes commercial buildings, which lowers tax revenue, which makes it harder to fund services, which makes pollution worse.

That circular causality is the entire point. As you build, you will be tempted to add features. Resist until each new feature can be justified by what feedback loop it closes or extends. A feature that does not participate in a loop is just decoration.

### Principle 6: The minimum viable city should still feel like a city

It is better to ship a tiny city sim with three zone types, one resource, and a working demand loop than to half-build a sprawling one with fifteen systems that do not talk to each other. The Phase 1 milestone is deliberately small not because it is easy but because it forces every architectural piece to exist end to end. Once that loop is closed, every subsequent phase is an addition to a working game, never a leap into unknown territory.

### Why these principles matter for your stated goal

You said you want this project to be a foundation you can evolve into more particular or creative sub-genres. The principles above are explicitly chosen with that in mind. A grid-based, data-driven, event-bus-mediated, multi-clock simulation is the most malleable foundation you can build for this genre. From it, you can pivot to:

- A *survival city-builder* like Frostpunk by adding a single global threat resource that ticks down and changes the demand functions.
- A *restoration game* like Terra Nil by inverting which actions consume and produce resources, so that natural recovery becomes the goal.
- A *narrative management game* by adding a story-event system that subscribes to existing simulation events and overlays scripted moments.
- A *colony sim* like Rimworld by adding individual agents that move on the grid and have personal needs, sitting on top of the same world state.
- A *strategy game* by adding a second player or AI and turning resources into contested territory.

Each of these is an additive transformation. You do not rewrite the foundation; you extend it. That is what makes this blueprint worth following carefully.

---

## Part 2 — Core gameplay mechanics

Now I will describe the gameplay itself: what the player does, what the simulation does in response, and what the feedback loop between them feels like. Read this section as the contract that the systems in Part 3 are written to fulfill.

### The player's actions

The player has a small, fixed verb set, which is intentional. A small verb set with deep consequences is more interesting than a large verb set with shallow consequences, and it is dramatically easier to build, balance, and test.

The player can pan and zoom a camera over the isometric grid. The player can select a tool from a small palette and apply it to a tile. The tools, in the order you will implement them, are: bulldoze, zone residential, zone commercial, zone industrial, and (in later phases) build road, build power plant, build power line, and place service buildings. The player can also adjust the game speed (paused, slow, normal, fast) and observe overlay views showing pollution, land value, traffic, or power as colored heatmaps over the grid.

That is the entire input surface. Notice what is not in it: no direct building placement of residential or commercial structures (zones grow buildings automatically based on demand), no individual citizen manipulation, no menu-driven economy (taxation comes later as a single global slider). The player is a planner, not a builder, and the city grows in response to the conditions the planner creates.

### What the simulation does

The simulation runs on a tick clock and performs the following recurring work, each piece on its own cadence.

Demand is recomputed periodically. Residential demand goes up when there are more jobs than residents and goes down when there are more residents than jobs. Commercial demand goes up when there are more residents than shops can serve and goes down when commerce outpaces population. Industrial demand follows a similar logic relative to commercial throughput and raw residential workforce availability. In the simplest implementation, these are just three floating point numbers between -1 and 1, recalculated every simulated month.

Zones grow buildings when demand for that zone type is positive and a zoned tile is empty. Growth is probabilistic and gradual: each empty zoned tile rolls each tick against a probability proportional to current demand, and on success a building begins constructing. Construction takes a few ticks to complete. Once complete, the building contributes to population (residential) or jobs (commercial and industrial).

Zones abandon buildings when demand is strongly negative or when local conditions become hostile (high pollution, no power, no road access in later phases). Abandonment is also probabilistic, which gives the city a living, breathing quality rather than instant snapping between states.

The economy collects taxes from populated buildings each simulated month, spends money on maintenance for any service buildings, and updates the player's treasury.

Once you add them, networked systems (power, water, roads) update their connectivity graphs when tiles change, and diffusion systems (pollution, land value) propagate their values across the grid on a slow tick.

### The core feedback loop

Read this carefully because everything you build is in service of making this loop work.

The player zones some residential, commercial, and industrial tiles. The demand system, finding any positive demand, starts probabilistically growing buildings. As residential buildings populate, the population rises, which increases commercial and industrial demand, which causes those zones to grow. As industrial zones grow, they generate pollution (Phase 4), which lowers land value in surrounding tiles, which makes those tiles less attractive for residential growth, which slows residential expansion, which eventually starves industry of workers, which slows the whole city. Meanwhile, taxes from populated buildings fund the player's treasury, which the player spends on roads, power, and services that unlock new growth.

That is the entire game in one paragraph. Every system you build exists to make that loop work. Every system you add in later phases extends that loop in some direction (adding new dependencies, new constraints, new failure modes).

### What "winning" means

There is no win condition in the minimum viable version. The game ends when the player chooses to stop, and the experience is the journey of growth, equilibrium, and stress. This is correct for the foundation. Later, when you evolve into a sub-genre, you will impose win conditions appropriate to that sub-genre (survive ten years, restore the wilderness, reach a target population, achieve net-zero pollution, and so on). Imposing them on the foundation would prematurely constrain it.

---

## Part 3 — Technical architecture

This section describes the system layout, the responsibilities of each module, and the patterns that hold them together. I will describe everything in terms of *what each module owns* and *how modules interact*, rather than giving you complete code, because the act of writing the code is itself a learning exercise that this document is not trying to replace.

### High-level layer diagram

The game has four conceptual layers, stacked from foundation to surface. Data flows mostly upward (lower layers are read by upper layers); commands flow mostly downward (the player issues commands that the simulation executes); and events flow horizontally across the simulation layer through the event bus.

```
+--------------------------------------------------+
|  Input & UI Layer                                |
|  (mouse, keyboard, HUD, tool selection, menus)   |
+--------------------------------------------------+
                  | issues commands
                  v
+--------------------------------------------------+
|  Rendering Layer                                 |
|  (camera, isometric projection, sprite batching, |
|   overlay heatmaps, draw-order sorting)          |
+--------------------------------------------------+
                  ^
                  | reads (never writes)
                  |
+--------------------------------------------------+
|  Simulation Layer                                |
|  (systems: economy, zoning, growth, demand,      |
|   power, pollution, etc., communicating via      |
|   the event bus and ticking on their own clocks) |
+--------------------------------------------------+
                  ^
                  | reads and writes
                  v
+--------------------------------------------------+
|  World State Layer                               |
|  (the grid, list of buildings, money, demand     |
|   values, clock — pure data, no logic)           |
+--------------------------------------------------+
```

The strict rule is that the simulation layer never imports anything from the rendering layer, and the world state layer never imports anything from any layer above it. If you preserve this discipline, you can run the simulation headless for tests, and you can swap out the renderer entirely (for example, replacing 2D isometric with a top-down debug view) without changing any simulation code.

### Module responsibilities

The world state module owns the grid, the building list, the player's resources, the simulation clock, and the global demand values. It exposes read functions (get the tile at x, y; get the building at x, y; get the current demand for residential) and write functions (set the zone type of a tile; add a building; remove a building; deduct money). It contains no logic about what these changes mean. It is the database.

The event bus module owns the publish-subscribe mechanism. Other modules call `bus.subscribe(event_name, handler_function)` at startup and `bus.publish(event_name, data)` at runtime. The bus itself is trivial to implement, perhaps thirty lines, and you should write it yourself rather than using a library because doing so will teach you exactly how it works and why it matters.

The simulation systems each own one concern. The zoning system handles the consequences of zone changes (it does not handle the player clicking — that is a command issued by the input layer that calls a world state write function, which then publishes a `tile_zoned` event that the zoning system might or might not react to). The growth system periodically scans zoned tiles and rolls dice for new buildings. The demand system periodically recomputes the three demand values from current population and jobs. The economy system periodically collects taxes and pays maintenance. Each system has a `tick_interval` (in simulation seconds, or whatever unit you choose) and an `update(dt)` function that accumulates time and only does real work when its interval elapses.

The system runner owns the list of all simulation systems and calls `update(dt)` on each one every frame. Each system internally decides whether to actually do work based on its tick interval. This is your central simulation loop.

The renderer owns the camera, the isometric projection math, the sprite batches, and the overlay views. It reads world state every frame and produces the visual output. It exposes one function to the input layer: `screen_to_tile(px, py)` so that mouse input can be translated into grid coordinates.

The input layer owns keyboard and mouse handling and the current tool selection. When the player clicks, the input layer asks the renderer which tile was clicked, then issues a command (a function call) to the appropriate world state writer (`world.zone_tile(x, y, "residential")`). World state writers publish events as a side effect, which propagates the change to anyone who cares.

The UI layer is a sub-concern of input and rendering, owning the heads-up display, menus, and toolbars. Keep it isolated in its own module from day one even if it is trivial at first, because UI tends to grow and tangle with everything else if you let it.

### The event bus pattern in detail

Because the event bus is so central, I will sketch its shape in pseudocode. Implementing it should take you less than an hour.

```lua
-- bus.lua (conceptual sketch, not finished code)
local M = {}
M.subscribers = {}  -- event_name -> list of handler functions

function M.subscribe(event_name, handler)
    -- ensure a list exists for this event, then append the handler
end

function M.publish(event_name, data)
    -- look up the handler list, call each handler with data
    -- handlers should be small and not publish further events synchronously
    -- if you need cascading events, queue them and process after the current handler returns
end

return M
```

The synchronous-versus-queued question is worth thinking about. If publishing an event inside a handler immediately triggers more handlers, you can create deep call stacks and ordering surprises. A simple and safe pattern is to queue events published during a tick and dispatch them all between ticks. Start with synchronous and switch to queued if you hit problems.

### The tick scheduler pattern in detail

The tick scheduler is what makes the multi-clock architecture work. Each system has the same shape:

```lua
-- example: economy_system.lua (conceptual)
local M = {}
M.tick_interval = 1.0  -- simulated seconds per tick (one tick per simulated month, say)
M.time_since_last_tick = 0

function M.update(dt, world, bus)
    M.time_since_last_tick = M.time_since_last_tick + dt
    if M.time_since_last_tick >= M.tick_interval then
        M.time_since_last_tick = M.time_since_last_tick - M.tick_interval
        -- do the actual work: iterate buildings, collect taxes, etc.
        -- publish events as needed
    end
end

return M
```

The `dt` passed in is *simulated* time, not real time, which is how you get pause and fast-forward for free. Your main loop multiplies real `dt` by the current game speed factor before passing it to systems.

### File and folder layout suggestion

A starting layout that respects the layer boundaries described above:

```
slowgrid/
  main.lua                 -- LÖVE entry point, sets up bus, world, systems, renderer, input
  conf.lua                 -- LÖVE configuration
  src/
    world/
      world.lua            -- world state structure and read/write functions
      grid.lua             -- grid-specific helpers (iteration, neighbors, bounds)
      constants.lua        -- tile types, zone types, magic numbers in one place
    bus.lua                -- event bus
    systems/
      runner.lua           -- the system runner that ticks all systems
      economy.lua
      zoning.lua
      growth.lua
      demand.lua
      -- later phases: power.lua, pollution.lua, land_value.lua, etc.
    render/
      camera.lua
      iso.lua              -- isometric projection math, screen<->tile conversion
      renderer.lua         -- the main draw routine, reads world, calls iso
      overlays.lua         -- pollution, land value, power heatmaps
    input/
      input.lua            -- raw input handling
      tools.lua            -- tool selection and command dispatch
    ui/
      hud.lua
      toolbar.lua
  assets/
    sprites/
    fonts/
```

Do not over-engineer this on day one. Start with a flatter layout and split files when they exceed a few hundred lines or when responsibilities start to mix.

### Lua and LÖVE specific guidance

A few practical notes that will save you time.

Lua's only data structure is the table, used as both array and dictionary. Embrace this. Do not import an OOP library; just use tables with functions that take the table as the first argument. For the rare case where you want method syntax, `setmetatable` with `__index` is enough. Avoid inheritance entirely; it is rarely useful in games and especially not in this style of architecture.

LÖVE's coordinate system has y increasing downward, which matters for isometric math. The standard isometric projection from grid coordinates `(gx, gy)` to screen pixels `(sx, sy)` is `sx = (gx - gy) * tile_width / 2` and `sy = (gx + gy) * tile_height / 2`, plus camera offset. The inverse is `gx = (sx / (tile_width / 2) + sy / (tile_height / 2)) / 2` and `gy = (sy / (tile_height / 2) - sx / (tile_width / 2)) / 2`. Test the inverse early by clicking on tiles and highlighting them; it is the most common source of subtle bugs.

For drawing performance, use `love.graphics.newSpriteBatch` for the terrain layer. Drawing 4096 tiles individually each frame will work but starts to cost you; with a sprite batch it is one draw call. Buildings can stay as individual draws until you have more than a hundred or so on screen at once.

For depth sorting in isometric, sort drawables by `gx + gy` ascending, so tiles "behind" draw first. For objects of different heights on the same tile, draw the floor first, then objects.

For game state management between menu, gameplay, and pause screens, the `hump.gamestate` library is well-regarded and saves you boilerplate. For tween animations (smooth camera moves, building construction effects), `hump.timer` or `flux` are both good. These are the only two third-party libraries I would suggest from the start; everything else, write yourself for the learning value.

For serialization (save and load), the `bitser` library handles Lua tables well, including cycles. Because your world is pure data, save and load should be trivial: serialize the world state table, deserialize it, and re-subscribe systems to the event bus. If you ever find yourself writing complex save code, you have probably violated the data-is-data principle somewhere.

---

## Part 4 — Phased development plan

This is the phased plan. Each phase is a complete, playable milestone. Do not skip ahead, and do not start a phase until the previous one feels solid. Each phase teaches you something specific, and the lessons compound.

### Phase 0 — Hello, isometric world (estimated: a few evenings)

Your goal in this phase is to have an isometric grid on the screen, a movable camera, and correct mouse-to-tile picking. There is no simulation yet. There is no event bus yet. There is only a grid and the ability to highlight the tile under the cursor.

By the end of this phase you will have written the isometric projection math, set up LÖVE's main loop, implemented a basic camera with WASD or middle-mouse pan and scroll-wheel zoom, drawn a 64x64 grid of placeholder tiles (a flat color or simple checkerboard is fine), and confirmed that clicking on any tile highlights the correct one. You will also have set up your file structure and gotten comfortable with the LÖVE workflow of running, hot-reloading, and printing debug info to the console.

What you learn here is the rendering math and the LÖVE basics. Resist the urge to add gameplay until this feels rock solid. Isometric picking bugs are subtle and best squashed in isolation.

### Phase 1 — The minimum viable city (estimated: one to two weeks)

Your goal in this phase is the smallest possible thing that feels like SimCity. Add the world state module, the event bus, the system runner, and three systems: zoning, growth, and demand. Add three tools: bulldoze, zone residential, zone commercial. Skip industrial for now to keep things even simpler.

The player can paint zones on the grid. The demand system, ticking once per simulated month, computes whether residential or commercial demand is positive based on a trivial rule (residential demand is positive if commercial buildings outnumber residential buildings; commercial demand is positive if the reverse). The growth system, ticking once per simulated month, iterates zoned-but-empty tiles and rolls dice to spawn buildings proportional to demand. Buildings are just sprites; they do not need internal complexity. Population is the sum of residential buildings, jobs is the sum of commercial buildings.

There is no money yet. There is no UI beyond a simple debug overlay showing demand values and population. The game is mostly a curiosity, but it works end to end.

What you learn here is the architecture, which is the entire point. You will have built every piece of the foundation in its simplest form: world state, event bus, system runner, multi-clock ticking, and the rendering-reads-but-never-writes discipline. Every later phase is an extension.

Before moving on, prove your architecture to yourself by adding a "fast forward" button that multiplies game speed by ten. If everything works correctly without bugs, your tick scheduler is sound. Add a "save and quit / load" button. If you can serialize and restore the world cleanly, your data-is-data discipline held.

### Phase 2 — Industry, money, and the first real loop (estimated: one to two weeks)

Add the industrial zone and the economy. Now you have three zones whose demands depend on each other in a non-trivial way: residents need jobs, jobs need workers, industry produces goods that commerce sells, commerce employs residents.

Add money. Buildings pay taxes each month proportional to their population or jobs. The player starts with a fixed treasury. There is still nothing to spend money on, but the treasury exists, fluctuates, and gives you a foothold for everything that follows.

Add the first proper UI: a HUD showing money, population, jobs, current date, and the three demand values as bars. Add tool selection as on-screen buttons rather than keyboard shortcuts.

What you learn here is multi-system feedback. With three zones whose demands feed each other, you will see your first emergent oscillations: cities that boom and bust, cities that get stuck, cities that grow steadily. Tuning the demand formulas to make these dynamics interesting (rather than degenerate) is your first real game-design exercise. Spend time on it. This is where the game starts to feel alive.

### Phase 3 — Roads and networks (estimated: one to two weeks)

Add roads. This phase teaches you graph data structures layered on top of the grid. A road tile is a connector, and a building is "connected to the road network" if it is adjacent to a road tile that is part of the network reaching from itself to (in this minimal version) the edge of the map.

Modify the growth system: buildings only grow on zoned tiles adjacent to a road. Modify abandonment: if road connectivity is lost (the player bulldozed a road), buildings begin to abandon.

Implement the network using a simple flood-fill or union-find. Recompute connectivity only when a road tile is added or removed (not every tick), because road changes are rare and you can afford to do real work when they happen.

What you learn here is the difference between *eager* and *lazy* computation, and the value of caching derived state. The road network is derived state — it can always be recomputed from the grid — but caching it lets the growth system query it in constant time, and the cache invalidates only on road changes.

### Phase 4 — Power and pollution: the diffusion phase (estimated: two weeks)

This is the most architecturally significant phase, because you will discover that power and pollution share a deeper abstraction than they first appear to.

Power is another network, like roads. Power plants produce power, power lines carry it, buildings consume it. Buildings without power do not grow and slowly abandon. You implement this almost exactly like roads, and that reuse should suggest to you that there is a *NetworkedUtility* pattern you can extract. Extract it. Refactor roads and power to share code. This is your first refactor of a working system, and it is a critical learning moment.

Pollution is different. Industrial buildings emit pollution. Pollution spreads outward from sources by diffusion, decaying over distance. This is cellular automata territory. The naive implementation (every tick, for every tile, sum contributions from every source) is far too slow. You will learn one of several techniques: only update tiles within range of sources, propagate via a wavefront, or run diffusion only every few ticks. Performance becomes a real consideration here for the first time.

Pollution affects land value, which is also a diffused field — high land value near amenities, low near pollution and industry. Land value affects growth: residential and commercial zones prefer high land value, industrial does not care. Suddenly you have closed a major feedback loop: industry pollutes, pollution lowers land value, low land value drives residential away, industry loses workers, residential drifts to higher land value (away from industry), commercial follows residential, and the city develops natural geography.

What you learn here is performance-aware simulation, cellular automata, and the extraction of shared patterns. You also see, for the first time, your city develop emergent neighborhoods. This is the moment your project starts to feel like a real game.

Add the overlay views: a pollution heatmap, a land value heatmap, a power coverage map. The player needs to see derived state to make decisions about it. The overlays are also fantastic for debugging.

### Phase 5 — Services, disasters, and the foundation is complete (estimated: two to three weeks)

Add service buildings: police, fire, parks. These are buildings the player places directly (not zoned), they cost money to build and maintain, and they create a positive influence field around themselves (the inverse of pollution). Parks raise land value; police reduces a new "crime" stat that lowers land value; fire stations reduce the chance of building fires (a disaster).

Add at least one disaster: random fires that destroy buildings unless a fire station is within range. The disaster system listens for `month_tick` events and rolls dice; affected buildings publish `building_destroyed`; the renderer plays a brief animation; the economy registers the loss.

Add a taxation slider: the player adjusts a single tax rate that scales building tax revenue but also dampens growth (high taxes slow building construction). This is the first explicit trade-off the player must manage and the foundation of all economic strategy.

At the end of Phase 5, you have a functioning, balanced city simulation. It is small compared to the original SimCity, but it has every architectural component the full game would need, and every one of those components is in a state that can be cleanly extended.

What you learn here is how to add systems to a mature codebase without breaking it. By this point, the event bus and the data-is-data discipline are paying compound dividends: each new feature plugs in without disturbing the others. You should feel this concretely. If you do not — if adding fires requires you to modify the economy system, or if the tax slider needs renderer changes — that is a signal that some earlier coupling crept in, and now is the time to find and fix it.

### Phase 6 and beyond — Evolving into sub-genres

Once Phase 5 is solid, the foundation is yours to mutate. Each direction below is achievable as an additive transformation, not a rewrite. Pick the one that excites you most and explore it for a few weeks. Then come back and pick another.

A *survival city-builder*. Add a global threat: a cold front, a drought, a plague. The threat ticks down a global resource (warmth, water, health) that decays unless the player builds specific structures. Demand functions change to account for the threat (people will not move to a freezing city). Disasters become more frequent and harsher. The game now has a survival arc and a possible loss state.

A *restoration game*. Invert the goal. The map starts as a polluted, exhausted ruin. The player's tools include demolition, soil remediation, tree planting, and water restoration. Pollution is now a negative resource to be drained, and land value is replaced by biodiversity. Buildings are mostly things to remove rather than place. You will find that very little of the foundation needs to change; mostly you are changing the meaning of existing values and tweaking a few formulas.

A *narrative management game*. Add a story-events module that subscribes to existing simulation events. When the city hits certain conditions (population crosses a threshold, pollution reaches a level, a specific district develops), a scripted event fires: a letter from a resident, a choice with consequences. The story is layered on top of the simulation, not bolted into it.

A *colony sim with individual agents*. Add citizens as entities that walk on the grid. Each citizen has a home, a workplace, and needs. Buildings now provide specific services to specific citizens, and the city's health is the sum of individual lives. This is the largest extension, but it builds on the foundation rather than replacing it.

A *resource-network puzzle game*. Drop the open-ended sandbox and create scenarios: "with this budget and this terrain, achieve a population of 10,000 in 50 months." Most of the systems you have built are exactly what is needed; what changes is the framing.

The point of the foundation is that any of these is reachable from where you are. That is the real prize of building this carefully.

---

## Part 5 — Working principles for the build itself

A few meta-principles to keep in mind as you build, distilled from common failure modes in projects like this.

### Build the loop first, polish later

It is tempting to make Phase 0's tiles look beautiful. Resist. Make them work, then move on. Beauty is added at the end, once the systems are stable, because any visual work you do early will be redone later as the design evolves. Programmer art (flat colors, simple shapes, text labels) is a feature in the early phases, not a flaw.

### Tune values from data, not from intuition

Your demand formulas, growth probabilities, tax rates, and diffusion constants are tuning parameters. Expose them in a single config file (`world/constants.lua`) and resist hard-coding them in system logic. Then build a debug overlay that shows the values in real time, and ideally a console command to tweak them at runtime. Tuning a simulation is a long, empirical process, and you will save yourself enormous time by making it cheap to experiment.

### Write tools before you need them

When you find yourself manually clicking the same sequence of tiles to reproduce a bug, write a debug command that does it for you. When you find yourself eyeballing whether a system is working, build the overlay that visualizes it. Tools you build for yourself compound in value. By Phase 5, you should have a small library of debug commands, overlays, and inspection tools that let you understand the simulation faster than the player ever could.

### Refactor when patterns emerge, not before

When you build roads in Phase 3 and then power in Phase 4, you will notice they share structure. *Then* refactor, not before. Premature abstraction is just as bad as no abstraction. Wait until you have two or three concrete examples of a pattern before extracting it, because only then do you know what the abstraction needs to support.

### Commit often, in small steps

Use git from day one, even though it is just you. Commit each system as it comes online, each refactor as a separate commit. When something breaks, the small commits let you bisect to the cause. When you want to remember how you solved something, the commit log is your journal.

### Keep a design diary

Alongside the code, keep a plain text file where you write down design decisions, things you tried that did not work, balance changes and what they did, and open questions. Reread it at the start of each session. This is how the project becomes a learning vehicle and not just an artifact — by giving your future self access to your past self's reasoning.

---

## Closing notes

This blueprint is intentionally long because the architectural choices it asks you to make compound for many months of work. If you internalize the six design principles, build the layers in the order Part 4 describes, and keep the disciplines of Part 5, you will end up with something rare: a hobby project whose architecture you actually understand and whose extensibility you have proven to yourself by extending it.

The genre is rich, the foundation is malleable, and the work is the kind that rewards patience. Start with Phase 0, get that isometric grid on screen, and let the rest unfold from there.

Good luck, and have fun.
