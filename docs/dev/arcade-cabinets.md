# §2z-arc-cab — The particular cabinets: what MAME says, what the room builds

(2026-10-26.) The list of every cabinet that is not a plain upright, one by one: what MAME 0.289 itself says its controls are, what
the real machine was, what RetroXR builds for it and how, and what is not built yet. `arcade.md` ("The cabinet takes the shape of the
game") is the mechanism; this is the catalogue. The seven games the task named (Time Traveler, Kuri Kinton, Panic Park, Silent
Scope and Silent Scope 2, Prop Cycle, Final Lap 3) come first, then every other form that is built, then the cabinets that are not.

## How to read this

Three kinds of fact, never mixed:

- **MAME** (verified): read in MAME 0.289's own driver sources (`src/mame/<file>.cpp` at the `mame0289` tag; the port names, ranges and flags below
  are verbatim), in `-listxml` (`mame0289lx.zip`), or in libretro-mame's OSD (`src/osd/modules/input/input_retro.cpp`, `assignmenthelper.cpp`).
  `Tools/arcade/mame_inputs.py` pulls the control names out of a folder of driver files, so a MAME update can be checked again.
- **Research** (a lead): web search summaries about the real cabinet. The egress proxy refused every arcade and image host (Wikipedia, Arcade Museum, Giant Bomb,
  Dragon's Lair Project, upload.wikimedia.org...: 403, and `WebFetch` resolved no host), so **no page was opened and no photograph was seen**. Each claim says how sure it is.
  Where two summaries disagreed both are given.
- **Estimate**: a number or a shape chosen here. Every dimension, travel and speed of a built cabinet is one; they are constants at the top of the file
  that uses them, so a headset can retune them.

MAME's status is its driver flag: **G** good, **I** imperfect, **NW** preliminary (does not run properly: Panic Park, Silent Scope, Top Skater...).
A cabinet is built for a game MAME cannot run yet on purpose: the cabinet follows the table, not the core.

## 1. From a game to a cabinet

```
romset -> ArcadeGameTable line  "p2c1b9w2:joy+stick;tslot panicprk=panicprkj"      (Tools/arcade/gen_game_index.py, from -listxml)
       -> ArcadeGameProfile.for_romset(...).form()                                    ("slot")
       -> ArcadeCabinetSpecs.for_game(base, profile)  -> a spec Dictionary             (players, coins, shape, what stands in front)
       -> RetroSystemModelArcadeCabinet.morph_to(spec) -> ArcadeCabinetBuilder.build_form   (built detached, moved in whole, deferred, never under a core)
       -> parts found BY NAME by ArcadeControlModule / ArcadePanelHands                (the panel shows what the core is sent and a hand can work it)
```

A profile is `p<players>c<coins>b<buttons>w<ways>:<kinds>;<attributes>`. MAME says the players, coins, buttons, ways, kinds, the rotation, the screens,
the guns and whether the game reads a service switch (`v`). **MAME says nothing of what the cabinet looked like**: the form (`t...`) is a choice made in
`gen_game_index.py` from curated lists (`CYCLE HOLO SLOT RIFLE MOUNTED_GUN GUN_PEDAL BIKE STAND_RACER ROOFED ODD`, and `FLY` and `SEATING` in `Tools/arcade/cockpits.py`), the Cabinet
DIP switch and the game's name. 28,713 romsets, 1,639 profiles. Two attributes say what the SIT-DOWN version had (section 2b): `q`, the letters `s` (a seat), `c` (a cabin round it) and `m` (a base that
moves), and `z`, a throttle lever. A third, `b`, says the game has a Timekeeper chip whose memory it checks (`h` the image it is seeded from is hand built or missing, `g` a good dump,
`n` none: `arcade-backup-memory.md`).

| form (`t`) | romsets (families) | | form (`t`) | romsets (families) |
|---|---|---|---|---|
| plain upright | 27,405 (8,283) | | `rifle` | 51 (7) |
| `race` | 355 (104) | | `gunm` | 57 (16) |
| `gun` | 305 (134) | | `pump` | 22 (14) |
| `stand` | 123 (34) | | `cycle`, `holo`, `slot` | 2 (1) each |
| `music` (not built) | 158 (82) | | `odd` (not built) | 73 (38) |
| `bike` | 64 (19) | | `dance` | 53 (31) |
| `fly` | 41 (17) | | | |

And across every form: **3,290 romsets stand the monitor on its side** (`r90`/`r270`: the taller `tate` body), 170 turn it over (`r180`, nothing changes), 356 drive
more than one screen, 3 to 8 players are 1,345, **2,959 are alternating** (`a`: one panel, two turns) and 14,977 read a service switch (`v`).

## 2. The seven named games

### Time Traveler `timetrv` (Virtual Image Productions, Sega licence, 1991) — form `holo`

- **MAME**: `sega/timetrv.cpp`, **G** (a laserdisc game: its disc image is a CHD beside the zip, "Games with a disc" in `arcade.md`). Controls: `IN0` joystick up/down/left/right,
  START1, START2, COIN1, BILL1; `IN1` BUTTON1 "Attack", BUTTON2 "Reversal Cube", SERVICE. The DIPs "Max Reversal Cubes" and "Reversal Cube Cost" are the cube's rules.
  The display is rotated 180 with a flip (the video comes out turned over).
- **The real cabinet** (research, medium on the mirror, low on the size): an upright with the CRT low in the base facing up, its picture thrown onto a curved mirror, so
  the actors seem to float in front of a black stage, with a few real props on a small black platform in front of the image. The "hologram" is a mirror illusion. One source
  gives about 127 x 109 x 114 cm.
- **Built**: the upright, one stick, two buttons, one coin door (the table's `p1c1b2w8:joy;r180;tholo;v`), and the picture moved `HOLO_DEPTH` (30 cm) **behind the
  glass at the far end of a black tunnel** cut to the window (`HoloSideL/R`, `HoloRoof`, `HoloFloor`), with a low plinth (`HoloPlinth`) in front of it for the props. The
  picture is the tube's size still, so it floats smaller and deeper, and a head that moves sees it move against the frame, which a flat glass never shows.
  `ArcadeCabinetBuilder._build_monitor` (`back`) and `_build_holo_stage`; the spec key is `holo` (`{"depth": HOLO_DEPTH}`).
- **Estimates**: the depth, the plinth, the tunnel. The mirror is not modelled: the picture is drawn where the image appeared.
- Tests: `arcade_form_tests odd/`; picture: `arcade_cabinet_probe --forms=timetrv` (windowed).

### Kuri Kinton `kurikint` (Taito, 1988; Taito L system) — an alternating upright (no form of its own)

- **MAME**: `taito/taito_l.cpp`, **G**. Controls: `IN0`/`IN1` `TAITO_JOY_UDLR_2_BUTTONS` for player 1 and 2 (an 8-way joystick and two buttons each), TILT; the DIP
  "Cabinet" (SW1:1) is Upright or Cocktail. Nothing about it is odd. It is on the list as the test of the **alternating** rule.
- **Built**: ONE panel in the middle labelled 1P, and a momentary START labelled 2P beside it, which is player 2's START (MAME reads player 1's controls for both turns on an upright),
  one coin door. The rule is the table's `a`: the Cabinet DIP offers a cocktail and the factory setting is an upright with a single set of controls (or an `Upright Controls`
  DIP says Single). **It is a heuristic, not a fact MAME states**: it holds for Pac-Man, Galaga, Donkey Kong, 1942, Rastan, Ghosts'n Goblins and Kuri Kinton and is not set
  for Bubble Bobble, Contra, 1943 or Mario Bros. (two panels). 2,959 romsets carry it.
- Tests: `arcade_form_tests specs/` ("Kuri Kinton (alternating) has one panel, 1P, and a START 2P beside it").

### Panic Park `panicprk` (Namco, 1997; System 23) — form `slot`

- **MAME**: `namco/namcos23.cpp`, **NW** (does not run in 0.289). Controls: `JVS_ANALOG_INPUT1` `IPT_AD_STICK_X` 0..0xffff, centre 0x8000, **`PORT_CENTERDELTA(0)`**
  (lever 1), `JVS_ANALOG_INPUT2` the same for `PORT_PLAYER(2)` (lever 2); `JVS_PLAYER1`: START1, START2, and the operator's "Up Select", "Down Select", BUTTON1 "Enter".
  The `-listxml` also files a `joy` `vertical2` and a nine-button `joy` for player 2: that is the operator bits and nothing a player works. A lever in a slot is a POSITION, not a
  rate, and `CENTERDELTA(0)` says the same of a key-driven one: it stays where it was left.
- **The real cabinet** (research, medium; two summaries agree): two sideways-sliding levers, red for player 1 and blue for player 2, **in ONE slot across the front**.
  They collide when they meet (the game says "Push One Another!"); a one-player game parks the other lever at its end. A 33 or 50 inch screen (System 23). Each lever
  ends in a big flat handle (the "two big buttons" of the reports: the handles themselves, with a big START ABOVE each, toward the screen; no photograph could be opened from
  the build machine, so the handle's size and shape and where START stands are an estimate: START was under the lever until a player saw it hang off the deck's front edge).
- **Built**: the tall body (the 33 inch class is the smaller of the two screens the cabinet had; the table's `m33`, `MONITOR_CLASS` in `gen_game_index.py`, so the glass is
  the tall one and the body is wider than the upright's, `ArcadeCabinetSpecs.class_shape`) with two panels, each a **`SlidePivot` carriage on a shared `SlotRail`** with a short
  shaft and a **flat dome 9 cm across** (`LeverBall`, `SLOT_HANDLE_Z` above the carriage: the point a hand takes) and a **big round START** in the player's colour, red and blue
  (`_player_color`), the slot travel `SLOT_TRAVEL` 14 cm either side of where each rests (player 1 in the left half, player 2 in the right: both reach the middle, neither
  passes it). The lever's position is the player's left stick X (an analog position, as `CENTERDELTA(0)` asks); each panel is its own player (own port, own START cap).
  A one-player game gets one lever. The spec's panels are `{"kind": "slot", "slot_x", "start_x"}`; `panel_extent` counts the whole travel AND the handle's reach past it
  (`SLOT_HANDLE_REACH`, 5 cm: the dome is 4.5 cm in radius, and at the end of the slot it stood outside the walls) so a wider travel widens the body.
  **The deck is 7 cm deeper than an upright's** (the spec's `deck_extra`, `SLOT_DECK_EXTRA`; `ArcadeCabinetSpecs.deepened`: the apron and the deck's front edge move out together, the glass
  and the body behind them do not, the apron's boxes hang on the shape's `apron_z`, and the overhang is a solid box): the rail runs at `SLOT_LEVER_Y`, a hand's breadth from the deck's front
  edge, and each START stands above its lever's resting place at `SLOT_START_Y`, clear of the dome (`arcade_form_tests odd/` measures every one: the handles inside the walls at the ends
  of the slot, START above and on the deck, the rail under the whole travel).
- **VR hands**: the trigger on a lever's ball takes hold of it (`SLIDE_REACH` 5.5 cm) and it slides with the hand, 14 cm being all the way (`SlideGrab`).
- **Not built**: the levers do not push each other; two hands can put both through the middle (the game reads two numbers).
- Tests: `arcade_form_tests odd/`, `arcade_hand_tests slot/`; picture `--forms=panicprk`.

### Silent Scope `sscope` and Silent Scope 2 `sscope2` (Konami, 1999 and 2000; `hornet.cpp`) — form `rifle`

- **MAME**: `konami/hornet.cpp`, both **NW**. Controls: `ANALOG1` "Gun Yaw" `IPT_AD_STICK_X` 0..0x7ff centre 0x400 `CENTERDELTA(0)`, `ANALOG2` "Gun Pitch"
  `IPT_AD_STICK_Y` 0..0x7ff `PORT_INVERT` `CENTERDELTA(0)`, BUTTON1 "Gun Trigger", a service switch. **The rifle is two analog axes and a trigger, not a light gun.**
  Two displays: `lscreen` 512 x 384 and `rscreen` 768 x 236 (the main picture and the scope's). The Golgo 13 rifles in the same family (`golgo13`, `g13knd`, `g13jnr`) have a
  second button, "Sensor" / "Scope Sensor" (an eyepiece switch), which Silent Scope does not.
- **The real cabinet** (research, medium on the rifle, low on the scope): the player stands; a plastic sniper rifle is bolted to the cabinet on a pivot (an analog mount under
  it); the scope shows a close-up on a small LCD (sources disagree on whether it is a magnified part of the main screen). A tall cabinet; one seller lists Silent Scope 2 at
  208 x 81 x 165 cm.
- **Built**: the wide body, ONE rifle on a taller post in the middle of the deck (`Scenes/Objects/peripherals/arcade_light_rifle.tscn`), **fixed to the post and turning about
  its pivot** (40 degrees either way, 12 down to 28 up, never rolled; a hand turns it by where the hand IS: the barrel runs from the hand through the pivot): `arcade.md` "Guns on
  a swivel". START alone on the deck, the trigger is the rifle's.
- **The scope** (2026-10-26): `lscreen` (screen 0, the monitor) and `rscreen` (screen 1, `// for scope`, 15 kHz) are the pair in every Silent Scope's configuration, and the layout is `dualhsxs`: one
  8.03 x 3 frame, the monitor left, the scope right. The wide body's tube shows the left half alone and the rifle's eyepiece carries a small screen (`ScopeScreen`) showing the right half
  (`arcade.md` "Several screens"). Table attributes `l1` (the lens) and `c0,0,4,3/4.03,0,4,3`.
- **The eyepiece is a cup, 10 cm across at the eye, with a 7.4 x 5.5 cm screen in it** (2026-10-26; it was a 4.6 cm eyepiece with a 3.7 x 2.8 cm screen, too small to read a picture in, and a
  player asked for it bigger): `gen_arcade_gun.gd --variant=rifle`, `SCOPE_SCREEN` and `SCOPE_CUP_RADIUS`; the picture's diagonal is inside the cup (`arcade_form_tests screens/`).
- **A rifle game of ONE screen has a DIGITAL scope** (`golgo13`, `g13knd`, `g13jnr`, `sscopex`, `sogeki`, `sscopexu`, `sscopefh`: MAME gives them one display and no lens, which left the eyepiece dead):
  the monitor shows the whole picture and the lens the part of it the rifle points at, **2.5 times** (`ArcadeCabinetSpecs.SCOPE_ZOOM`, the spec's `screen.scope.zoom`,
  `ArcadeScreenModule.scope_zoom`), following the gun's own aim (`LightGun.last_aim`, the point on the picture the barrel meets) and kept inside the picture. It shows only a frame of the game running:
  dark while the game is only on show (attract) and while another machine's picture is on the glass. `arcade_form_tests scope/`; `--forms=golgo13` takes the eyepiece from the player's eye
  (`formscope_`). It is an approximation: no source says what the real scope showed (sources disagree on whether it is a magnified part of the main screen at all).
- **Not built**: the Golgo 13 eyepiece sensor, a scope that follows the eye (the lens is always on). Nothing here has been seen to run: Silent Scope is NW in MAME 0.289.
- Tests: `arcade_form_tests mount/ screens/ scope/`.

### Prop Cycle `propcycl` (Namco, 1996; System 22) — form `cycle`

- **MAME**: `namco/namcos22.cpp`, **I**. Controls: `ADC.0` `IPT_AD_STICK_X` 0x0bf..0x33f centre 0x1ff `PORT_REVERSE`; `ADC.1` `IPT_AD_STICK_Y` the same range; `OPT.0`
  `IPT_AD_STICK_Z` named **"Cycle Pedal"**, 0x01..0xff centre 0x80, `KEYDELTA(10)`; `INPUTS` COIN1, SERVICE1, SERVICE, START1. No buttons.
- **The real cabinet** (research, medium on the controls, low on the size): the player sits on a replica bicycle (saddle, pedals, grips) in front of the screen; pedalling gives
  lift, the grips steer and tilt the craft up and down (one summary adds a sideways lean). Whether the cabinet is an upright or a deluxe one is not agreed.
- **Built**: the WIDE body (a 0.90 m flat glass and its own 40 inch tube, as a rider's head is above the saddle) and in front of it, clear of the bay door's swing, **a
  bicycle on a stand** (`_build_cycle`): `CycleStand`, `SeatTube`, `TopTube`, `DownTube`, `ChainStay`, `SeatStay`, `Fork`, `RearPost`, `Saddle`, `Stem`, and the two controls:
  - **`BarsPivot`** (`BarCross`, `BarGripL/R`, `BrakeLeverL/R`, START on `BarPanel`): the left stick. X steers (`BARS_YAW_DEG` 28 degrees about the stem, right is clockwise
    seen from above); Y tips the grips (`BARS_PITCH_DEG` 12 degrees: pushed forward over the stem, pulled back toward the rider).
  - **`CrankPivot`** (`CrankAxle`, `Chainring`, `CrankArmL/R`, `CrankPedalL/R`): the **right stick's Y**, pushed up is forward, and the deflection is the pedalling SPEED
    (`CRANK_SPEED` 1.5 turns a second at full), because MAME's `AD_STICK_Z` reads speed about its centre. libretro-mame binds `IPT_AD_STICK_Z` to the right stick's Y
    (`input_retro.cpp`: "bonus AD stick Z").
  The rider's hands are one controller (a `PanelGrip` at the stem) as a panel is. No collision: a player steps up to it. One coin door.
  **The saddle is a seat** (2026-10-26; it was drawn and nothing could be sat on): `RiderSeat`, a `CockpitSeat` (`_build_rider_seat`), the cushion to press on the saddle's top, the eyes 0.72 m
  above it, getting up onto the floor beside the stand, the rider's own floor taken to be at the pedals' height (a headset adds its person's height to it: a person on a real chair has
  their eyes about where a cyclist's are). `seat_tests rider/`.
- **VR hands**: the trigger on a grip takes hold of the bars (`BARS_REACH` 7 cm): sideways 15 cm is a full turn, forward or back 10 cm a full tip (`BarsGrab`, two axes,
  its own let-go distance); the trigger at a pedal takes hold of the crank (`CRANK_REACH` 6 cm) and turning it with the hand pedals, at the speed the hand turns it
  (`CrankGrab`: an angle about the axle, no angle on the axle itself).
- **Estimates**: every dimension; **which way "pull" is for the Y axis** (the game's own sense of up and down is not in MAME's port definition); that the pedal speed
  is read about the centre as a signed value. Nobody has run the game (it needs a core and a ROM).
- Tests: `arcade_form_tests odd/` and `reach/` (a box over the bars once hid their grip from a laser: caught there), `arcade_hand_tests cycle/`; picture `--forms=propcycl`.

### Final Lap 3 `finalap3` (Namco, 1992; System 2) — form `race`

- **MAME**: `namco/namcos2.cpp`, **I**. Controls (one player): `AN5` "Steering Wheel" `IPT_PADDLE` 0x01..0xff centre 0x80, `AN6` "Brake Pedal" `IPT_PEDAL2` 0..0x40, `AN7`
  "Accelerator Pedal" `IPT_PEDAL` 0..0x80, `MCUH` BUTTON1 "Shift Gear" **`PORT_TOGGLE`**, COIN1, COIN2, SERVICE.
- **The real cabinet** (research, medium on the controls and the linking, low on the form): a sit-down twin (two seats and two 25 inch screens, plywood and diamond plate);
  four units chain for eight racers. MAME runs ONE unit and reads ONE driver; the Arcade Museum's spec table says upright, StrategyWiki sit-down.
- **Built**: the sit-down cockpit (`race`): the `racer` body, a platform, **a real seat** (`CockpitSeat`: press the cushion to sit, the eyes at the middle of the glass), a dash with the
  wheel (the left stick, to `WHEEL_LOCK_DEG`), two organ pedals on one axle (gas R2, brake L2) and a gear lever by the right hand (the game's own button, and only for a game that has one: see below), START on the dash. The twin
  is not built: nothing in MAME has a second driver.
- **The gear lever is the game's own** (2026-10-26; before it was "button 1, held", which fits few games). `Tools/arcade/shifters.py` reads it out of the drivers'
  `INPUT_PORTS_START` blocks (`-listxml` carries neither the button's name nor `PORT_TOGGLE`) and writes `Tools/arcade/shifters.json`, which `gen_game_index.py` turns into the
  table's `x` attribute for the `race` and `stand` forms: of the 157 driving parents, **69 name a gear change: 34 on ONE button (31 `PORT_TOGGLE`, the game flips low/high
  on each PRESS, and 3 held), 20 a sequential box (a "Shift Up" and a "Shift Down" button), 15 an H pattern** ("Gear 1".."Gear 4", four or five buttons: a lever of two positions cannot say
  which, so none is built); the other 88 have none. The lever is drawn for the `race` and `stand` forms among them (a bike has none). The button is MAME's own number: **button 1 is Final Lap 1, 2 and 3, Rad Mobile, Slipstream; button 2 Cisco Heat, Spy Hunter, Racin' Force;
  button 3 Out Run, Turbo Out Run, Power Drift, WEC Le Mans, Hot Chase, Continental Circus; button 4 Chase HQ, Top Speed, Super Chase**; Pole Position's gear change is button 3 HELD (a
  switch, not a toggle). Button n is the pad's B A Y X L R in order (`ArcadeProfiles.button_bit`). What the cabinet does with it (`ArcadeGameProfile.shifter()`):
  - a **toggle** gets ONE tap (0.12 s) of its button for every change of gear, the lever's hand sending it (`LeverGrab`: high past 60% of the throw, low under 40%, so a wobble
    about the middle shifts nothing; two changes in a hurry are two queued taps, never one long press) and the lever DRAWN where the presses left it (`ArcadeControlModule._step_shift`:
    it flips on the button's rising edge, whoever pressed it: a pad, a finger, the lever). The game's own gear is not known to the cabinet: a game that changes gear by itself, or
    a core reset, leaves the lever where the presses were (a new run puts it back low: `reset_shift`);
  - a **held** shifter's button is down for as long as the lever is high, and the lever stays high when let go;
  - a **sequential box** taps `up` going high and `down` going low, and the drawn lever goes high on an `up` press and low on a `down`;
  - **no lever is drawn for a game with none** (an H pattern, an automatic, a game the sources say nothing of): it was drawn for every driving game with a button, and pressed one
    that could be a "view" or a horn. A pad's player was never touched by any of this: they press the button the game names.
  Not run against a core. Whether a toggle game wants a tap this long (0.12 s) on every core, and the tap queue's rest (0.10 s), is an estimate; the number of presses is exact.
- Tests: `arcade_form_tests build/`, `reach/` (Daytona); the seat in `seat_tests`.

## 2b. The sit-down cabinets: a seat, a cabin round it, a base that moves

(2026-10-26.) After Burner II was drawn as an upright with a stick on its panel, and so were G-LOC, Galaxy Force II and Space Harrier; The Lost World had its two guns on a deck with nowhere to sit.
Their cabinets were the opposite: **you sat in them**, strapped into a seat in a closed cockpit that tilted with the stick. MAME says so in its own words, one DIP switch at a time:
After Burner's `Cabinet Type` offers "Moving Deluxe" and "Moving Standard", G-LOC's "Moving" and "Cockpit", Space Harrier's and Rail Chase's "Moving", Galaxy Force II's "Deluxe" and
"Super Deluxe", Out Run's "Moving" and "Up Cockpit", Line of Fire's "Cockpit" (`Tools/arcade/cockpits.py --report` lists them against the curated list). **The factory setting of every one of them is
"Upright", so the DIP's default says nothing; its CHOICES say a sit-down cabinet existed**, and a game MAME's DIPs are silent on (The Lost World's jeep seat, Solar Assault's pod) is in the same list from
the research. Both go in `SEATING` (`cockpits.py`, one line per game with where it comes from), and the table carries them as `q`: `s` a seat, `c` a cabin, `m` a moving base.

| game (romset) | form | seat / cabin / moving | throttle | where it comes from |
|---|---|---|---|---|
| After Burner `aburner`, After Burner II `aburner2` | `fly` | s c m | II only (DIP "Throttle Lever") | DIP "Moving Deluxe / Moving Standard"; an enclosed cockpit with a seat belt, hydraulic: three sources |
| Space Harrier `sharrier` | `fly` | s . m | no | DIP "Moving": an open sit-down seat on a moving base |
| G-LOC `gloc` (R-360 `glocr360`, its clone, a gyroscope cage), Strike Fighter `strkfgtr` | `fly` | s c m | `gloc`, `strkfgtr` (the R-360 has no Z of its own) | DIP "Moving", "Cockpit" |
| Galaxy Force II `gforce2` | `fly` | s c m | yes | DIP "Super Deluxe / Deluxe": cabinet, seat and screen move together |
| Thunder Blade `thndrbld` | `fly` | s . m | yes | DIP "Deluxe" (`thndrbld1`): a helicopter chair that follows the stick, no cabin |
| Sega Strike Fighter `sstrkfgt`, Sky Target `skytargt`, Thunder Ceptor `tceptor` | `fly` | s . . | no (Strike Fighter's Z is "Rudder Pedal") | research: a seat; the deluxe ones non-motion |
| Night Striker `nightstr`, Top Landing `topland`, Air Combat `aircomb`, Air Combat 22 `airco22b` | `fly` | s c . | the two Air Combats | DIP "Cockpit" / "Deluxe"; the Air Combat cabinet is a full-size cockpit with a rumbling seat |
| Midnight Landing `mlanding`, Air Inferno `ainferno`, Solar Assault `slrasslt` | `fly` | s c m | no | DIP "Deluxe" / "DX Moving Only"; Solar Assault the SpeedKing pod (pneumatic, one source) |
| Out Run `outrun`, Turbo Out Run `toutrun`, Power Drift `pdrift`, Super Monaco GP `smgp` | `race` | s . m | | DIP "Moving", "Cockpit" (Out Run's default "Mini Up" had filed it `stand`) |
| Emergency Call Ambulance `eca` | `race` | | | a sit-down cabinet: a wheel and pedals (it was `odd`) |
| Rail Chase `rchase`, Rail Chase 2 `rchase2`, Jurassic Park `jpark` | `gun`, `gunm` | s . m | | DIP "Moving" (Rail Chase), research: a bench that pitches and sways |
| The Lost World `lostwsga`, Line of Fire `loffire` | `gunm` | s . . | | a seat styled on the film's jeep (research); DIP "Cockpit": two seats a gun |

- **MAME's controls** (verbatim, `segaxbd.cpp`): After Burner is `ADC0` `IPT_AD_STICK_X` 0x20..0xe0 `KEYDELTA(4)`, `ADC1` `IPT_AD_STICK_Y` 0x40..0xc0 `PORT_REVERSE`, `ADC2` `IPT_AD_STICK_Z` (the throttle, centre 0x80,
  `KEYDELTA(79)`: a key moves it fast), BUTTON1 "Vulcan", BUTTON2 "Missile"; G-LOC adds BUTTON3 "After Burner". Two more ports, `ADC3` "motor Y" and `ADC4` "motor X", are `IPT_CUSTOM` constants:
  the board reads the position of the moving base's motors, and MAME hands it a base that is always centred. **Nothing of the motion is sent out through libretro**, so the cabinet cannot be fed the
  game's own motion; it moves with the stick, which is what a motion base did.
- **Built**, a flight cockpit (`fly`): the driving cockpit's `racer` body, platform, dash, START and **real seat** (`CockpitSeat`, eyes at the middle of the glass), and in place of the wheel a **stick between the
  knees** on a console (`StickPivot` in a frame standing up, 30 cm of shaft, a grip in the player's colour with the first two buttons on its head: `StickGrab` scales its throw with the shaft, so the grip follows
  the hand), a **throttle lever by the left hand** (`ThrottlePivot`, its knob `ThrottleKnob` with the next two buttons on it) for a game that reads one, the last two buttons on the dash beside START. A game with no throttle has
  its third and fourth buttons on the stick's head. The stick is the left stick as any panel's is; **the throttle is the right stick's Y** (forward up, the lever's top away from the player), as the bicycle's crank is.
  *That libretro-mame sends `AD_STICK_Z` through the right stick's Y is not verified against a core* (it is the crank's assumption too). A hand takes the lever at its knob (`ThrottleGrab`, 10 cm of travel
  for all of it) and **it stays where the hand left it**, as a throttle does (a pad's right stick pushed further than the lever wins while it is, the larger always winning, as for any control a hand and a pad
  both work); a machine switched off, or a run that ends (`ArcadeControlModule.rest`), puts it back in the middle.
- **The cabin** (`cabin`): a panel each side whose front edge slants up from the sill beside the dash to the roof's front corner, as a canopy's does (it is the monitor glass's own line carried on, up to the roof and
  down to the platform), a roof that runs forward over the monitor housing's marquee, and five red lock-on lamps hung just ahead of the marquee's face (`CABIN_LAMP_Z`: a seated player sees them above the picture, which a
  lamp behind the marquee would not give); open behind where you get in. **The shape is an estimate**: the research has words for these cabinets (an enclosed cockpit, a seat belt,
  "enclosed on almost all sides"), no photograph.
- **The moving base** (`motion`): the platform, the dash, the seat, the controls and the cabin are on one node (`MotionPivot`) that `ArcadeControlModule.tick` tilts about the platform's centre: **banked into the turn 4 degrees at
  full stick, nosed up 3 degrees at full pull** (gas and brake nose a driving cockpit the same way), eased at 4 a second, settled level when the run ends. A few degrees on purpose: the real one was said to swing about 25 (one source),
  but a head carried on a tilting seat is a head being rocked. **The player is carried with the seat**: `CockpitSeat` calls `SeatSitting.follow`, which moves the origin by the eye point's move (position only, and the body under it:
  the heading is the player's). **Options > Cabinet Motion** (`AppPrefs.arcade_motion`): automatic is on at a desk and off in a headset, or always, or never. A headset and a Quest on a moving seat are OWED.
- **The bench** (`bench`): a gun ride's platform in front of the guns, which stay on the deck, with a seat a gun (two at most, 40 cm wide each, the eyes capped at 1.20 m so a seat at a 1.33 m glass is not a stool), each player getting up
  on the outside of their own seat. **The bench does not move**: nothing says how the ride moved (the libretro API carries no output of the game's), and a seat that rocked to no purpose under a headset is harm for nothing.
- **Not built**: the R-360's rotation (a cage that turns right over); rudder pedals (Sega Strike Fighter's `AD_STICK_Z` is one, Thunder Ceptor's accelerator pad is a `PEDAL`); Sega Strike Fighter's three screens;
  Air Rescue's twin; Lucky & Wild (a wheel and two guns: a driving cockpit with guns); The Ocean Hunter's bench (unverified); a bench that moves; the real motion of any of them.
- Tests: `arcade_form_tests seating/` (the table's flags for 34 games, the cabin, the controls, the tilt's direction and size, the bench), `arcade_hand_tests fly/`, `seat_tests follow/`, `arcade_variants_tests` (the setting is saved);
  pictures `arcade_cabinet_probe --forms=aburner2,sharrier,nightstr,outrun,lostwsga` (`form_`, `formside_`, `formseat_`, `formlap_`, `formtilt_`).

## 3. Every form that is built

What each one is made of, so a new one can follow it. "Hands" is what a headset's hands do on it (`arcade.md` "Hands on the panel").

| form | games | what stands there | how it is built | hands |
|---|---|---|---|---|
| **panels by player** (any) | every game | a panel per player, the control the game has and exactly its buttons | `layout_panels`, `panel_kind` (`stick twin ball dial buttons wheel`), `button_grid`; three to six players make the BODY wider (`body_width`), a door and a socket under each panel | a fingertip presses a cap; the trigger takes a stick, a dial, a trackball |
| **tate** | 3,290 romsets | the monitor on its side | its own body (`tate`: the glass 0.65 m up the slant, 1.92 m tall) and a 0.36 x 0.48 m tube; every window is cut to its tube | |
| **alternating** | 2,959 | one panel, 1P, and a 2P START | the table's `a`; one coin door | |
| **screens** | 356 | several screens side by side | the tube row; the frame holds them as one picture | |
| **service** | 14,977 | TEST and SERVICE in the compartment opposite the power switch | `ArcadeServiceModule`, only where MAME says `<input service="yes">` | VRButtons |
| `gun` | 305 (134) | guns in holsters, a pedal where the game had one (Time Crisis), a bench where it was a ride (Rail Chase) | the wide body, one gun for each light gun the game has (up to 3), START alone each | the hand takes the gun as any pickable |
| `gunm` | 57 (16) | a gun on a post, a bench where it was a ride (The Lost World) | Operation Wolf's Uzi, Terminator 2, Beast Busters (3): fixed to the post, turning about its pivot | the hand turns it |
| `rifle` | 51 (7) | one rifle on a taller post | Silent Scope, Golgo 13; see above | the hand turns it |
| `race` | 355 (104) | a sit-down cockpit | the `racer` body, platform, seat, dash, wheel, two pedals, gear lever; a roof for the Model 3 twins (`ROOFED`); a moving base for Out Run, Power Drift (`q`) | wheel (clockwise is right), pedals under a finger, the lever |
| `fly` | 41 (17) | a sit-down flight cockpit | the `race` cockpit with a stick and a throttle for the wheel, a cabin where the game's had one, a moving base; see 2b | the grip leans with the hand, the throttle lever stays where it is left |
| `stand` | 123 (34) | a stand-up driving cabinet | the wheel on the panel, a lever beside it, the pedals on the floor in front (Pole Position, Out Run, Final Lap) | the same |
| `bike` | 64 (19) | a ride-on motorbike | a bike on a stand in front of the `racer` body; it LEANS (`LeanPivot`) | the bars: sideways 15 cm is a full lean |
| `cycle` | 2 (1) | a bicycle | see Prop Cycle | bars (two axes), crank |
| `holo` | 2 (1) | a deep stage behind the glass | see Time Traveler | |
| `slot` | 2 (1) | two levers in one slot | see Panic Park | the lever slides |
| `dance` | 53 (31) | a stage of four arrows a dancer | a square of nine 30 cm panels, a safety bar; the arrows sink with the directions | a foot is not tracked: a finger can press an arrow |
| `pump` | 22 (14) | a stage of five panels | Pump It Up's diagonals, the buttons' own | the same |

## 4. What a MAME control becomes

**The census** (MAME 0.289 `-listxml`, machines that take a coin; "playable" is a parent with driver status good or imperfect):

| MAME `control type` | parents | playable | RetroXR `kind` | what the panel draws | what the core is sent |
|---|---|---|---|---|---|
| `joy` (8, 4, 2 way) | 3,529 | 2,797 | `joy` | stick and caps | D-pad bits (and the left stick's axis through "left+dpad") |
| `only_buttons` | 1,568 | 325 | `btn` | caps | the face buttons |
| `gambling` | 1,461 | 890 | `other` | *a plain panel (not built)* | |
| `mahjong` | 885 | 297 | `other` | *not built* | |
| `keypad` | 874 | 44 | `other` | *not built* | |
| `hanafuda` | 510 | 23 | `other` | *not built* | |
| `stick` (analog) | 247 | 186 | `stick` | a stick; on a post a gun or a rifle | left stick X/Y (`AD_STICK_X/Y`); the third axis `AD_STICK_Z` the right stick's Y |
| `paddle` | 209 | 151 | `paddle` | a wheel (with pedals) or a dial | left stick X (`PADDLE`), a driving game's `PADDLE_V` left stick Y |
| `lightgun` | 208 | 141 | `gun` (`touch` for the touch-screen drivers) | guns | the libretro light gun device |
| `dial` (spinner) | 200 | 176 | `dial` | a knob (`DialPivot`) | left stick X as a SPEED |
| `pedal` | 187 | 124 | `pedal` | pedals | R2 (`PEDAL`), L2 (`PEDAL2`); the face buttons B and A also add |
| `trackball` | 147 | 133 | `ball` | a ball (`BallPivot`) | left stick X/Y as a speed |
| `doublejoy` | 64 | 59 | `twin` | two sticks | the left and right stick |
| `positional` | 35 | 33 | `dial` | a knob | left stick X |
| `keyboard` | 21 | 1 | `other` | *not built* | |
| `mouse` | 8 | 3 | `ball` | a ball | left stick as a speed |

**How libretro-mame reads them** (verified in its OSD, `input_retro.cpp` `configure` and MAME's `assignmenthelper.cpp`): a RetroPad's left stick X is the joystick's X axis and is
bound to `IPT_PADDLE`, `IPT_POSITIONAL`, `IPT_DIAL`, `IPT_TRACKBALL_X`, `IPT_AD_STICK_X` and `IPT_LIGHTGUN_X`; its Y to `PADDLE_V`, `POSITIONAL_V`, `DIAL_V`, `TRACKBALL_Y`,
`AD_STICK_Y` and `LIGHTGUN_Y`; the D-pad to the same types' decrement and increment (a key's way of moving them); **the right stick's Y is `AD_STICK_Z`** ("bonus AD stick Z");
R2 and L2 are `PEDAL` and `PEDAL2` (analog, "negative" modifier) and the B and A buttons add to them. **So two axes of one type for one player share one stick axis**: Wave Runner's
"Handle Bar" and "Roll" are both `AD_STICK_X`, Alpine Racer's "Steps Swing" and "Steps Edge" are `AD_STICK_X` of player 1 and of player 2 (two ports for one player). MAME's own analog types
behave as `analog_field` says (`ioport.cpp`): sticks and paddles are absolute and re-centre, **pedals sit at the bottom of their range**, light guns are absolute, dials, trackballs and mice are
relative and wrap, positional controls are absolute and may wrap. `CENTERDELTA(0)` (Silent Scope, Panic Park, Space Gun) keeps a key-driven axis where it was left.

What the cabinet sends for each of its parts is `arcade.md` "Input" and "Hands on the panel"; the bars, crank and lever here send the left stick (X, X/Y), the right stick's Y and the left stick's X.
**Never run against a core here**: which direction of the Y axis is "pull" for Prop Cycle, and that the right stick reaches `AD_STICK_Z` on the core build in the room, are owed.

## 5. Not built

Plain uprights until a module of their own is built. The controls are MAME's own names; "G/I/NW" the status. **Nothing below has been run.**

| family | games (romsets) | MAME's controls (verbatim names) | how it could be built |
|---|---|---|---|
| ski and board | Alpine Racer `alpinerd` 3, Alpine Racer 2 `alpinr2b` 2, Alpine Surfer `alpines` 1 (all **I**); Top Skater `topskatr` 4, Ski Champ `skichamp` 1 (**NW**) | Alpine: `AD_STICK_X` "Steps Swing" (player 1) and `AD_STICK_X` "Steps Edge" (player 2's port); Top Skater: `AD_STICK_X` "Curving", `AD_STICK_X` "Slide", buttons "Select Left/Right", "Jump Front", "Jump Tail"; Ski Champ: `PADDLE`, `PEDAL` | a platform of two foot plates that slides across (swing) and tips (edge, on the second port), the player standing on it (the head's offset is the swing); poles are not a control |
| jet ski, kayak, raft | Aqua Jet `aquajet` 1, Jet Wave `jetwave` 3 (**I**); Wave Runner `waverunr` 1, Rapid River `rapidrvr` 3 (**NW**) | Aqua Jet: `PADDLE`, `PEDAL`, `AD_STICK_Y`; Jet Wave: `PADDLE` "Steering Handle", `PEDAL` "Accelerator", button "Angle", "Tilt Left/Right"; Wave Runner: `AD_STICK_X` "Handle Bar" and "Roll", `AD_STICK_Y` "Throttle Lever" and "Pitch"; Rapid River: `AD_STICK_Y` "Yaw", `AD_STICK_X` "Pitch" | the `bike` form's bars and lean on a jet ski's hull; a throttle lever (`slide`'s sibling); a paddle in both hands |
| fishing | Sega Bass Fishing `bassdx` 4, Get Bass `getbass` 1 (**NW**) | `AD_STICK_X`, `AD_STICK_Y`, `PEDAL`, `PADDLE_V`, `PADDLE` | a rod (a second `rifle`-like gun on a post) and a reel crank (the `cycle`'s `CrankGrab`) |
| horse | Final Furlong `finfurl` 1, Final Furlong 2 `finfurl2` 2 (**NW**) | `AD_STICK_X` "Handle", `AD_STICK_Y` "Swing", buttons "Whip Button L/R" | a saddle you sit on (`CockpitSeat`) and reins to pull |
| tank and pod cockpits | Tokyo Wars `tokyowar` 2 (**I**); Desert Tank `desert` 1 (**NW**); Cyber Sled `cybsled` 2 (**I**); Big Run `bigrun` 2 (**G**); Magical Truck Adventure `magtruck` 1 (**NW**) (Emergency Call Ambulance `eca` is a `race` cockpit now) | Tokyo Wars: `PADDLE` "Steering Wheel", `PEDAL` "Forward Pedal", `PEDAL2` "Backward Pedal", "Left/Right Trigger"; Cyber Sled: two `AD_STICK` pairs a player, "Missile", "Gun", "Viewport Change"; Desert Tank: `PADDLE`, `PEDAL`, `AD_STICK_Y`, "Machine Gun", "Cannon", three "VR" buttons | the `race` cockpit with the extra triggers; a pod with two sticks a seat |
| vector cockpits | Star Wars `starwars` 3, The Empire Strikes Back `esb` 1, Red Baron `redbaron` 2, Battlezone `bzone` 4 (**G**) | `AD_STICK_X` and `AD_STICK_Y` (a yoke); Battlezone two sticks (a plain `twin` panel already) | a yoke on a column (a `stick` panel drawn as a yoke) in a pod |
| striking | Punch-Out!! `punchout` 5, Super Punch-Out!! `spnchout` 3, Arm Wrestling `armwrest` 1 (**G**); Boxing Mania `boxingm` 1 (**NW**) | a joystick and buttons (Punch-Out: two stacked screens); Boxing Mania "Select L/R" | two stacked monitors (the `s2` frame is side by side now); gloves as two hand poses |
| light-gun oddities | Hammer `hammer` 1, Mallet Madness `maletmad` 1 (**G**); GunMania `gunmania` 1 (**NW**); Lucky & Wild `luckywld` 2 (**G**) (Rail Chase `rchase` is a gun ride with a bench now) | `LIGHTGUN_X/Y`; Lucky & Wild also `PADDLE` and two pedals | a mallet on the gun's hit point; a seat for a driver beside a gunner |
| rhythm | ParaParaParadise `ppp` 2, `ppp11` 1, ParaParaDancing `ppd` 1 (**I**); `ppp2nd` 2, Dance Maniax `dmx2m`, `dmx2majp`, Mambo a Go-Go `mamboagg` 2 (**NW**) | almost nothing: only SERVICE and two buttons are MAME inputs (sensors are not emulated) | none until the sensors are |
| spinner on an upright | Kick `kick` 3, Kickman `kickman` 1 (**G**) | `IPT_DIAL` | **already a dial panel**: the `odd` mark is redundant |
| other | Jambo! Safari `jambo` 1 (**NW**) | not found | |
| **music** | beatmania `bm*` (about 40), beatmania IIDX, GuitarFreaks `gtrfrk*`, DrumMania `drmn*`, Percussion Freaks `pcnfrk*`, pop'n music `popn*`, Keyboardmania `kbm*`, Taiko `taiko*` (158 romsets, 82 families; most **I** or **NW**) | turntables (`PADDLE`, `AD_STICK`), nine buttons, drum pads, guitars | the instrument itself, the hands through its bars; each game needs its own disk image |

Not a single cabinet, and the biggest unbuilt group: **the `gambling`, `mahjong`, `keypad`, `hanafuda` and `keyboard` machines (2,920 parents, 1,090 of them playable, 8,778
romsets with an `other` kind; 2,776 parents have no other control)** draw as a joystick panel, which is wrong and harmless. A mahjong or keypad panel would push keyboard keys to the core
(the extension has a key input).

## 6. The first survey

What `arcade.md` held under "Unusual cabinets" before this list: the families MAME's drivers file as special, by what the player does, with a VR idea each (kept as it was written, 2026-10-25; the games it names are checked against the drivers in section 5 where they are on the curated list). The statuses are MAME 0.289's.

What the table files as `odd` or `music`, and more, for later: VR natural interaction is the point of most, and the desktop will stay limited. Checked
against MAME 0.289 (status: **G** good, **I** imperfect, **NW** not working, from the driver flags; the controls from the drivers' port names).
libretro MAME reads every left/right axis (paddle, spinner, trackball, analog X, gun X) from the left stick X or the mouse X, up/down from left stick Y,
MAME's third axis from the right stick Y and the pedals from R2/L2; two axes of one type for one player collapse onto one stick axis unless remapped.
Many of the body cabinets are on boards MAME does not run (NAOMI is Flycast's here; Model 3, System 23, Viper, Hikaru are NW).

| family | games (romset, status) | what the player does | a VR idea |
|---|---|---|---|
| ride-on | Prop Cycle `propcycl` I, Final Furlong `finfurl` NW, Hang Pilot `hangplt` I, Magical Truck Adventure `magtruck` NW | pedal a bike to fly, ride a horse, a hang-glider bar, pump levers | grip and pump; rock; a two-hand A-frame |
| ski / board | Alpine Racer `alpinerd` 2 `alpinr2b` Surfer `alpines` I, Top Skater `topskatr` NW, Ski Champ `skichamp` NW | swing and edge ski plates, poles; a skateboard deck | hips shift = swing, grip roll = edge |
| boat / jet ski | Aqua Jet `aquajet` I, Jet Wave `jetwave` I, Wave Runner `waverunr` NW, Rapid River `rapidrvr` NW | a jet ski's bars and throttle; a raft's paddle | bars and a lean; an oar in both hands |
| fishing | Fisherman's Bait `fbaitbc` `fbait2bc` `fbaitmc` I, Sega Bass Fishing `bassdx` / Get Bass `getbass` NW | a rod, a reel | jerk the rod, crank the reel |
| striking | Punch-Out!! `punchout` Super `spnchout` Arm Wrestling `armwrest` G, Heavyweight Champ `hwchamp` G, Title Fight `titlef` I, Boxing Mania `boxingm` NW, Mallet Madness `maletmad` Hammer `hammer` Mole Attack `mole` G, Kick & Kick `kicknkick` I | punch, swing a mallet, kick a ball | punch at height, swing (the hit point is a gun's x/y) |
| music | beatmania `bm1stmix` pop'n music `popn1` Keyboardmania `kbm` I (about 40 more), GuitarFreaks `gtrfrks` I, DrumMania `drmn` NW, ParaParaParadise `ppp` I, Mambo a Go Go `mamboagg` NW | keys and a turntable, nine buttons, a guitar, drums, sensor bars, congas | the instrument itself; hands through the bars |
| hologram / multi-screen | Time Traveler `timetrv` G (laserdisc), Holosseum `holo` I, Starblade `starblad` I, Darius `darius` G (3 screens), Ninja Warriors `ninjaw` I, Super Dead Heat `spdheat` (4), Cyberball `cyberbal` G, Hard Dunk `harddunk` I (6P), Punch-Out!! (2 stacked), Silent Scope `sscope` NW (the scope's view) | a figure floating over a black stage; a bank of screens | a floating plane; a curved bank; the scope's view in the eyepiece |
| cockpit / flight / tank | Star Wars `starwars` ESB `esb` Firefox `firefox` Red Baron `redbaron` G, Battlezone `bzone` G, Tokyo Wars `tokyowar` I, Cyber Sled `cybsled` I, G-LOC R360 `glocr360` G, After Burner II `aburner2` Space Harrier `sharrier` G, Steel Talons `steeltal` G, Densha de GO! `dendego` I, Desert Tank `desert` NW | a yoke, tread sticks, a periscope, a 360 degree capsule, a train's controller | the driving seat with a yoke, a stick or a lever |
| a special control on an upright | Tempest `tempest` Tron `tron` Discs of Tron `dotrone` Kick `kick` G (spinner), Marble Madness `marble` G (+ about 130 trackball games), Paperboy `paperboy` 720 `720` G, Toobin' `toobin` G, Super Off-Road `offroad` Hot Rod `hotrod` Super Sprint `ssprint` G (3-8 wheels), Ms. Pac-Man `mspacman` cocktail | a spinner, handlebars, paddle buttons, several wheels, a table | a panel module each |
| other | Panic Park `panicprk` NW (two levers in one slot), Lucky & Wild `luckywld` G (a driver and a gunner), Rail Chase `rchase` G (a moving cart), GunMania `gunmania` NW, Jambo! Safari `jambo`, Emergency Call Ambulance `eca` NW, Final Lap 3 `finalap3` I (twin seats), Police 24/7 `p911ed` NW (body-dodge sensors) | | seats with guns; the lever |

Not working and for later: Angler King `aking`, Punch Mania `pnchmn`, Mocap Boxing `mocapb`, Arm Champs II `armchmp2`, Galaxian3 `gal3`, Driver's Eyes `driveyes`,
Ridge Racer Full Scale `ridgeracf`, Hydro Thunder `hydrthnd`, the photo-sticker booths `pclub2` `npcartv1` (camera and printer not emulated).
**By playable games per effort** (working parent sets in MAME 0.289): 1. control modules on the upright (154 spinner, 133 trackball, 58 paddle, 33 rotary games: only the
panel changes); 2. more screens and panels and the cocktail table (107 multi-screen, 269 with 4+ players, about 950 parents with a cocktail switch); 3. cockpit, flight
and tank on the driving seat (about 30); 4. striking (about 11, the most natural in VR); 5. rhythm (about 50 Bemani sets, each with its disk image and instrument);
6. the hologram stage (Time Traveler, Holosseum: one floating-plane trick); 7. the body platforms (ski, board, boat, ride-on: the best fit, about 8 working); 8. fishing (3).
Not verified: Silent Scope's scope picture on a real run, Lucky & Wild's guns (light or positional), Desert Tank's, Jet Wave's and Ski Champ's controls, Hang Pilot's second screen.

## 7. Adding a form

1. **The list.** A game's form is a choice: add it to the matching set in `Tools/arcade/gen_game_index.py` (or a new one, and a `t<form>` letter in the docstring), check its controls in MAME's driver
   (`Tools/arcade/mame_inputs.py <driver dir> <romset>...`), then regenerate the table (`python Tools/arcade/gen_game_index.py mame0289.xml`; the file is deterministic) and diff it.
2. `ArcadeGameProfile.FORM_*` and, if the form wants anything the table does not say, an accessor. `ArcadeCabinetSpecs.for_game`: the spec key the form sets (**erase it at the top with the
   others**, add it to `_same_form`'s keys, or a morph from one form to another is skipped), the shape, the panels. `panel_extent` for a new panel kind.
3. `ArcadeCabinetBuilder`: build the parts by NAME (`ArcadeControlModule` finds `BarsPivot`, `CrankPivot`, `SlidePivot`, `WheelPivot`... by name), set the module's script on a node that is NOT in the tree
   yet (a form is built detached on a stage), give the form's pointer boxes (`form_boxes`) **under** every control a laser must reach (a box over the bars hid their grip: `reach/`), and a footprint.
4. `ArcadeControlModule`: the pose each part takes from the player's state; `ArcadePanelHands`: a `ControlGrab` kind if a hand can take hold of it (the trigger, never the grip).
5. Tests: `arcade_form_tests` (a group, and the game in `reach/`), `arcade_hand_tests`; **break each new line of code and watch a case go red**.
6. A photograph: `arcade_cabinet_probe --forms=<romset>` (windowed, not `--headless`).
7. This file, `arcade.md`, the baseline.

## 8. Verified, estimated, owed

- **Verified in code**: the table (a fresh run of the generator is byte for byte the committed file), every spec, part name and pose in the suites above, each mutation-tested.
- **Verified in MAME's source**: every control name, range and flag quoted here, and libretro-mame's axis bindings.
- **Estimated**: every dimension, travel, speed and direction of a built cabinet, and everything said of a real cabinet that was not read in a driver.
- **Owed**: a headset (every hand number), a Quest, a real core and ROM for each of the seven games (none has been run), the Y direction and the speed sense of Prop Cycle, the `PORT_TOGGLE`
  shifters, the second screen of the rifles, two peers, and photographs of the real cabinets (every image host was refused).
