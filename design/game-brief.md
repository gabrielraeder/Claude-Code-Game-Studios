# Game Brief: Dogworks Racing: Kennel Kingdom

## In your words
- "I want your help defining the game which we'll develop here. either - a tower defense game, like the ones we had in warcraft 3 online, multiple lanes, where we created the pattern of the path with towers. - a mario kart like game - present more suggestions (idea is multiplayer with friends, like both above can be)"
- "I don't want a browser game, I want a real complete game to run on the pc"
- "it was a great proof of concept. Can we change the plan to do mario kart instead?"
- Picked: "Online from the start"
- "first 2, driving, drif feel, and items and chaos are both crucial"
- "its a great prototype. for initial version, the drift feels good enough."
- "So, i want your suggetions based on the name and logo I have for twicht. Dogworks TV. Dogworks racing or something similar will be the name and theme>> https://www.twitch.tv/dogworkstv https://dogworkstv.com/games/"
- Picked: Kennel Kingdom (medieval)
- "include motorcycles on the vehicle options if this is the time to do so as well, medieval designs"
- "the match can have more than 4 players? 12?"
- Picked: 2 tracks (second: Dungeon Depths), 5 items, basic sound in MVP, English only, 8 racers
- "do we have support for controller, or only keyborad?"

**Pitch:** Knight dogs race armored carts and war-bikes through a storybook castle kingdom: drift to charge boosts, hurl catapult stones at your friends, and cross the finish line in 12-racer online chaos. *(guessed)*

**Genre:** Arcade kart racer, online multiplayer.

**Controls:**
- **Keyboard:** WASD/arrows to drive, Space to drift, E for items.
- **Controller:** triggers to drive, left stick to steer, RB to drift, LB for items.
- Both work from the start.

**Question:** Does a full online race with friends on a real medieval track, with shortcuts, make the group hit rematch? *(guessed)*

**Hooks:**
- The DogworksTV knight-dog mascot as the hero racer.
- A choice of armored cart or medieval war-bike.
- 3-tier drift boosts.
- Medieval chaos items.
- Up to 12 racers.
- Built to be streamed with friends: short races, instant rematch, a HUD readable on stream. *(guessed)*

**Intent:** needs 2–12 players. You said "multiplayer with friends", "12?". Bots fill empty slots.

## Look and references
- **Look:** *(guessed)*
  - Bright storybook-medieval in 3D low-poly cartoon, with bold shapes in the DogworksTV logo's style.
  - Palette: castle-stone greys and grass greens for the world, mascot red-orange and cream white for racers, parchment cream for UI.
  - Dungeon Depths: dark stone with warm torchlight and lava glow.
  - Signature detail: every vehicle flies its racer's pennant, and the UI uses the logo's parchment banner.
- **References:** Mario Kart (drift boosts and item chaos; mechanics only, no IP); the DogworksTV logo (the mascot: red-and-white dog in a knight's helmet).
- **View:** 3D · **Camera:** chase cam behind the vehicle.

## First minute
*(guessed)*
1. The host clicks Host. Friends join by IP, and their knight dogs line up in the lobby with their pick of cart or bike.
2. A war horn sounds the countdown.
3. The first castle-gate corner: hold drift, blue sparks charge, release for a boost.
4. An item box hands you a catapult stone. You fire it, it banks off a wall, and a friend spins out.

## Challenge
*(guessed)*
- **Lap 1:** 12 racers contest from the start, and the first item volley lands around 30 s.
- **What a mistake costs:** a cauldron spill, a falcon or a missed drift costs several places.
- **Laps 2–3:** shortcuts and orange/purple drifts decide the winner. Position-weighted items keep the back of the pack in the race.

## Core loop
- Drive and drift to charge boosts.
- Grab item boxes, then attack or defend.
- Take shortcuts and fight for position over 3 laps.
- Results, then rematch.

## Goal & fail state
- **Goal:** finish first after 3 laps.
- **Fail state:** none. You place 1st–12th.
- **Session complete:** when the results screen shows everyone's place and the host can start a rematch.

## Features
- [x] **Driving:** 3-tier drift boost, rebuilt from prototype 1's tuning, with vehicle stats kept as data. Keyboard and controller supported, and the menus work from the controller too.
- [x] **Online:** host/join for up to 12 racers by IP (Tailscale-friendly), using the proven owner-authoritative model. Bots fill the empty slots, and the host picks how many.
- [ ] **5 medieval items** from item boxes, with position-weighted odds tuned for 12:
  - War Horn: boost.
  - Catapult Stone: wall-bouncing shot.
  - Cauldron Spill: slick dropped behind.
  - Falcon: homes in on the racer ahead.
  - Shield of the Realm: blocks one hit.
- [ ] **2 tracks,** each with 2 shortcuts, a road wide enough for 12 and a 12-slot grid:
  - Castle Circuit: drawbridge and secret passage.
  - Dungeon Depths: mine-cart rail and lava-gap jump. *(shortcut ideas guessed)*
  - Rich layouts and dense scenery, with elevation (hills, jumps, banking, a crossover) and moving hazards (a drawbridge on a timer, rolling barrels, gates) added in later stories. You said: "The track is a lot simple, should be way more complex", and to use Mario Kart, Sonic and other kart racers as examples.
- [ ] **Tougher bots:** better racing lines, item use and tuned rubber-banding.
- [ ] **8 knight-dog racers** (the Dogworks mascot plus 7 originals of different breeds and colors) and 2 medieval vehicle types with pennants:
  - Armored cart: steady, with wide drifts, and barely knocked by bumps.
  - War-bike: faster acceleration and tighter drifts, but knocked harder. *(handling split guessed)*
- [ ] **Race flow, HUD and basic sound:**
  - Flow: lobby with racer and vehicle pick, track choice, countdown, 3 laps, results, rematch.
  - HUD: stream-readable place display and minimap.
  - Sound: engines, drift sparks, boost, item hits, war-horn countdown, and one music loop.

## Your systems
- driving and drift feel · in the slice
- items and chaos · in the slice
- online multiplayer with friends · in the slice
- vehicle choice (cart / motorcycle) · in the slice

## Keep
-

## Avoid
- No Nintendo IP: no Mario characters, items, names or tracks.
- No browser game. It's a real PC game.

## Out of scope
- Tracks beyond 2, cups and championships · later
- Full audio (music per screen, dog voices, crowd) · later
- More vehicle types and kart parts / garage · later
- Battle mode · later
- Key rebinding menu · later
- Languages other than English · later
- Split-screen, Steam matchmaking and playing with strangers · later
- Anti-cheat and host migration · not needed among friends

## Build order
*The first version is stories 001-007, in this order. After it (the user, 2026-11-20): 008 elevation and banking, 009 moving hazards, 011 surfaces, 012 living scenery, 013 pack-racing speed, 014 air tricks, 010 graphics pass, 015 lap evolution, 016 set pieces, 017 motion and air extras, 018 weather, 019 traffic and traps, 020 time trials and variety (features from `design/references/track-features-catalog.md`).*
*(guessed)*
1. **Online core and driving together:** the net architecture from day 1, the cart's drift rebuilt on top, and vehicle stats as data. Includes a 12-player stress test with headless copies on autopilot.
2. **Castle Circuit** with shortcuts. Track character is the least proven part.
3. **Items:** the 3 proven ones first, then Falcon and Shield, with victim-confirmed hits.
4. **Tougher bots.**
5. **Racers and vehicles:** the mascot first, then the war-bike's handling, then the other 7 dogs.
6. **Dungeon Depths.**
7. **Race flow, lobby, results/rematch, stream HUD and basic sound.**

---
**Kill condition:** if after 3 sessions with friends nobody asks for a rematch on Castle Circuit. *(guessed)*

**Who it's for / what they feel:** DogworksTV and friends playing on stream. Chaotic laughs and photo-finish races. *(guessed)*

**Games you love / don't:** Mario Kart (drift boosts, item chaos); Warcraft 3 custom maps (playing online with friends).
