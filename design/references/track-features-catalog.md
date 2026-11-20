# Track Features Catalog: What Lives in Kart Tracks Beyond the Layout

> Research reference for planning new track stories (after 008 elevation, 009 moving hazards, 010 graphics pass).
> Researched 2026-11-20. **Patterns only.** No character, track, landmark or look below may be copied;
> every "Our idea" is original to Dogworks Racing: Kennel Kingdom (see `design/game-brief.md`).
> Companion to `design/references/track-design-reference.md` (layout, numbers, pacing), which this file does not repeat.
> **(est.)** marks a judgment call: every cost, every priority, and any number not cited.

## 0. How to read the tables

**Cost** (small team, our Godot setup, est.): **S** = days, one system touched. **M** = 1-2 weeks, or touches the kart model plus track data.
**L** = several weeks, new physics state, or new content on both tracks.

**Net** says how the feature stays consistent across 12 PCs, given our model (story 002): each PC simulates its own kart
(owner-authoritative), and a race clock is synced to the host.
- **Local**: affects only the PC's own kart (surfaces, tricks, drafting). The normal kart state sync already covers it. Free.
- **Clock**: a pure function of the synced race time (timers, patrols, barrages). Every PC agrees with no messages (the story 009 note).
- **Event**: one reliable announcement with a race time, like the item box `rpc_box_taken` in story 004. Cheap, but needs an owner.
- **Cosmetic**: each PC renders its own reaction, and tiny disagreements do not matter (crowds, flags, debris).
- **Physics**: shared objects pushed around by karts. **Avoid**: every entry below is designed to dodge this.

**Priority**: **must** (the owner chose it, or it is cheap and core), **strong**, **nice**, **skip**.
**Dep** codes: 004 items, 005 bots, 006 vehicles, 007 HUD/sound, 008 elevation, 009 hazards, 010 graphics.

**Already in our tracks** (do not re-plan these): boost pads, item boxes, lane splits, a secret-passage shortcut, the rail-less
drawbridge with moat sink and respawn, and the lava gap you can only cross at speed. **Already planned**: hills, jumps, banking and a
crossover (008), and the timed drawbridge, rolling barrels and gates (009).

## 1. Surfaces and terrain

| # | Feature | What it adds | Seen in (source) | Cost / Dep / Net | Our idea (original) | Pri |
|---|---|---|---|---|---|---|
| 1 | **Off-road slowdown** (grass, sand, mud, rubble) | The road edge becomes a real cost, so racing lines matter and wide drifts get punished. You cannot drift or reach top speed off-road. | MK series: grass, mud and shallow water slow karts [MW-Series][Prima] | **S-M**. A surface polygon type in the track data plus a per-surface speed cap and grip table. Net: Local. | Castle: tourney-field turf and the muddy kennel yard behind the stables. Dungeon: loose rubble and gravel spill at cave mouths. | **must** (owner chose) |
| 2 | **Boost-cut through off-road** | Risk and reward: spend a boost to take a straight line across the rough. An item or a skill opens a shortcut. | MK: a Mushroom or Star crosses grass, and the Dry Dry Ruins sand cut [MW-DryDry][MW-Mud]. DKR: hovercraft on sand and water [WP-DKR] | **S** on top of #1. While boosting, the off-road cap is lifted. Dep 004 (War Horn). Net: Local. | Cut the inside of the joust-field hairpin across the turf with a War Horn or pad speed. Dungeon: hop the gravel bend after the forge. | **must** (owner chose) |
| 3 | **Shallow water and puddles** | A milder off-road with a big splash (stream value). It also marks a safe edge of a deadly area. | MK: shallow water counts as off-road [MW-Series] | **S** (a surface type plus a splash effect). Dep 010 for the effect. Net: Local and Cosmetic. | Moat shallows on the drawbridge approach: a slow but safe lane beside the risky bridge. | **strong** |
| 4 | **Slick surfaces** (wet stone, ice, spilled oil) | Lower grip, longer slides, and drift timing has to change. A skill test. | MKW: rain makes roads slippery (reported in previews) [MW-Rain]. Our Cauldron Spill is the item version (004) | **S** (a grip multiplier per surface). Net: Local. | Dungeon: a slime-wet flagstone corner under a dripping cistern. Castle: a spilled-ale cobble patch outside the tavern. | **nice** |
| 5 | **Moving floor** (conveyors, turntables, gears) | Push toward or away from your goal: drive with it for speed, against it to lose speed. Rewards reading the floor. | MKDS: gears reverse every 45 s, speeding you up or slowing you down by direction [MW-TickTock] | **M** (a surface velocity added to the kart). Net: Clock (direction = f(race time)). | Dungeon: the forge's ore conveyor beside the road reverses on a timer, and a rotating grindstone floor in the mill room. | **nice** |
| 6 | **Crumbling or sinking road over laps** | The road narrows lap by lap, so late laps get tense with no new content. | MK Wii Grumble Volcano: cracked chunks shake on lap 2 and are gone by lap 3 [MW-Grumble] | **M** (a road segment with per-lap states). Dep 008 (sinking) and #16. Net: Clock or Event (see #16). | Dungeon: cracked flagstones over the lava hall shake on lap 2 and sink on lap 3. The safe line is the narrow ledge. | **strong** (belongs to lap evolution) |

## 2. Air, jumps and tricks

| # | Feature | What it adds | Seen in (source) | Cost / Dep / Net | Our idea (original) | Pri |
|---|---|---|---|---|---|---|
| 7 | **Trick off ramps, landing boost** | Skill expression on straights: one button press in the air pays a boost when you land. | MK Wii, 7 and 8 tricks [MW-Trick]. SASRT: up to 3 chained stunts in a timing window, and landing mid-stunt stops you [WP-SASRT] | **M**. A trick input window in the air, an animation, and landing boost tiers. Dep 008 (air state). Net: Local, plus an animation flag in the kart state. | A trick on every hay-bale ramp at the tourney field. The dog does a "sit-up and howl" or a shield spin (art TBD). | **must** (owner chose) |
| 8 | **Hang-time boost** | Longer air time gives a bigger boost, so players hop off lips to stretch it. | CTR: the landing turbo scales with time in the air [ATVI-CTR][PPX-CTR] | **S** inside #7 (boost = f(air time)). Net: Local. | Big drop into Dungeon Depths: a long fall that rewards a hop off the lip. | **strong** (merge with #7) |
| 9 | **Bounce pads** | Vertical chaos, routes only reached by bouncing, and a trick chance on each bounce. | MK Mushroom Gorge: red caps bounce and allow tricks, green caps do not, and a bounce is a shortcut over a chasm [MW-Gorge] | **S** once 008 has vertical velocity. Net: Local. | War-drum skins at the tourney band stand and straw-sack piles under the siege tower. Two colors: bouncy versus flat. | **strong** |
| 10 | **Launcher to another section** (cannon, catapult) | A spectacle shortcut. The flight is a set piece, and players can be hit or immune in flight (a design choice). | MK cannons: item-immune in DD, DS and Wii, hittable from 7 on [MW-Cannon] | **M**. A scripted ballistic arc per kart, then a hand-back to physics. Dep 008. Net: Local (each kart flies its own arc). | Castle: a trebuchet cradle at the keep flings karts over the wall onto the rampart road. Dungeon: a mine-lift spring. | **strong** |
| 11 | **Glide sections** | Air steering, a mid-air line choice and flyover views. | MK7 and 8 glide ramps (cyan panels, distinct from dash panels) [MW-Glide] | **L** (an air-control model, camera, and new geometry). Dep 008. Net: Local. | Banner-cape glide off the castle's highest tower. | **nice** (later) |
| 12 | **Half-pipes and quarter-pipes** | Trick walls on the side of a straight, so a straight still asks for input. | MK Wii half-pipes, marked by vertical panels [MW-Halfpipe] | **M** (a launch-up-and-return arc). Dep 008. Net: Local. | Curved buttress walls along the castle's outer ring. | **nice** |
| 13 | **Wall ride** | Driving up a wall for about 3 s, dodging items, wall-borne pickups. | MKW, after a jump boost [MW-WallRide][Kotaku-MKW] | **L** (needs a wall surface frame for the kart). Dep 008. Net: Local. | A Dungeon tunnel with smooth carved walls. | **skip** (cost against our flat-to-height kart model) |
| 14 | **Grind rails** | Ride a thin rail and charge a mini-turbo. It is a line choice and an item dodge. Designers added it so that "straight roads" are fun [NIN-ATD] | MKW rail ride [MW-Rail][Kotaku-MKW] | **L** (snap to a curve, balance, exit boost). Dep 008. Net: Local. | Dungeon: ride the old mine-cart rails beside the road. Castle: the drawbridge chains (a short rail). | **nice** (strong later for Dungeon) |

## 3. Routes and track structure

| # | Feature | What it adds | Seen in (source) | Cost / Dep / Net | Our idea (original) | Pri |
|---|---|---|---|---|---|---|
| 15 | **Pad-launched shortcut** | A boost pad placed so that only a racer at full speed clears a gap or barrier, combining speed, a jump and a shortcut. | CTR: a pad's speed makes a leap onto a platform that skips a bend [PS-CTRshort] | **S** (data placement). Dep 008. Net: Local. | The lava gap already does this flat. Add a pad before a rampart gap that needs pad speed plus a hop. | **strong** |
| 16 | **Lap evolution** (the track changes on lap 2/3) | Cheap novelty from the same geometry. It tells a story ("the siege begins"), and lap 3 decides the race. | SASRT tracks "terraform": bridges destroyed on lap 3 force flight, and blocks drop to close the previous lap's path [WP-SASRT][GIAG-SASRT]. MK8 lap-2 statue lasers [MW-BowserC]. CrossWorlds: the final-lap layout opens new paths and hazards [WP-CW] | **L** (track state per stage, swapped geometry or colliders, bots aware). Dep 009 and 008. Net: **Event**. The host announces "stage 2 at race time T" when the *leader* crosses the line, so all 12 PCs share one world (a per-racer lap would make two worlds). | Castle lap 2: the tourney banners drop and the gate opens a second lane. Lap 3: a rival kingdom's siege ram breaches the village wall, opening a new cut and closing the old one. Dungeon: see #6, plus a flooded lower tunnel on lap 3. | **must** (owner chose) |
| 17 | **Leader picks the next lap's route** | Agency for the leader, the pack must react, and chat can call it on stream. | CrossWorlds: the lap-1 leader picks one of two Travel Rings, and lap 2 runs in another world [WP-CW] | **M** on top of #16 (two stage-2 variants and a pick input). Dep 007 (HUD prompt). Net: Event. | At the end of lap 1 the leader rings one of two bells: "Bell of the Moat" floods the lower road, "Bell of the Keep" raises the portcullis route. | **strong** (high stream value) |
| 18 | **Randomized per-race layout** | Every race differs, so memorized lines stop working. Time trials keep a fixed layout. | MK8 Excitebike Arena: ramps and pads change every race, a standard layout is used in Time Trial, and the director cites 200+ layouts [MW-Excite][MKFan-Excite] | **S-M** if pads and ramps are data. Net: Clock-style. The host sends one seed in the race start, and every PC derives the same layout. | Joust-field ramps: the squires set out hay ramps in a different pattern each race. | **nice** |
| 19 | **Vehicle-gated routes** | Vehicle choice changes the race: a route only one class fits or can force open. | DKR: plane-only paths, and the vehicle choice decides the paths [WP-DKR] | **S** (a width gate, or a breakable that needs mass). Dep 006. Net: Local. | War-bikes fit the narrow tanner's alley. Armored carts can ram the flimsy fence of the sheep pen (#24). | **strong** |
| 20 | **Elimination rally** (multi-track, cuts at checkpoints) | A new mode: last places are out at each checkpoint, which suits 12 players. | MKW Knockout Tour: 6 checkpoints, the last four out at each [MW-MKW] | **L** (a mode, point-to-point routes). Net: Event. | A "Kennel Kingdom Run" from the castle down into the dungeon. | **skip** for now (a mode, not a track feature) |
| 21 | **Crossovers, loops, stacked roads** | See story 008. | MK8 and CTR (track design reference §4) | in 008 | — | (planned) |

## 4. Hazards and obstacles (beyond story 009)

| # | Feature | What it adds | Seen in (source) | Cost / Dep / Net | Our idea (original) | Pri |
|---|---|---|---|---|---|---|
| 22 | **Timed sweepers** (pendulums, rotating arms) | A rhythm hazard: read it, time it, go. | MKDS clock hands, pendulums and gears; MK8 tamed them into walls and trick ramps [MW-TickTock] | **S-M** per hazard on 009's timer system. Net: Clock. | Dungeon: a swinging mace over the jail corridor, and a turning water-wheel paddle. Note the MK8 lesson: knock-off hazards became walls, which is friendlier with 12 racers. | **strong** (009 follow-on) |
| 23 | **Wandering creatures that join later** | The road gets busier as the race goes on. Animals are both hazard and charm. | MK Wii: cows leave their fields after 30 s and become hazards [MW-Moo] | **S-M** (a patrol path, active after time T). Net: Clock. | A flock of sheep and a goose gang drift across the village lane after 30 s. Dungeon: giant rats cross the sewer bend. | **strong** |
| 24 | **Traffic along the road** | Weaving and line choice. Moving with or against racers reads differently. | MK Wii: highway traffic, and mine carts as obstacles in a mine [MW-Moonview][MW-GoldMine] | **M**. Net: Clock (paths parameterized by race time). | Castle: a supply wagon train trundles the outer road. Dungeon: ore carts (already in 009). | **nice** (009 has mine carts) |
| 25 | **Projectiles from the background** | Telegraphed danger "from the world", plus spectacle. | MK Wii: fireballs from a distant volcano [MW-Grumble]. DKR: a boss ship shoots at racers in one segment [MW-DKR] | **M** (target marks, a fall arc, an impact zone). Net: Clock (target i at time t from a seeded list). | Castle lap 3: the besiegers' catapult stones land on glowing target rings in the field. Dungeon: lava drips from ceiling cracks on a marked rhythm. | **strong** |
| 26 | **Player-triggered trap** | Players change the track for each other: chaos and grudges, ideal on stream. | Pattern; closest: MKW P Switches trigger events in Free Roam [MW-MKW] | **M** (a trigger, a timed effect, bot awareness). Net: Event (the toucher announces it). | A lever plate in the Dungeon drops a portcullis on the *right* lane for 4 s, so the leader can close it behind them. | **nice** |

## 5. Interactive and reactive scenery

| # | Feature | What it adds | Seen in (source) | Cost / Dep / Net | Our idea (original) | Pri |
|---|---|---|---|---|---|---|
| 27 | **Breakable props** (crates, barrels, cutouts) | Juice and stream laughs. They can slow you, drop an item, and respawn. | MK crates break, release an item and slow you (from MKDS) [MW-Crate]. MK7 and 8 wooden cutouts break and respawn [MW-Cutout]. CTR crates [ATVI-CTR] | **M**. Two tiers. (a) **Cosmetic** debris: each PC breaks its copy when any kart touches it, with no message. (b) **Item crates**: copy the item box announce (004). Dep 004. | Castle: apple-cart crates, cider barrels and wooden knight cutouts at the village. Dungeon: bone piles and powder kegs that puff smoke. | **must** (owner chose) |
| 28 | **Destructible shortcut** | The first racer to break it opens a route for everyone for N s. A race moment. | Pattern from SASRT's terraforming and dropping blocks [GIAG-SASRT]. Original as a player-caused version | **M**. Net: Event (the breaker announces it with a race time; it closes on the clock). Dep 006 (carts break it, bikes bounce off). | A rotten stable fence: an armored cart at full speed smashes it, opening a cut through the hay barn until it is "rebuilt" next lap. | **strong** |
| 29 | **Cheering, reacting crowds** | The place feels inhabited and the race feels like an event. A crowd cheer on an overtake reads well on stream. | MKW devs: time of day and life make the world "feel inhabited" [NIN-ATD]. Our track reference §8 | **S-M** (low-poly crowd cards, a wave or cheer on a nearby pass, a roar on a lead change). Net: Cosmetic. Dep 007 (crowd audio). | Hound knights and pup squires in tourney stands, waving pennants as the leader passes. Dungeon: prisoners rattle cell bars and cheer. | **must** (owner chose) |
| 30 | **Reacting animals** | Small surprises that reward attention, like chickens scattering. | MK cows [MW-Moo]. Pattern (ambient, non-hazard) | **S** (a flee animation on proximity). Net: Cosmetic. | Hens scatter in the village, a falcon lifts off its post, a chained guard hound barks at drifting karts. | **must** (owner chose) |
| 31 | **Flags, banners, cloth** | Free motion, shows the wind direction (needed for #36), and color-codes zones. | Common across the genre; MKW day/night life [NIN-ATD] | **S** (vertex-shader sway). Dep 010 (shared materials). Net: Cosmetic. | House banners per zone; the leader's color is hoisted on the keep each lap. | **must** (cheap) |
| 32 | **Track collectibles that raise top speed** | A line choice (pick-up rows on risky lines), lost on hits, so hits sting more. A comeback lever. | MK coins: up to 10, raise top speed, dropped when hit, respawn [MW-Coin]. DKR bananas up to 10 [WP-DKR]. CrossWorlds rings raise top speed and are lost on contact [WP-CW] | **M**. Net: Local if **per-player instanced** (each PC hides only its own pickups, which is fair and needs no sync). Dep 004 (lose some on a hit). | "Gold biscuits", up to 10, +0.4 m/s top speed each (est.), drop 3 on a hit. Rows sit along the rail-less drawbridge edge and the lava gap line. | **strong** |

## 6. Boost and speed features

| # | Feature | What it adds | Seen in (source) | Cost / Dep / Net | Our idea (original) | Pri |
|---|---|---|---|---|---|---|
| 33 | **Slipstream / drafting** | Pack racing with 12: chasers gain on the leader's straights. Skill in timing the pull-out. | MK since 64 [MW-Slip]. TSR slingshot: longer drafting gives a bigger boost [TSR-PS] | **S-M** (a cone test against remote karts' view positions, a charge, then a boost). Net: Local (uses the interpolated positions already drawn). | "Riding the banner wind": a pennant-streamer trail behind the kart shows the draft cone. | **strong** |
| 34 | **Moving boost gates and rings** | A boost you have to aim at, in the air or on the road. | CrossWorlds frenzy: moving boost gates [WP-CW]. SASRT plane boost rings [GI-SASRT] | **S** (a ring trigger plus a motion path). Dep 008 for air rings. Net: Clock. | Banner arches after the trebuchet launch (#10). A sliding "squire's hoop" gate on the joust straight. | **nice** |
| 35 | **Bump boost zone** | Turns contact into a reward in one zone: both karts gain speed, which makes pack chaos fun. | MK8 Spin Boost: colliding in anti-gravity gives both racers a boost [MW-Spin] | **S** (a zone flag on the bump response from story 001). Net: Local (each PC boosts its own kart on contact). | **The Jousting Lists**: a fenced straight where kart-to-kart bumps give both a "lance boost". A strong medieval fit. | **strong** |

## 7. Environment and weather

| # | Feature | What it adds | Seen in (source) | Cost / Dep / Net | Our idea (original) | Pri |
|---|---|---|---|---|---|---|
| 36 | **Wind gusts** | A lateral push you steer against on exposed sections. Banners give the warning. | MK7 pipes push karts, and MK8 DS Shroom Ridge wind is a shortcut [MW-Wind] | **S-M** (a force zone with an intensity of f(race time)). Net: Clock. | Castle ramparts: gusts every 6 s (est.), telegraphed by banners snapping. | **nice** |
| 37 | **Weather and time-of-day variants** | The same track feels fresh, and wet means slick. Dev caution: every lighting variant must be re-checked for readability [NIN-ATD] | MKW weather and time of day; rain makes roads slippery [MW-MKW][MW-Rain] | **L** (lighting variants, test cost). Dep 010. Net: Event (in the race start). | "Dusk Tourney" (torch-lit Castle) and a rain variant with slick cobbles (#4). | **nice** (after 010) |
| 38 | **Darkness and light pools** | Mood in the Dungeon. Readability must stay intact. | Dark tracks are criticized for readability (track reference §4, item 6) | **S** (a lighting rule, mostly 010). | Torches on the *outside* of every corner, a lava glow on the danger edge, a lit item row. | **must** (as a rule) |

## 8. Spectacle and set pieces

| # | Feature | What it adds | Seen in (source) | Cost / Dep / Net | Our idea (original) | Pri |
|---|---|---|---|---|---|---|
| 39 | **Acting giant landmark** | A marquee moment: the track's identity, a clip, a timed hazard. | MK8 castle centerpiece statue that punches the two paths [MW-LavaBowser] | **M-L** (a big animated prop plus #22-style timing). Dep 009 and 010. Net: Clock. | Dungeon: a colossal stone hound-knight statue slams its shield on alternating lanes (glow and rumble 1.5 s before; est.). | **strong** |
| 40 | **Background event that changes the track** | A story told by the track, on a schedule. | SASRT dragons destroy the bridges on lap 3 [SASRT-wiki via search; WP-SASRT] | Part of #16. Net: Event. | The siege ram breach (#16) happens *on screen*: dust, crowd panic and a crumbling wall. | **strong** (with #16) |
| 41 | **Flyovers that drop items** | Things in the sky reward looking up and add chaos. | MKW: seaplanes and helicopters sometimes drop Item Boxes [MW-MKW] | **M**. Net: Event (the host announces the drop spot and time). | A royal falconer's hawk drops an item crate on the field on lap 2. | **nice** |

## 9. Multiplayer, online and stream

| # | Feature | What it adds | Seen in (source) | Cost / Dep / Net | Our idea (original) | Pri |
|---|---|---|---|---|---|---|
| 42 | **Spectator camera for finished racers** | With 12 racers, finished players keep watching. On stream, it cuts to the action. | Common in online racers. **Not confirmed** for MK8DX in our search (MK8 has a replay reel instead [MW-Reel]) | **S-M** (a camera that follows the leader, the closest battle or an active set piece; uses existing remote state). Dep 007. Net: none new. | The "Herald Cam" cycles between the leader, the tightest gap and the next big set piece (#39, #16). | **strong** |
| 43 | **Shared event callouts** | Everyone knows what the world is about to do, for fairness and hype. | Pattern. Lap-gated hazards need it (#16) | **S** (HUD banner plus sound on Clock or Event triggers). Dep 007. | A herald's voice: "The gate opens!", "Siege on the last lap!". | **strong** |
| 44 | **Ghosts, staff times, replays** | Solo practice and route learning. A clip reel for the streamer. | MK staff ghosts and uploads [MW-Ghost]. MK8 Highlight Reel [MW-Reel] | **M** for ghosts (record the kart state, which the debug autopilot CSV already resembles). **L** for replays. | Time trial against a "Royal Champion" ghost. | **nice** |

## 10. Accessibility and readability

| # | Feature | What it adds | Seen in (source) | Cost / Dep / Net | Our idea (original) | Pri |
|---|---|---|---|---|---|---|
| 45 | **One visual language for track features** | Players read the track at 26-35 m/s. Each feature type gets its own color and motion. | MK: glide ramps in cyan so they are not confused with dash panels; half-pipes marked by vertical panels [MW-Glide][MW-Halfpipe] | **S** (a rule in the art bible and track theme). Dep 010. | Gold chevrons = boost; red-white hay = trick ramp; brown speckle = off-road; a pulsing ember ring = incoming hazard. | **must** |
| 46 | **Telegraph windows** | Every timed or world hazard warns ≥1.0 s ahead (est.) with sight plus sound. No unfair hits. | Track reference §4, item 6. MK8 softened its knock-off hazards [MW-TickTock] | **S** per hazard. Net: Clock (the warning is part of the same timeline). | Shadow plus whistle before a catapult stone, a rumble before the statue slam. | **must** |
| 47 | **Minimap feature icons** | Shows open or closed shortcuts and lap-stage changes. | Pattern | **S**. Dep 007 (the minimap exists in the brief). | The drawbridge icon goes red when it is raised. | **nice** |

## 11. Recommended story breakdown (must and strong only)

Numbers are proposals (next free after 010). Sizes are estimates. "Both" = Castle Circuit and Dungeon Depths.

| Order | Story (proposed) | Features | Depends on | Size | Tracks |
|---|---|---|---|---|---|
| 1 | **011 Surfaces and off-road** | #1 off-road, #2 boost-cut, #3 shallows, #45 visual language (surface part), #4 slick (optional) | 003. Uses 004's War Horn for cuts, but pads and drift boosts already work. **Can start now (flat).** | M | Both |
| 2 | **012 Living and breakable scenery** | #27 breakables (cosmetic + item crates), #29 crowds, #30 animals, #31 banners, #23 wandering flock (clock patrol) | 003. 004 for item crates. Props as primitives now; **010 restyles them** (shared materials). 007 for crowd audio. | M | Both |
| 3 | **013 Pack-racing speed** | #33 slipstream, #32 gold biscuits, #35 Jousting Lists bump boost, #19 vehicle-gated route (bike alley, cart ram) | 001 bump response, 002 view positions, 004 (lose biscuits on a hit), 006 (vehicle classes) | M | Both (Lists: Castle) |
| 4 | **014 Air tricks and launchers** | #7 tricks, #8 hang-time, #9 bounce pads, #10 trebuchet launcher, #15 pad-launched gap | **008** (vertical velocity, landing). 005 bots learn tricks at a basic level. | M-L | Both |
| 5 | **015 Lap evolution** | #16 lap 2/3 changes (leader-crossing Event), #6 crumbling flagstones, #17 leader's bell choice (if time), #40 on-screen siege breach, #28 destructible fence, #43 herald callouts | **009** (timer and hazard system), **008** (sinking), 005 (bots read stage), 007 (callouts) | L | Both |
| 6 | **016 Set pieces and Herald Cam** | #39 hound-knight statue, #25 catapult barrage and lava drips, #22 mace and water-wheel sweepers, #42 spectator cam, #46 telegraph rule audit | 009, 008, 010 (look), 007 (HUD) | L | Both (statue: Dungeon; barrage: Castle) |

Ordering notes (est.):
- 011 and 012 need nothing new and can run before or beside 004-006. 012's props should exist before 010 so the graphics pass styles them once.
- 013 lands after 004 and 006. 014 directly after 008. 015 and 016 after 009.
- Every story keeps the existing gates: `tools/track_check.gd` (nothing fully blocks the main road), the 12-racer stress test, and retained screenshots.

**Sync rule for all six:** prefer Local, Clock and Cosmetic. Use one Event (a host or owner announcement with a race time) only for shared world
state: lap stages, broken shortcuts, item crates and bell choices. Never use shared kart-pushed physics objects.

## 12. Sources

Keys used above. Fan-wiki claims are marked as such; mariowiki and Wikipedia pages were read 2026-11-20 unless noted.

- [MW-Series] https://www.mariowiki.com/Mario_Kart_series (off-road: shallow water, grass, mud)
- [Prima] https://primagames.com/eguides/mario-kart-8-deluxe-eguide/how-to-drive/terrain (no drift or top speed off-road unless boosting)
- [MW-DryDry] https://mariowiki.com/Wii_Dry_Dry_Ruins · [MW-Mud] https://www.mariowiki.com/Mud
- [MW-Rain] https://www.mariowiki.com/Rain (MKW rain and storms; slippery-road claims come from pre-launch previews)
- [MW-TickTock] https://www.mariowiki.com/Tick-Tock_Clock_(race_course)
- [MW-Grumble] https://www.mariowiki.com/Grumble_Volcano
- [MW-Trick] https://www.mariowiki.com/Trick · [MW-Gorge] https://mariowiki.com/Mushroom_Gorge
- [MW-Cannon] https://mariowiki.com/Cannon_(Mario_Kart_series) · [MW-Glide] https://www.mariowiki.com/Glide_Ramp
- [MW-Halfpipe] https://mariowiki.com/Half-pipe_(object) · [MW-WallRide] https://www.mariowiki.com/Wall_ride
- [MW-Rail] https://www.mariowiki.com/Rail_ride and https://www.mariowiki.com/Grindrail
- [Kotaku-MKW] https://kotaku.com/mario-kart-world-rail-wall-charge-jump-ride-switch-2-1851784648
- [MW-MKW] https://www.mariowiki.com/Mario_Kart_World (routes, Knockout Tour, water surfing, day-night cycle, item-dropping aircraft, P Switches)
- [NIN-ATD] Nintendo "Ask the Developer Vol. 18, Mario Kart World, Chapter 2": https://www.nintendo.com/en-gb/News/2025/May/Ask-the-Developer-Vol-18-Mario-Kart-World-Chapter-2-2832717.html
- [MW-BowserC] https://mariowiki.com/Bowser%27s_Castle_(Mario_Kart_8) · [MW-LavaBowser] https://mariowiki.com/Lava_Bowser
- [MW-Excite] https://www.mariowiki.com/Excitebike_Arena · [MKFan-Excite] https://mariokart.fandom.com/wiki/Excitebike_Arena (fan wiki; the 200+ figure is attributed to the director)
- [MW-Moo] https://mariowiki.com/Moo_Moo · [MW-Moonview] https://www.mariowiki.com/Moonview_Highway · [MW-GoldMine] https://www.mariowiki.com/Wario's_Gold_Mine
- [MW-Crate] https://mariowiki.com/Crate · [MW-Cutout] https://www.mariowiki.com/Kuppa_Kanban (wooden cutouts)
- [MW-Coin] https://www.mariowiki.com/Coin · [MW-Slip] https://mariowiki.com/Slipstream · [MW-Spin] https://www.mariowiki.com/Spin_Boost
- [MW-Wind] https://mariowiki.com/Wind · [MW-Ghost] https://www.mariowiki.com/Ghost_(Mario_Kart_series) · [MW-Reel] https://mariowiki.com/Highlight_Reel
- [MW-DKR] https://mariowiki.com/Diddy_Kong_Racing · [WP-DKR] https://en.wikipedia.org/wiki/Diddy_Kong_Racing
- [WP-SASRT] https://en.wikipedia.org/wiki/Sonic_%26_All-Stars_Racing_Transformed (gates, boat waves, stunts, terraforming)
- [GIAG-SASRT] https://godisageek.com/2012/07/sonic-all-stars-racing-transformed-hands-on-preview/ (blocks drop on the previous lap's path)
- [GI-SASRT] https://gameinformer.com/games/sonic__all-stars_racing_transformed/b/xbox360/archive/2012/11/18/sonic-%26-all-stars-racing-transformed-review (boost rings)
- [SASRT-wiki] https://sonic.fandom.com/wiki/Sonic_%26_All-Stars_Racing_Transformed (dragons destroy the bridges on lap 3; seen via search snippet, page refused fetch, HTTP 402)
- [WP-CW] https://en.wikipedia.org/wiki/Sonic_Racing:_CrossWorlds (Travel Rings, frenzy boost gates, final-lap changes, rings raise top speed, 12 online)
- [TSR-PS] https://www.pushsquare.com/news/2019/05/guide_team_sonic_racing_-_tips_and_tricks_for_beginners
- [ATVI-CTR] https://support.activision.com/content/atvi/support/web/en/crash-team-racing/articles/crash-team-racing-nitro-fueled-gameplay-tips.html
- [PPX-CTR] https://www.powerpyx.com/crash-team-racing-nitro-fueled-boost-mechanics-explained/
- [PS-CTRshort] https://www.pushsquare.com/news/2019/07/guide_ctr_nitro-fueled_-_where_to_find_all_shortcuts

**Gaps:** the Sonic and Crash fandom wikis refused automated fetches, so their claims come via search snippets or other sources.
KartRider: Drift, Beach Buggy Racing and Garfield Kart turned up no track-feature specifics, so they are not cited. We found no GDC
talk on kart track features; the Nintendo developer interview is the only first-party design source.
