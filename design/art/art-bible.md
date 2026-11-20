# Art Bible: Dogworks Racing: Kennel Kingdom

> **Status**: Approved
> **Owned By**: art-director
> **Last Updated**: 2026-11-20
> **Art Director Sign-Off (AD-ART-BIBLE)**: SKIPPED 2026-11-20 — solo mode

`/art-bible` writes these nine sections in this order and replaces each
section's `[To be designed]` line as that section is approved. A section still
holding its placeholder is incomplete; a later run fills only those.

## 1. Visual Identity Statement

**Visual rule:** If it isn't readable at a glance on a compressed 12-racer stream, it isn't finished: bold shape and flat color first, detail second.

**Supporting principles**

- **Logo-first shape language** (anchor: the DogworksTV badge and the knight-dog brand)
  - Chunky low-poly silhouettes, thick dark outlines, flat color blocks, rounded storybook forms; the mascot's red-orange and cream is the loudest color in any scene.
  - *Design test:* When a model or prop could be either realistic or stylized, choose the simpler, bolder shape that would still look right inside the logo badge.

- **Racers pop, world supports** (anchor: "12-racer online chaos" and readable on stream)
  - The world uses muted castle-stone greys and grass greens; racers, pennants, items and hazards get the saturated, high-contrast colors. Every vehicle flies its racer's pennant as the identifier (shape and color, never detail).
  - *Design test:* When a track element competes with a racer or item for attention, choose the option that lowers the track element's contrast or saturation and keeps the racer's silhouette clear.

- **Storybook warmth, comic chaos** (anchor: "chaotic laughs and photo-finish races")
  - Bright, friendly light and parchment-cream UI keep the tone playful, never grim. Dungeon Depths goes dark stone with warm torchlight and lava glow, but stays cozy-spooky and keeps track edges and racers legible.
  - *Design test:* When an effect or mood choice could look scary or realistic, choose the exaggerated, funny read (big squash, bold puff, readable hit) that lands a laugh and shows who got hit.

- **Sources:** a mix of Mario Kart 8 Deluxe, Sonic & All-Stars Racing Transformed and Crash Team Racing Nitro-Fueled (pattern lessons only: readability, color hierarchy, boost feedback) with the DogworksTV name and dog and the medieval castle setting. Nothing is copied from those games' characters, tracks or looks.

## 2. Mood & Atmosphere

Anchor: "chaotic laughs and photo-finish races, played on stream with friends". Energy is 1 (calm) to 5 (peak). Every state keeps the outline-ink and flat-color rules from Section 1.

- **Main menu / lobby** (energy 2): "Come on in, the squad's here."
  - Light: warm key from the upper left, cream-gold ambient, soft vignette; ~5200K, low contrast.
  - Descriptors: cozy, welcoming, parchment, tavern-bright.
  - Knight dogs idle on a stone dais with pennants waving. Parchment banner UI is the focus. No harsh shadows.
- **Countdown / start** (energy 3, ramps to 5 on GO): "Hold it... hold it..."
  - Light: the scene stays at the track's own light. The vignette tightens 10% per beat. The horn blast on GO flashes a 0.15 s cream wash.
  - Descriptors: tense, expectant, ceremonial, tight.
  - Torches and pennants snap to full motion on GO.
- **Racing: Castle Circuit** (energy 4): sunny storybook day.
  - Light: high noon-to-afternoon sun, ~5600K, soft blue-grey shadows (never black), sky `#8EC9F0` with chunky cream clouds.
  - Descriptors: bright, festive, breezy, picture-book.
  - World saturation stays about 35% below racer saturation (the "racers pop" rule).
- **Racing: Dungeon Depths** (energy 4): cozy-spooky, never grim.
  - Light: ambient dark stone ~2800K at 25% of daylight value. Warm torch pools (amber) and lava glow (orange rim light) carry the read.
  - Descriptors: flickery, snug, rumbling, warm-in-the-dark.
  - Track edges and racers keep a minimum rim light. Shadows are plum-black, never pure black. Fog is purple-brown, not grey.
- **Boost / drift** (energy 5): speed and payoff.
  - Light: the kart pulses a local glow. FOV +8% and screen-edge streaks on boost; no full-screen color grade.
  - Descriptors: crisp, snappy, sparkling, whooshing.
  - Tier color escalates the read (Section 4). The world dims 5% around the kart so the sparks win.
- **Item hits / chaos** (energy 5): slapstick, never cruel.
  - Light: a 0.1 s hit-flash on the victim, then a squash-and-stretch spin. Comic star puffs and dust rings.
  - Descriptors: goofy, exaggerated, readable, bouncy.
  - The attacker and the victim must be identifiable from the effect alone.
- **Photo finish / results** (energy 5, then 3): "Who won? Replay it!"
  - Light: a golden warm-up (+300K) on the winner, confetti in pennant colors, a slow-motion beat at the line.
  - Winner: spotlit podium, cream-gold glow, crown pop. Also-rans: still warm and cheerful, with a slump or a laugh animation. No grey-out or shaming; the rematch prompt is always visible.
  - Descriptors: triumphant, rowdy, affectionate.
- **Respawn after moat / lava** (energy 3): a laugh, then a reset.
  - Moat: a big splash and foam ring, then a bubble-pop lift-out. Lava: a scorch puff and a cartoon "singe", never burning.
  - A short lantern-light tether carries the racer back to the track. A 0.5 s ghost shimmer marks the invulnerable window.
  - Descriptors: sheepish, bouncy, quick.
- **Distinctness rule:** the menu is parchment-warm and static; Castle is bright cool-sky; Dungeon is dark with warm pools; chaos states are the only ones with full-screen flashes.

## 3. Shape Language

Anchor: the DogworksTV badge (chunky, rounded, thick-outlined). Stream-readable at 12 racers.

- **Core grammar**
  - Round = friendly (racers, pickups, UI). Pointed = threat (hazards, lava, spikes). Chevron or arrow = go faster.
  - Everything is a chunky low-poly primitive with a bevel. Nothing thinner than a 2 world-unit stroke at kart scale.
  - Outlines: racers 4 px, track props 3 px, distant scenery 2 px (at 1080p; inverted hull or post-process). Outline color is Outline Ink (Section 4).
- **Racer silhouette (hero shapes)**
  - Knight dog: chibi, head about 45% of body height. A large rounded helmet with the visor up and two ear shapes that vary per breed: the one distinguishing trait per archetype.
  - Armored cart: a wide trapezoid, low and steady, with big round wheels. War-bike: a tall narrow wedge with a leaning rider. The two must separate in a pure silhouette test at 64 px.
  - Pennant: a swallowtail triangle on a tall pole, always the tallest element on the vehicle (~1.2x vehicle height), always the racer's identity color plus one pattern shape (Section 4).
  - Racer silhouettes are never hidden by a prop of the same contrast.
- **Environment geometry (supporting shapes)**
  - Rounded storybook forms: tapered towers, leaning timber frames, bulging walls. Corners are chamfered, not sharp.
  - Large simple planes with one accent shape per surface (a banner, a crest, a window). Detail is a second-read feature, never needed at distance.
  - Verticals taller than the camera (keep, towers) are broad and simple, so they never become noise behind racers.
  - Track edge: a continuous curb stripe (cream and Castle Stone) and a visible lip. Dungeon: a lit rim stripe on the edge.
  - Dungeon geometry is chunkier and lower: arches, rock lumps, crooked beams. Same grammar, darker values.
- **Pickups and gameplay shapes**
  - Item box: a rotating, bobbing cube with a ribbon and a "?" crest; always a cube, and nothing else is.
  - Boost pad: a flat road decal with an animated chevron stack. Hazards: a jagged zigzag edge (lava crust) or a wave-line rim with foam (moat).
  - Each item has a unique silhouette (horn curve, stone ball, cauldron pot, falcon wing-spread, kite shield), readable as a flat icon in a circle.
- **UI shape grammar**
  - Parchment banner: rounded rectangle (12 px radius), 4 px ink outline, curled ends: the logo's banner shape.
  - Item slot: circle. Place display: a banner with a big numeral. Minimap: a rounded-square parchment tile with a chunky track line and racer dots as pennant triangles.
  - No thin hairlines, no sharp corners, no drop shadows beyond a 3 px offset block.
- **Hero vs supporting hierarchy (loudest to quietest)**
  1. Racers and pennants. 2. Items, boxes, pads and hazard hits. 3. Track edge, curbs and gates. 4. Landmarks (keep, statue). 5. Props and scenery.
  - When two shapes compete, lower the outline weight and contrast of the lower tier before changing the higher one.

## 4. Color System

Hex values are proposed starting points, to be tuned in-engine. Simple flat colors first (Section 1).

- **Primary palette**
  - Mascot Red-Orange `#E8452C`: hero and brand; racer slot 1, banner headers, primary buttons.
  - Parchment Cream `#F6EBD0`: UI base, mascot trim, the light counterpart of outlines, curbs.
  - Outline Ink `#2A1E26`: all outlines and UI text. A warm plum-black, never pure black.
  - Castle Stone `#8C919A`: walls, road shoulders, props (muted).
  - Meadow Green `#6FA05A`: grass, hedges, orchard (muted, ~40% saturation).
  - Torchlight Amber `#F2A33A`: warm light, lamps, Dungeon pools, "warmth" accents.
  - Sky Blue `#8EC9F0`: sky and distant water only.
- **Racer identity (12 slots; slot 1 = the mascot, 1–8 = the 8 knight dogs, 9–12 = extra kart colors for 12 online players)**
  - 1 `#E8452C` red-orange, 2 `#F2C14E` sun yellow, 3 `#2F6FDB` royal blue, 4 `#1FA37A` emerald, 5 `#8E44C9` violet, 6 `#F2F2F2` snow white, 7 `#3A3F4B` charcoal (cream trim), 8 `#7CC4F5` sky blue, 9 `#A0522D` sienna, 10 `#C2185B` crimson, 11 `#B8E04A` chartreuse, 12 `#D9A7F0` lavender.
  - Each slot also has a pennant pattern: solid, stripe, chevron, dots, checker, cross, split, diamond, border, star, wave, tri-band. Color is never the only identifier.
  - The local player gets a cream ring and an arrow marker above the pennant (shape, not color). Pink `#FF4FA3` is reserved for item boxes and is never a racer color.
- **Semantic colors**
  - Drift tiers (spark color): T1 `#3FA9FF`, T2 `#FF9A1F`, T3 `#A64DFF`. Boost flame: white core `#FFF1A8`, outer flame in the current tier color (the War Horn boost uses T2 orange); a longer flame means a higher tier.
  - Boost pad: cyan `#22E6E0` with white `#FFFFFF` chevrons, emissive. Item box: hot pink `#FF4FA3` cube with a cream ribbon.
  - Items (icon and effect accent): War Horn `#F5C542` gold; Catapult Stone `#7A7F8C` slate with a `#FF7A33` ember trail; Cauldron Spill `#8BE04E` lime slick with bubble shapes; Falcon `#4C5FD7` indigo with a `#FF3B3B` lock-on ring; Shield `#E4EAF2` steel with a translucent `#FFE48A` bubble.
  - Hazards: moat `#3F86B5` (foam rim `#EAF4F8`, matte, wave lines); lava core `#FF6A1A`, bright `#FFC24A`, crust `#3B1D18` (animated, emissive, jagged).
  - Place display: 1st `#F5C542`, 2nd `#C8D3E0`, 3rd `#C98A4B`, 4th and below `#F6EBD0`, each with a numeral and an ordinal suffix.
- **Per-area temperature**
  - Castle Circuit: warm sun (~5600K) over cool-grey stone; accents warm.
    - Tourney Field: the warmest and most festive; pennant reds, pavilion stripes in cream, red and yellow.
    - Moat and Gatehouse: the coolest area, blue water with stone-grey walls; the only place cool blues dominate.
    - Market Village: warm timber browns (the `#A0522D` family), cream plaster, awnings in muted red and yellow.
    - Keep Courtyard: neutral-cool stone `#8C919A`, gold flag accents on the keep.
    - Rampart Gardens: greens `#6FA05A` with warm orchard dots (peach and apple red at 40% saturation).
  - Dungeon Depths: cool plum-grey stone ambient (~2800K); light pools are warm.
    - Cellar Vaults: the darkest and coolest, sparse amber torches. Torch Gallery: rhythmic amber pools on cool stone.
    - Great Cavern: lava-orange lake light over dark basalt, the hottest and widest glow. Mine Works: warm timber and lantern yellow, cool rock. Lava Forge: the hottest, orange and amber rim light, black-red crust.
  - Rule: in every area, world saturation stays below the racers'. The track edge and racing line keep a value step of at least 20% from the surrounding scenery.
- **UI palette and divergence**
  - Parchment `#F3E6C4` panels, Ink `#2A1E26` text, Red-Orange `#E8452C` primary button, parchment secondary button, disabled `#B8AE96`, focus ring `#F5C542` with a thicker outline.
  - Divergence from the world: the UI is flat parchment, no gradients, no world lighting, always full brightness. Semantic colors (cyan, pink, lime) appear in the UI only when they carry that meaning (item icons, drift meter), never as decoration.
- **Colorblind safety (backup for each failing pair)**
  - Drift tiers blue / orange / purple: blue and purple merge under protanopia and deuteranopia, and orange drifts toward yellow-brown. Backup: spark shape (T1 round dots, T2 4-point stars, T3 stars plus a ring burst), spark count, a rising pitch tick per tier, and a 3-pip HUD meter.
  - Cyan pads vs moat water: both read blue-green under tritanopia and at low saturation. Backup: animated chevrons and emissive glow on the pad; the moat has a foam rim, wave lines and a splash sound, and is never on the racing line.
  - Lava vs mascot red-orange vs the orange tier: all orange. Backup: lava is animated, emissive and jagged with a dark crust; the mascot always has its cream trim and outline; tier sparks are small particles near the kart.
  - Racers 1 / 4 / 11 (red, green, lime) and 2 / 11 (yellow, lime) under deuteranopia: backup is the per-slot pennant pattern plus a name tag and the place number; never color alone.
  - Cauldron lime vs meadow green: backup is the bubble shape, a glossy flat lime and a splat sound.
  - Item pink vs red: backup is the cube shape and rotation, plus a pickup chime.
  - Falcon lock-on red: backup is a shrinking ring shape and a warning sound.
  - Colorblind mode option: swap the tier colors to blue `#3FA9FF`, yellow `#FFE14D` and magenta `#FF4FA3`; retest with a color-vision simulator during implementation.
- **Known risks to check in playtests:** lava, the mascot red-orange and the T2 orange tier are all orange; if they blur, move lava toward yellow-orange or shift T2 to yellow. Racer colors 9–12 (sienna, chartreuse, lavender) are the weakest and need a pennant-pattern check on the 12-racer stream view. Pink item boxes depart from the genre's usual gold to guarantee contrast against greens, stone and dungeon darkness.

## 5. Character Design Direction

Anchor: the DogworksTV mascot and "racers pop, world supports" (Section 1). Every racer must read as *that* dog from the chase camera on a compressed stream.

- **Archetype: the knight dog.** Chibi proportions (head ~45% of body height, Section 3), big eyes with large pupils and white highlights, a short muzzle, a chunky body in simple armor. The face is always visible: helmets are worn visor up (as in the logo) or are open-faced.
  - The mascot (slot 1) matches the logo: red-orange and white fur, yellow eyes, a rounded knight's helmet with the visor up. It is the reference model; the other seven are built to its scale and line weight.
- **Telling the 8 racers apart (one primary trait each, in this order of strength):**
  1. Ear shape and head shape per breed (pointed, floppy, bat ears, round; long or short muzzle). This is the silhouette trait.
  2. Helmet variant (rounded knight's helmet, kettle hat, horned helm, plumed helm, crown-helm, hood-and-coif...), each a different silhouette above the head.
  3. Body color and the racer's identity color (Section 4) on the tabard, cart paint and pennant.
  - *Design test:* when two racers look alike in a 64 px grey silhouette, change the ears or the helmet first, never only the color.
- **No enemies, NPCs or teams in a race.** Every kart is a racer. Bots use the same roster; they are told apart only by the name tag ("BOT"). The local player gets the cream ring and arrow marker (Section 4); online friends get their name tag above the pennant.
- **Vehicles**
  - Armored cart: a wooden cart body with bolted iron plates, big round wheels, a round shield on the nose bearing a paw crest, and the pennant pole at the back.
  - War-bike: a two-wheeler styled like an armored steed, with a horse-head prow in plate armor, a saddle-style seat, and the pennant behind the rider. The rider leans forward (Section 3).
  - Vehicles take the racer's identity color on large panels only; trim is Parchment Cream or iron grey.
- **Expression and pose: exaggerated, comic, never hurt.**
  - Four faces: determined (racing), big grin (boost, overtake, win), dizzy swirl eyes with stars (hit, spin-out), wide-eyed panic (falling into the moat or lava).
  - Ears and tail are secondary motion: they stream back on boost, flop on a hit, wag on a win.
  - Poses: lean into turns, a big wind-up arm for throwing items, a two-arm cheer on the podium, a slump with a laugh for also-rans (Section 2).
  - *Design test:* when an animation could be realistic or cartoony, choose the one with a bigger squash, stretch or held pose.
- **Detail at camera distance (LOD philosophy).** At the chase camera a racer fills ~10–15% of the screen height; rivals 20 m ahead fill ~3%.
  - Must survive at 3% (the farthest rival): helmet silhouette, ear shape, identity color, pennant.
  - Must survive at 10%+ (your own kart and close rivals): eyes and expression, tabard emblem, cart crest.
  - Never modeled: fur strands, small rivets, chain-mail texture, fingers beyond a mitten paw.
  - Lower detail levels drop the face and the crest first and keep the silhouette, the color and the pennant to the last level.

## 6. Environment Design Language

Anchor: "storybook warmth" and "racers pop, world supports" (Section 1).

- **Architecture: the Kennel Kingdom, a storybook medieval realm built by dogs.** Generic European castle-town forms (curtain walls, round towers with cone roofs, timber-frame houses, a keep), bent toward dogs so the setting is ours and not a generic fantasy castle:
  - Roofs have the steep pitch and overhang of a doghouse; doorways are rounded "kennel arches".
  - Recurring motifs: the paw crest (banners, shields, the keep's gate), bone shapes (railing posts, the drawbridge chains, battlements' merlons on the keep), food bowls as fountains and wells.
  - Proportions are storybook: towers lean slightly and taper, walls bulge, everything is chamfered (Section 3).
  - *Design test:* when a building could be "any castle", add one dog motif at its largest scale (a paw crest on the gate, a bone balustrade), never small decoration.
- **Dungeon Depths: the kingdom's underworld.** Wine cellars and storerooms, then mines and a forge run by dog miners and smiths. Same motifs, rougher: timber props, chewed-bone piles, horseshoe and collar moulds in the forge.
- **Texture philosophy: stylized and flat, not PBR.**
  - Toon shading with 2–3 light bands plus the ink outline (Section 3). Color comes from flat albedo and vertex color.
  - Surfaces get one simple tiling pattern at low contrast (brick courses, plank grooves, cobble dots, roof shingles, grass tufts), never photographic textures, normal-map detail or grime.
  - Why: stream compression destroys fine texture first (Section 1); flat, bold surfaces keep racers readable and keep the 60 fps budget.
  - Water and lava are the only animated surfaces: scrolling flat bands, foam rims, a slow glow pulse (Section 4).
  - *Design test:* when a surface looks busy at the chase camera, remove its pattern before changing its color.
- **Prop density by area type** (from the track study: something stands within one road width of each edge on 70–90% of a lap):
  - Enclosed zones (Tourney Field stands, Market Village streets, Dungeon galleries): dense, continuous edges (walls, facades, stands, barrel racks) that frame the road.
  - Open zones (Moat, Rampart Gardens, the Great Cavern): sparse foreground, big background vistas (the keep, the lava lake), so the lap breathes.
  - Never on the racing line: only gameplay objects (item boxes, pads, hazards) sit on the road. Props near the road keep a 20% value step from the road and racers (Section 4).
  - Tall props (towers, trees) stay 2+ m back from the wall so they never hide racers at the chase camera.
- **Environmental storytelling (no text):**
  - Tourney Field: dog spectators in the stands wave pennants in the racers' identity colors; a jousting fence and a herald's stand.
  - Moat and Gatehouse: the drawbridge chains, a portcullis half raised, guard dogs' helmets on posts.
  - Market Village: stalls of bones, fish and cheese, laundry lines between houses, a cat watching from a roof.
  - Keep Courtyard: the statue of the founder knight-dog (the mascot's pose) on the bowl fountain; training dummies with bite marks.
  - Rampart Gardens: the orchard, a trebuchet on the lawn, a windmill on a far hill.
  - Dungeon Depths: dropped torches, mine carts full of bones and ore, the forge glow visible from far away.
  - One landmark per track is visible from most of the lap: the keep (Castle Circuit), the forge glow (Dungeon Depths).

## 7. UI/HUD Visual Direction

Anchor: the logo's parchment banner (Section 3) and "readable on stream" (Section 1).

**Art view**

- **Screen-space HUD, not diegetic.** Racing information sits on screen, framed in the logo's language. Diegetic touches are limited to the world: pennants, the lap banner over the start arch, the war-horn countdown.
- **Frames:** parchment banners (Parchment `#F3E6C4`, 4 px Ink outline, curled ends, 12 px radius) for titles, the place display and menus. In-race HUD elements are smaller badge shapes: a circle for the item slot, a round-ended pill for lap and time.
- **Typography:**
  - Display face: a chunky rounded slab or storybook serif with heavy weight, for numerals, the place display, the countdown and titles (the logo's banner lettering is the model).
  - Body face: a rounded sans, medium weight, for menus, names and settings.
  - Size hierarchy at 1080p: place numeral 96 px, countdown 160 px, lap and time 36 px, name tags 22 px, body text 28 px, minimum anywhere 20 px. Text always Ink on parchment, or cream with a 3 px Ink outline over the world.
- **Icons:** flat illustrated icons with the ink outline, one silhouette each (Section 3), on a circle; no gradients, no photographic detail. Item icons use their Section 4 colors.
- **UI animation:** bouncy and quick. Banners unfurl in 0.2 s, numerals pop with a 120% overshoot, the item roulette spins and lands with a squash. Nothing slower than 0.3 s during a race.
- **Layout:** item slot top left, place display top right (largest element), lap and time top left under the item, minimap bottom right, drift meter at the kart, name tags above pennants. The center of the screen stays clear for the road.

**UX view**

- **Glance reads in a race.** The place, the item and the lap must read in under 0.5 s. The art view puts the place display as the largest element, which supports this. Risk: parchment frames with curled ends around every in-race element add visual noise at the edges of a busy 12-racer screen.
- **Stream readability.** Viewers watch a compressed, often smaller video. The 20 px minimum is the floor for the player; for the stream, the place, lap and countdown sizes above carry the read.
- **Accessibility floor:**
  - Text: minimum 20 px at 1080p, scaling with resolution; a UI scale option (80–130%).
  - Never color alone: place has the numeral and suffix, drift tiers have the 3-pip meter, racers have pennant patterns and names (Section 4).
  - Flashing: Section 2 uses a 0.15 s cream wash on GO and a 0.1 s hit flash. These stay under 3 flashes per second and get a "reduce flashing" option that replaces them with a border pulse.
  - Input: every menu works with keyboard only and gamepad only (story 001 already requires controller menus); focus is the gold ring with a thicker outline (Section 4).
- **Feedback:** every event the player must understand gets a visual and a sound: item received (roulette lands with a chime), hit taken (dizzy stars plus a HUD shake on the item slot), lap (banner pop), position change (the numeral bounces).

**Conflicts between the two views**

- **Ornate frames vs glance reads:** the art view frames HUD elements in parchment badges; the UX view warns that decorated frames compete with the racing read at the screen edges. Decision: **parchment in menus, lean HUD in a race** — full parchment banners for menus, the lobby, results and the place display; other in-race elements are plain badges (circle or pill, ink outline, no curled ends) (user, 2026-11-20).
- **Comic flashes vs photosensitivity:** Section 2's flashes are part of the comic feel; the UX floor needs them limited and switchable. Decision: **keep the flashes, capped below 3 per second, plus a "reduce flashing" option** that replaces them with a border pulse (user, 2026-11-20).

## 8. Asset Standards

Anchor: flat, bold, stream-readable (Section 1) at 60 fps with 12 racers. Project budgets (`.claude/docs/technical-preferences.md`, PC Windows, Godot 4.8 Forward+): **60 fps (16.6 ms frame), ≤ 2000 draw calls, ≤ 2 GB memory.**

**Art view**

- **File formats:** models as glTF 2.0 binary (`.glb`) from Blender or a similar tool; textures as `.png`; source files (`.blend`, layered images) kept outside the game folders.
- **Naming** (project files are snake_case): `[category]_[name]_[variant].[ext]`, e.g. `char_dog_mascot.glb`, `veh_cart_armored.glb`, `prop_market_stall_a.glb`, `tex_pattern_brick.png`, `fx_spark_tier2.png`. Categories: `char`, `veh`, `prop`, `bld` (buildings), `trk` (track pieces), `tex`, `fx`, `ui`, `icon`.
- **Texture tiers** (flat-color style, Section 6): pattern textures 256x256 tiling; one 256x256 palette swatch texture per material family (colors picked by UV, so most models share one material); hero racers 512x512 for the face, crest and tabard; UI icons 128x128 (256 for the place numerals); effects sprites 64–128 px.
- **Detail levels:** racers 3 levels (full, mid at ~20 m, silhouette at ~60 m; Section 5 says what drops first); buildings and large props 2 levels; small props 1 level, culled by distance.
- **Export philosophy:** one object per file, origin at the base center, -Z forward and +Y up (Godot's convention), real-world meters (a kart ~1.7 m wide), applied transforms, no unused materials. Colors live in the palette texture or vertex color, never as dozens of separate materials.

**Technical view**

- **Per-category budgets (proposals; the project sets no per-asset triangle budget, so these are derived from the frame budget and must be measured in story 010):**
  - Racer (dog + vehicle + pennant): ≤ 4,000 triangles at full detail, ≤ 1,500 mid, ≤ 500 silhouette. 12 racers ≈ 48k triangles at worst.
  - Building: ≤ 2,000; large prop (tower, statue, trebuchet): ≤ 1,500; small prop: ≤ 300 (instanced).
  - A whole track on screen: aim ≤ 400k triangles visible.
- **Draw calls (≤ 2000):** repeated props (wall blocks, houses, trees, crowds, banners) are drawn with instancing (MultiMesh), so each prop type costs one call, not one per copy; every racer is ≤ 4 materials; the track and its walls are merged into large chunks. Trade-off: merged chunks cut draw calls but are culled as a whole (a chunk partly on screen draws entirely), so chunks are sized ~100 m of road.
- **Materials and shaders:** one shared toon shader (2–3 light bands, Section 6) for the world and racers, color from the palette texture and vertex color; water, lava and boost pads are the only animated shaders. Few distinct materials keeps shader compiles and state changes low.
- **Textures and memory (≤ 2 GB):** desktop VRAM compression on all world textures (Godot's default import compresses for desktop); with 256–512 px textures the whole game's texture memory stays far under 100 MB, leaving the budget for the engine, audio and the scene.
- **Effects:** particle counts per kart capped (drift sparks ≤ 24 live, boost trail ≤ 32, dust ≤ 16); large semi-transparent effects (splashes, explosions, full-screen flashes) are short (≤ 0.5 s) to limit overdraw; 12 karts boosting at once must stay inside the frame budget.
- **Engine notes:** glTF is Godot's native 3D import path; the FBX importer was renamed to `EditorSceneFormatImporterFBX2GLTF` in 4.3 (`docs/engine-reference/godot/deprecated-apis.md`), another reason to export glTF. Import-time LOD generation, VRAM compression modes and MultiMesh behavior in 4.8 are not covered by the engine reference and are unverified until story 010 measures them.

**Conflict between the two views**

- **Outline method:** Section 3 wants thick ink outlines with different widths per tier (racers 4 px, props 3 px, scenery 2 px). An inverted-hull outline (a second, enlarged mesh per object) gives that control but roughly doubles the draw calls and vertices of every outlined object; a screen-space outline (one post-process pass) costs a fixed amount of GPU time, no extra draw calls, but gives less control over per-object widths. Decision: **hybrid** — inverted-hull outlines with exact widths on racers, items and pickups only (the hero tiers, Section 3); one screen-space outline pass for the world (user, 2026-11-20).

## 9. Reference Direction

Anchor: the DogworksTV badge (Section 1) outranks every reference below. Take one technique per source, never a look. Nothing is copied from any source's characters, tracks, items or logos.

- **Mario Kart 8 Deluxe** — track-edge legibility
  - Take: the road reads as a clean, low-noise plane bounded by a continuous high-contrast curb stripe. Scenery steps back in value so the racing line is obvious at speed (Section 3 track edge, Section 4 20% value step).
  - Avoid: chrome or glossy realistic kart materials, anti-gravity glow, its gold "?" item box (ours is a pink ribboned cube), and any mushroom or pipe motif.
- **Sonic & All-Stars Racing Transformed** — speed feedback
  - Take: boost is sold by the camera and the screen edges (FOV kick, edge streaks, a local kart glow), not by recoloring the world (Section 2 boost/drift).
  - Avoid: changing vehicle form (boat or plane modes), neon sci-fi glow, full-screen color grades, and franchise iconography.
- **Crash Team Racing Nitro-Fueled** — comic expression
  - Take: big readable faces and held poses on a hit or a win, squash-and-stretch spin-outs, and ears and tail as secondary motion (Section 5 expression and pose).
  - Avoid: its rendered fur shading (we are flat, with no fur strands), the manic wide-grin mascot face, jungle, tiki and temple motifs, and any bandicoot-like design.
- **Wolfwalkers (Cartoon Saloon, 2020)** — layered skyline
  - Take: the walled town built as stacked flat silhouette planes, each lower in contrast than the one before it, with one accent shape per plane. Use it for the keep and forge-glow vistas in open zones (Section 6 prop density and landmarks, Section 3 large simple planes).
  - Avoid: its angular, grid-like town shapes (ours are round and chamfered), visible sketchy pencil line, Celtic knotwork, and wolf or forest imagery.
- **Medieval rolls of arms (e.g. the Zürich Armorial, c. 1340)** — pennant design system
  - Take: the heraldic "rule of tincture": a metal on a colour, never a colour on a colour. Each pennant's pattern uses Parchment Cream or gold against the identity color, and the simple bold ordinaries (stripe, chevron, cross, checker) become the 12 slot patterns (Section 4 racer identity). Exception: the light slots 2 (sun yellow) and 6 (snow white) use Outline Ink for their pattern, since cream or gold would not read on them; readability (Section 1) outranks heraldic purity (user, 2026-11-20).
  - Avoid: real family arms, and lion or eagle charges (use paw and bone charges, Section 6). Also avoid aged or stained parchment realism and fine engraved hatching.
- **Mix rule:** if a new asset could be mistaken for any one source, push it back toward the badge: thicker ink, flatter color, rounder form, one dog motif.
