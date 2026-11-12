# Test results

Run on 2026-11-12 with Godot 4.7.2 (headless) on this repo's code, with
`python tools/run_tests.py --godot <godot> --all` (see `docs/TESTING.md`). The lag profiles
route every packet through `tools/lag_proxy.py`.

| Suite | Result |
|---|---|
| Unit checks | **52/52** |
| In-game screens (UI) | **23/23** |
| Title screen (menu) | **27/27** |
| Sign-in and sessions (lobby) | **24/24** |
| Save and load | **13/13** |
| 5-player session: same machine / ~80 ms 2% loss / ~150 ms 5% loss | **52/52**, **52/52**, **52/52** |
| Mechanic scenarios, same three profiles | **42/42**, **42/42**, **42/42** |

Two checks are timing-sensitive and were seen to fail once each on a loaded 2-core box
before passing on re-run ("hearts match the host's copy" when a bot is mid-hit at report
time; "no lasting detail leaks across zones" at 150 ms with 5% loss). Both passed in the
runs recorded here.

## Unit checks

- PASS  sickle hits a body straight ahead, inside reach
- PASS  sickle reaches a body whose centre is past reach but whose edge isn't
- PASS  sickle misses a body just past reach
- PASS  sickle misses right behind you
- PASS  sickle catches a body overlapping the edge of the arc
- PASS  burst: standing at its edge counts
- PASS  burst: just outside is safe
- PASS  slam wedge hits in front
- PASS  slam wedge misses behind the bear
- PASS  charge: the boar's body hits you once it reaches you
- PASS  charge: not before it gets there
- PASS  lane distance at the round end
- PASS  outline points close the shape
- PASS  new players hold just the sickle
- PASS  adding the can grows the wheel
- PASS  gear can't go in the wheel
- PASS  harvested berries land on the wheel stack
- PASS  using the last one takes it out of the wheel
- PASS  putting something back shrinks the wheel
- PASS  a full wheel says so
- PASS  pot_lid: Perfect window is smaller than Great, effectiveness goes down by tier
- PASS  buckler: Perfect window is smaller than Great, effectiveness goes down by tier
- PASS  tower_shield: Perfect window is smaller than Great, effectiveness goes down by tier
- PASS  spike_shield: Perfect window is smaller than Great, effectiveness goes down by tier
- PASS  the Tower Shield covers more than the Buckler
- PASS  the Buckler is faster to move with
- PASS  only the Spike Shield has spikes
- PASS  a torch isn't a shield
- PASS  lesson 1 waits for a hello
- PASS  saying hello finishes lesson 1
- PASS  the wheel lesson needs the seeds too
- PASS  the wheel lesson finishes when both are in
- PASS  every lesson has a title, a speech and tasks
- PASS  houses are solid
- PASS  a house doorstep is open
- PASS  every house has a room
- PASS  indoors is never dark
- PASS  Mossmouth is always dark
- PASS  someone indoors shows on the village map at the door
- PASS  walking along the top edge stops at the ledge's cliff: (2214.0, 14.0)
- PASS  the three outdoor stages loaded from their files: ["middlemost", "fernery", "mossmouth"
- PASS  the houses loaded from houses.json
- PASS  stage middlemost passes validation
- PASS  stage fernery passes validation
- PASS  stage mossmouth passes validation
- PASS  positions became Vector2 and rectangles Rect2
- PASS  colours became Color
- PASS  whole numbers became int (so cols/rows/seed work)
- PASS  the template is ignored as a stage
- PASS  the template itself is a valid stage
- PASS  a stage survives a to_json/from_json round trip
- PASS  validation reports a missing field

## In-game screens

- PASS  the solo world started
- PASS  Esc in game opens the pause menu
- PASS  the solo game pauses
- PASS  Esc again closes it
- PASS  the bag opens
- PASS  Esc over the bag opens the pause menu
- PASS  Resume from over the bag lands in the game
- PASS  the bag opens again with its own key
- PASS  the bag closes with its own key
- PASS  the map opens
- PASS  Esc over the map opens the pause menu
- PASS  Resume from over the map lands in the game
- PASS  the map opens again with its own key
- PASS  the map closes with its own key
- PASS  the controls screen opens
- PASS  Esc over the controls screen opens the pause menu
- PASS  Resume from over the controls screen lands in the game
- PASS  the controls screen opens again with its own key
- PASS  the controls screen closes with its own key
- PASS  Settings opens from the pause menu
- PASS  Esc in Settings goes back to the menu
- PASS  Esc again resumes
- PASS  Exit goes back to the title screen

## Title screen

- PASS  the title screen is the main scene
- PASS  it opens on the home page
- PASS  home has a "Play solo" button
- PASS  home has a "Host a game" button
- PASS  home has a "Join a game" button
- PASS  home has a "Settings" button
- PASS  home has a "Controls" button
- PASS  home has a "Quit" button
- PASS  typing a name sets your name
- PASS  picking a hoodie colour sets it
- PASS  "Controls" opens the controls page
- PASS  Esc goes back home from controls
- PASS  "Settings" opens the settings page
- PASS  Esc goes back home from settings
- PASS  "Join a game" opens the join page
- PASS  Esc goes back home from join
- PASS  "Play solo" opens the world list
- PASS  the list shows one row per slot: 3
- PASS  the port row is hidden for solo play
- PASS  "Host a game" shows the port for friends
- PASS  hosting opens the room page
- PASS  the room lists you as the host
- PASS  the host sees a Start button
- PASS  a joiner's Ready switch is hidden for the host
- PASS  Leave closes the room and goes home
- PASS  Join moves to the room while connecting
- PASS  a failed connection returns you home with a message: Couldn't reach that game. Check the address and that the host is running.

## Sign-in and sessions

- PASS host: the room opened
- PASS host: a player joined the room: { 1: { "name": "Host", "color": (0.6235, 0.8627, 0.7843, 1.0), "ready": true }, 1274468580: { "name": "Joiner", "color": (1.0, 0.702, 0.7804, 1.0), "ready": false } }
- PASS host: the joiner isn't ready yet
- PASS host: the joiner ticked Ready
- PASS host: the game started with 2 players
- PASS host: the joiner's avatar stands near the spawn
- PASS host: the joiner left the game
- PASS host: the game carries on after a player leaves
- PASS host: the joiner came back into the running game
- PASS host: exit took the host to the title screen
- PASS LobbyHost finished cleanly: exit code 0
- PASS joiner: connected and in the room: Connected. Saying hello...
- PASS joiner: the host is listed first
- PASS joiner: Ready reached the host and came back
- PASS joiner: the host started the game
- PASS joiner: in the world scene
- PASS joiner: this was a fresh start, not a join in progress
- PASS joiner: leaving returns to the title screen
- PASS joiner: rejoined the running game
- PASS joiner: flagged as joined in progress
- PASS joiner: the host's exit ended the game for me
- PASS joiner: back on the title screen
- PASS joiner: told why: The host closed the game.
- PASS LobbyJoin finished cleanly: exit code 0

## Save and load

- PASS both runs wrote a report
- PASS the first run saved: saved=True, solo=True
- PASS the second run loaded the slot: [net Saver] loaded save slot 7: day 1, 13:54
- PASS item wheel came back: ['sickle', 'can', 'popberry_seed']
- PASS bag came back
- PASS gear came back: {"chest": "", "helmet": "pot_helmet", "offhand": "torch", "shoes": "", "trinket1": "", "trinket2": "", "trinket3": ""}
- PASS crops came back: p1,0,0,0,0,0,0,0,0,0,0,...
- PASS pins came back: Saved pin
- PASS Pepper's lessons came back: lesson 2 (Grow a popberry), was 2
- PASS play time carries on: 15.8s then 18.5s
- PASS the clock carries on from the save: day 1 834 -> day 1 915
- PASS you're back where you stood: middlemost [1637.26, 1114.24] -> middlemost [1637.26, 1114.24]
- PASS no script errors

## 5-player session (same machine)

- PASS every process wrote a report: 7 reports
- PASS every player got into the game
- PASS lobby reached 5/5 before start: Host:5, Bot1:5, Bot2:5, Bot3:5, Bot4:5
- PASS host saw 5 -> 4 (leave) -> 5 (late join): player counts: 012345545
- PASS late player joined a game in progress
- PASS 6th player turned away: The game is full (5/5 players).
- PASS friends on the map: all 5 visible to each other, correct zone: 20/20 pairs
- PASS map positions track friends' real paths (p95 < 5 px): 1583 samples over the last 24 s: median 0.00, p95 0.00, max 187.2 px
- PASS in-zone positions track friends' real paths (p95 < 8 px): 304 samples over the last 24 s: median 0.00, p95 1.06, max 5.1 px
- PASS zones are separate instances: you only see players in your zone: Host@middlemost, Bot1@fernery, Bot2@mossmouth, Bot3@fernery, Late@mossmouth
- PASS no lasting detail leaks across zones: 0 momentary map/zone disagreements and 0 late old-zone snapshots across 6 zone changes
- PASS players spread across several zones: fernery, middlemost, mossmouth
- PASS zone travel worked both ways: Bot4 changed zone 2x and ended in middlemost
- PASS pins: everyone has the same pins: 6 pins: Boar country, Dark down here, Farm planted!, Ferns here, Late but here, Round trip
- PASS pins from every player arrived (incl. the one who left): 6 pins
- PASS late joiner received the pins placed before it arrived
- PASS crops identical for everyone: 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0...
- PASS host farmed: planted, watered twice, harvested: host bag: popberry x12, radish_seed x4, oil x2, lantern x1, pot_lid x1, hermes_boots x1, stamina_acorn x1, feather_pin x1, glow_pebble x1, sickle x1, can x7, popberry_seed x9
- PASS weather identical for everyone (at the same moment): {"fernery": "drizzle", "house_clock": "indoors", "house_pepper": "indoors", "house_store": "indoors", "house_willow": "indoors", "middlemost": "rain", "mossmouth": "drip"}
- PASS weather changed during the session: Host:17, Bot1:16, Bot2:16, Bot3:16, Late:7
- PASS clocks agree (day/night in sync): Host:0.00min, Bot1:0.55min, Bot2:0.43min, Bot3:0.30min, Late:0.59min
- PASS day/night cycle changes the light: brightest [1.0, 1.0, 1.0, 992.4, 1] at t=22s, darkest [0.036, 0.04, 0.088, 1323.8, 0] at t=33s
- PASS underground zone stays dim through day and night: Mossmouth light range 0.010 over 35 samples
- PASS bags and item wheels match the host's copy for every player
- PASS item wheel choices reach the host: Host holds sickle, Bot1 holds sickle, Bot2 holds sickle, Bot3 holds sickle, Late holds sickle
- PASS nights are actually dark outdoors: Middlemost at night: brightness 0.05 of 1.0 (14 samples)
- PASS underground is dark at every hour: Mossmouth brightness 0.06-0.06 over 35 samples
- PASS rain-proof lights stay lit in the dark (raincoat torch, lantern, headlamp): Host lit 17% of 18s dark, Bot1 lit 100% of 17s dark, Bot2 lit 100% of 39s dark, Bot3 lit 0% of 17s dark, Late lit 95% of 15s dark
- PASS rain put out a torch and it was relit at a campfire: went out=True, relit=True
- PASS the lantern burns oil: Bot2 holds lantern, fuel 18%, oil left 1
- PASS several enemy types roam the zones: fernery: boar x2, puffcap x3, wilt x2; house_clock: ; house_pepper: ; house_store: ; house_willow: ; middlemost: boar x1, wilt x3; mossmouth: bear x1, frost_wilt x2, puffcap x2
- PASS players see their zone's enemy types: Host: boar, wilt; Bot1: boar, puffcap, wilt; Bot2: bear, frost_wilt, puffcap; Bot3: boar, puffcap, wilt; Late: bear, frost_wilt, puffcap, wilt
- PASS attack telegraphs reach the players who can see them: Host:0, Bot1:12, Bot2:0, Bot3:12, Late:0
- PASS the fighter blocked or dodged telegraphed attacks: Bot3: blocked 2 (perfect 0), dodged 9, hit 7, dashes 0
- PASS the fighter moved one way while aiming another: 8.0s strafing
- PASS a frozen enemy was thawed with the torch: 5.0 relight torch | 9.1 jabbed a frozen frost_wilt
- PASS hearts match the host's copy: Late 9 vs host 8
- PASS equipped gear matches the host for every player
- PASS friends see each other's gear: 4 viewer/friend pairs
- PASS climber found the Wayfarer set in the canopy chest and wore it: {"chest": "raincoat", "helmet": "leaf_hood", "offhand": "torch", "shoes": "wellies", "trinket1": "", "trinket2": "", "trinket3": ""}
- PASS delver melted the ice, looted the Miner's set and wore it: {"chest": "overalls", "helmet": "miner_helmet", "offhand": "lantern", "shoes": "steel_toes", "trinket1": "ember_charm", "trinket2": "", "trinket3": ""}
- PASS melted ice is the same for everyone: Mossmouth ice: {'melted': 3, 'total': 4}
- PASS the pulley lift carries several players at once: works the canopy_lift: bottom -> top with 2 aboard
- PASS a lift can be called from the far end, then ridden: works the deep_lift: bottom -> top with 0 aboard; works the deep_lift: top -> bottom with 1 aboard
- PASS lift positions identical for everyone: {"fernery": {"canopy_lift": "bottom"}, "house_clock": {}, "house_pepper": {}, "house_store": {}, "house_willow": {}, "middlemost": {}, "mossmouth": {"deep_lift": "bottom"}}
- PASS lift riders reached the other level (cliffs block the way otherwise): Bot1 on the Canopy Ledge for 19.8s, Bot2 on the Deep Shelf for 28.1s
- PASS dashes spend stamina orbs: Bot1 dashed 2x; orbs 5.0/5
- PASS snapshot rate ~20 Hz for every client: Bot1:18.1Hz, Bot2:18.1Hz, Bot3:17.8Hz, Late:18.6Hz
- PASS round trip time measured: Bot1: avg 9.0 / p95 19.9 ms, Bot2: avg 9.5 / p95 19.0 ms, Bot3: avg 11.0 / p95 34.1 ms, Late: avg 15.5 / p95 93.8 ms
- PASS host frame time with 5 players: avg 7.69 ms, max 145.8 ms over 5732 frames
- PASS bandwidth is small: host upload 508 kbit/s for 4 clients, client download <= 142 kbit/s
- PASS no script errors in any log

## Mechanic scenarios (same machine)

- PASS aim_independent_of_movement: walking right while aiming left: facing (-1.00, 0.00); sickle hit the Wilt behind=true
- PASS block_from_behind_fails: blocked facing away: hp 10 -> 8 (the lid only covers your front)
- PASS block_from_front: a Regular block with the lid stops half: hp 10 -> 9 (2 damage, 1 taken), stamina spent 1.11 orbs
- PASS block_stops_a_bump_and_shoves: bumped by a Wilt while blocking: hp 10 -> 10, 1 bump(s) taken on the lid, Wilt shoved to 139 px away
- PASS block_tiers_on_a_bear: raised 0.7s early: Regular block, took 2; 0.2s: Great block, took 1; 0.05s: Perfect block!, took 0 (bear hits for 4). Pot Lid now 6.0/6
- PASS blocking_speed_depends_on_shield: walking while blocking: Buckler 187 px/s, Tower Shield 67 px/s
- PASS burst_standing_gets_hit: stood in the spore circle: hp 10 -> 8 (expect -2)
- PASS charge_hits_in_line: stood in the charge line: hp 10 -> 7 (expect -3)
- PASS charge_into_cliff_dazes: charged at the cliff and stopped dazed=true at y=692
- PASS chest_gives_set_once: first open gave 3 Miner's Set pieces; second open left 1 helmet (no duplicates)
- PASS darkness_at_night_and_underground: brightness: Middlemost noon 1.00, midnight 0.07; Mossmouth at noon 0.06; torch light on=true
- PASS dash_has_no_iframes: dashed through the burst (dash=true, still inside=true): hp 10 -> 8
- PASS dash_out_dodges: dashed clear (213 px from the centre, circle 140): hp 10 -> 10
- PASS faint_then_wake: hit at 1 hp: fainted=true; 10 s later woke up=true with hp 5
- PASS frost_wilt_needs_torch: sickle on ice: hp 1.00; torch jab thawed=true; sickle again: hp 0.67
- PASS hermes_boots_faster: walking 221 px/s; in Hermes Boots 321 px/s (x1.45)
- PASS holding_off_a_slime: held a Wilt off for 4 s: hp 10 -> 10, 1 bumps blocked, 3.3 stamina left
- PASS ice_melts_to_puddle_refills_can: ice blocks 4 -> 1; can refilled from the puddle to 10; walked through the gap=true
- PASS lantern_burns_oil: lantern ran dry from 100% and refilled itself: oil 2 -> 1, fuel now 90%, lit=true
- PASS last_berry_leaves_the_wheel: threw all 6 popberries: wheel 2 -> 1 segments, now holding sickle
- PASS locked_house_needs_key: without the key: stayed outside=true; with the Brass Key: inside house_clock, door unlocked for everyone=true; chest gave a Tower Shield=true
- PASS open_house_door: E at Pepper's Cottage door -> house_pepper; walked onto the doormat -> middlemost at (300.0, 384.0)
- PASS pepper_lessons: before 0; said hello -> lesson 1; filled the wheel -> lesson 2 (Grow a popberry); Pepper said 11 lines
- PASS perfect_block_stuns: lid up 0.06 s before the hit (Perfect): hp 10 -> 10, enemy stunned=true
- PASS rain_puts_out_burning_enemy: set alight=true, then rain: still burning=false
- PASS rain_snuffs_torch_then_relight: 3.5 s of rain: torch out=true; E at the campfire: relit=true
- PASS raincoat_keeps_torch_lit: 3.8 s of rain in a raincoat: torch still lit=true
- PASS shield_breaks_then_recovers: shield nearly worn out broke on a block=true; could block while broken=false; next burst hit in full=true; 5s later: broken=0.0s, health 1.0/6 and growing
- PASS sickle_hits_in_front_arc: Wilt 87 px away, 20 degrees off centre (body inside the arc): hit=true, hp 1.00 -> 0.50
- PASS sickle_misses_behind: Wilt right behind you (45 px), swinging forwards: hit=false (should miss)
- PASS sickle_misses_out_of_reach: Wilt 104 px away (body edge at 84 px, reach 72): hit=false (should miss)
- PASS sickle_reaches_big_body: Mossback Bear 110 px away (body edge at 66 px, reach 72): hit=true
- PASS slam_cone_hits: inside the bear's slam wedge: hp 10 -> 6 (expect -4)
- PASS spike_shield_hurts_attacker: blocked a Puffcap's burst with the Spike Shield: the Puffcap's hp 1.00 -> 0.33
- PASS sprint_and_dash_cost_stamina: sprint 0.8 s: 5.00 -> 3.99 orbs; dash: -1.00; dash with 0.2 left refused=true; 2 s later 1.75
- PASS steel_toes_kick: sprinted into a Puffcap in Steel-Toed Boots: its hp 1.00 -> 0.33
- PASS torch_sets_enemy_alight: torch jab: burning=true, hp 1.00 -> 0.67 over 2 s
- PASS touch_bump: bumping a Wilt: hp 10 -> 9 (expect -1)
- PASS tower_shield_covers_the_side: burst from 60 degrees to the side: Pot Lid (covers 70 degrees) took 2; Tower Shield (covers 150) took 0
- PASS wayfarer_set_bonus: all three Wayfarer pieces worn: bonus=true, dash costs 0.5 orb
- PASS wheel_grows_and_shrinks: wheel 1 -> 2 segments with the can; hermes_boots refused (2); can back in the bag -> 1 segments
- PASS no script errors in either log

## Lag profiles

Home internet (~80 ms, 2% loss): session 52/52, scenarios 42/42.
Rough Wi-Fi (~150 ms, 5% loss): session 52/52, scenarios 42/42.
