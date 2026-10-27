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
`gen_game_index.py` from curated lists (`CYCLE HOLO SLOT RIFLE MOUNTED_GUN GUN_PEDAL BIKE STAND_RACER ROOFED BOARD STYLE ODD`, and `FLY` and `SEATING` in `Tools/arcade/cockpits.py`), the Cabinet
DIP switch and the game's name. 28,739 romsets, 1,647 profiles. Two attributes say what the SIT-DOWN version had (section 2b): `q`, the letters `s` (a seat), `c` (a cabin round it) and `m` (a base that
moves), and `z`, a throttle lever. A third, `b`, says the game has a Timekeeper chip whose memory it checks (`h` the image it is seeded from is hand built or missing, `g` a good dump,
`n` none: `arcade-backup-memory.md`).

| form (`t`) | romsets (families) | | form (`t`) | romsets (families) |
|---|---|---|---|---|
| plain upright | 27,340 (9,177) | | `rifle` | 51 (25) |
| `race` | 433 (185) | | `gunm` | 57 (20) |
| `gun` | 308 (152) | | `pump` | 22 (14) |
| `stand` | 132 (45) | | `cycle`, `holo`, `slot` | 2 (1) each |
| `music` (built for six instruments, 2c) | 165 (88) | | `odd` (not built) | 49 (30) |
| `bike` | 65 (25) | | `dance` | 53 (32) |
| `fly` | 45 (21) | | `racegun` | 2 (1) |
| `skate`, `snow`, `ski` (a rider standing, 2f) | 4 (1), 1 (1), 6 (3) | | | |

And across every form: **3,290 romsets stand the monitor on its side** (`r90`/`r270`: the taller `tate` body), 170 turn it over (`r180`, nothing changes), 356 drive
more than one screen, 3 to 8 players are 1,345, **2,959 are alternating** (`a`: one panel, two turns) and 14,977 read a service switch (`v`).

## 2. The eight named games

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
  the monitor shows the whole picture and the lens the part of it the rifle points at, **3 times** (`ArcadeCabinetSpecs.SCOPE_ZOOM`, the spec's `screen.scope.zoom`,
  `ArcadeScreenModule.scope_zoom`), following the gun's own aim (`LightGun.last_aim`, the point on the picture the barrel meets) and kept inside the picture. It shows only a frame of the game running:
  dark while the game is only on show (attract) and while another machine's picture is on the glass. `arcade_form_tests scope/`; `--forms=golgo13` takes the eyepiece from the player's eye
  (`formscope_`). It is an approximation: no source says what the real scope showed (sources disagree on whether it is a magnified part of the main screen at all).
- **Golgo 13's SENSOR is built (2026-10-27)** and was why "the trigger only fires in the menus": MAME names it "Sensor" (`golgo13`, `g13knd`: `IPT_BUTTON2`, JVS P1 button 7) and "Scope Sensor" (`g13jnr`:
  `IPT_BUTTON3`, `PORT_TOGGLE`) -- a proximity switch ("If the player is 10cm or closer then this will be on") that the game's shooting waits for. A deck box with a lamp (`ScopeSensor`, `ArcadePedalModule`),
  on while the rifle is in a hand or the head is at the eyepiece, lifted by the pedal's gestures (`arcade.md` "The pedal", kind `sensor`). Sources disagree on where the real one sat (under the rifle's base or its
  shoulder, against the top of the gun by the eye: low); that it is a switch the player trips and the game waits for is MAME's. **The digital scope is a scope now**: a round field, a vignette and a reticle with mil dots
  (`arcade_screen.gdshader` `scope_reticle`; a Silent Scope's lens, which is the game's own second screen, has none), 3 times (`SCOPE_ZOOM`; it was 2.5 and a flat patch of the monitor, which read as "just a cropped part of the
  screen"). Sources say the real one was an optical Tasco scope of modest magnification looking at a small CRT, with the game zooming its own picture when the sensor trips (low): the lens shows the part of the
  monitor the rifle points at, magnified, and the game's own zoom is the game's. **Not built**: a scope that follows the eye (the lens is always on), the mission select's Up / Down Select and Enter (MAME's `vertical2` joystick and
  button 3 on the cabinet's panel: the rifle's panel has START alone), a desktop view into the scope. Nothing here has been seen to run: Silent Scope is NW in MAME 0.289 and no Golgo 13 ROM was at hand.
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

### Lucky & Wild `luckywld` (Namco, 1992; System 2) — form `racegun`

- **MAME**: `namco/namcos2.cpp`, **G**. Controls (the table, `p2c2b1w0:gun+paddle+pedal;g2`): two light guns (`LIGHTGUN_X/Y`, one a player), a `PADDLE` (the wheel) and a `PEDAL`.
- **The real cabinet** (research, low on the form): a sit-down for **two**, one driving and one shooting, a gun each. Nothing in MAME says which seat is which, so
  **the driver is player 1, the LEFT seat, and the gunner player 2, the RIGHT**: an estimate.
- **Built**: a `racegun` is the racing cockpit with TWO seats (`ArcadeCabinetSpecs.RACEGUN_WIDTH` 0.90 m; each cushion 0.40 m wide and `RACEGUN_SEAT_X` 0.21 m to a side of the middle; each a real `CockpitSeat`,
  `seats.md`, pressed to sit and got up from on its OUTSIDE): the wheel and the pedal in front of the DRIVER alone, no gear lever, no roof, no panel (the game has no button but START), a START at each end of the dash (the driver's
  on the left; the gunner's on the right is its own controller, player 2, so a pad in the second port or a netplay peer is the gunner), and **a gun each in a holster on the dash's face** (`_dash_holster`: a plate, a cup and a strap on the face the
  seats look at, the cord going into a grommet beside it, `gun_style` `dash`, the first player's gun the left one). The monitor stands under the same hood as every sit-down cabinet (`hood/`): the picture a metre from either seat's eyes.
- Why a form of its own: `gun` is a stand-up deck with holsters on the panel, `race` has one seat and no guns; this is the only game with both, so **it is filed by hand** (`RACEGUN` in `Tools/arcade/gen_game_index.py`) and
  `ArcadeGameProfile.is_gun()` and `is_driving()` both answer for it. It was an `odd` (not built) until 2026-10-26: a driving cockpit that sat one person and left the gunner standing.
- Estimates: the seat widths and spacing, the holsters' place, the driver being the left seat. Not verified: that the guns of a real run are light guns (rather than positional), a headset, a second player.
- Tests: `arcade_form_tests racegun/` (and the `reach/` list, where Lucky & Wild has to leave its guns reachable), `seat_tests pair/` (each seat sat in and got up from on its own side, one at a time). Pictures: `arcade_cabinet_probe --forms=luckywld`
  (`form_`, `formside_`, `formscreen_`, `formseat_`, `formlap_`, `formfeet_`).

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
| G-LOC `gloc`, Strike Fighter `strkfgtr` | `fly` | s c m | `gloc`, `strkfgtr` | DIP "Moving", "Cockpit" |
| G-LOC R360 `glocr360` (`glocr360j`), Wing War R360 `wingwar360` | `fly` | s m + rings (`r`) | no (the R-360 has no Z of its own) | research: a sphere in a two-axis gimbal on a ring that turns a full circle |
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
- **An upright you sat at** (Darius and Darius II; `qs` on a plain upright, 2026-10-26): research (BEEP! 4/87 through a Gigazine summary, one chain) says Taito's three-screen cabinet had a **bench-style seat with Body Sonic built in** (the speakers in the seat; the "rumbling subwoofer"
  comment in `ninjaw.cpp` is the same family's). The bench is the ride's, with a seat a player (two) **closer to the panel** (`UPRIGHT_BENCH_Z`, the cushion's middle 0.98 m from the front instead of 1.16: the seated player reaches the sticks, 0.5 m, and the three
  pictures are 0.6 m from the eyes and fill the view: the cabinet's "movie-like feel"). It is furniture: a player may stand. **Ninja Warriors (same cabinet design, upright listings say standing, one review sit-down), Darius Gaiden (an F3 upright) and every other upright stay
  standing.** The bench does not move (the real one did nothing but sound).
- **Sega's Star Wars Arcade** (`swa`, `swaj`; Model 1, 1993/94; not Atari's Star Wars, which is an upright with a yoke, 2e) is the same arrangement, on research (two listings, medium): **two seats, a pilot and a gunner**, **an analog
  joystick each with a trigger and a thumb button** and a throttle lever for the pilot's seat alone; the monitor a 50 inch rear projection housed separately (one listing, low). Built as `qs` (a bench of two seats) in front of two stick panels of three buttons and `m50` (the
  biggest picture an upright's body holds: the `tall` body, 1.08 m wide). **Not found and not drawn**: what the seats were (the stick was found on the deck's place, not between the knees), the pilot's throttle (MAME gives the game a `PEDAL`, which no upright panel draws), any motion.
  Before this it was a plain upright with two sticks and the 25 inch tube.
- **The bench** (`bench`): a gun ride's platform in front of the guns, which stay on the deck, with a seat a gun (two at most, 40 cm wide each, the eyes capped at 1.20 m so a seat at a 1.33 m glass is not a stool), each player getting up
  on the outside of their own seat. **The bench does not move**: nothing says how the ride moved (the libretro API carries no output of the game's), and a seat that rocked to no purpose under a headset is harm for nothing.
- **The R-360 pod** (`glocr360`, `glocr360j`, `wingwar360`: the table's `r`, 2026-10-26): see below. **Not built**: rudder pedals (Sega Strike Fighter's `AD_STICK_Z` is one, Thunder Ceptor's accelerator pad is a `PEDAL`); Sega Strike Fighter's three screens;
  Air Rescue's twin; The Ocean Hunter's bench (unverified); a bench that moves; the real motion of any of them.
- **The R-360 pod** (`glocr360`, `glocr360j`, `wingwar360`; the table's `qsmr`): Sega's sphere cockpit hung in a two-axis gimbal on a ring that turns a full circle, a hydraulic seat that can turn upside down, a harness and a safety bar (research,
  two summaries agree; no photograph). The cockpit is the flight one with **rings where the canopy's panels would be** (`ring` for `cabin` in the spec, `_build_ring`): two hoops of 1 m stand each side of the platform, outside it, on an
  axle through the seat's middle at the level of the chest (`RingOuter`), a hoop of 0.8 m stands behind the seat (`RingInner`), each with four hazard-yellow brackets a quarter turn apart so the turn shows. **They are open frames**: no collision, no pointer
  box, a player walks through them, and none stands in the picture's line of sight (the hood test's sight line, `glocr360` in its list). They turn with the base's motion (`Options > Cabinet Motion`, as the base itself does):
  **a pull turns the outer ring about the axle up to 96 degrees over the top, a push to the side the rear one about the view's axis up to 120 degrees**, eased at 4 a second; the seat and the eyes do not turn with them (the base tips its 4 degrees
  and the seat with it, as for any moving base), a headset is never spun round. *The real pod turned the player right over; here the seat stays and the rings turn round it.* Every size is an estimate. A clone's own profile is needed for this
  (`RING` in `cockpits.py`, by machine name: `gloc` and `wingwar` keep the canopy).
- Tests: `arcade_form_tests seating/` (the table's flags for 34 games, the cabin, the controls, the tilt's direction and size, the bench), `arcade_form_tests ring/` (14 checks: the table, the spec, the parts and where they stand, each hoop's plane, the brackets, no collision, the pull
  and the push turning the right ring about the right axis, eased, the seat's eyes staying put, level again, off with Cabinet Motion off; 22 mutations, all red, the generator's included), `arcade_hand_tests fly/`, `seat_tests follow/`, `arcade_variants_tests` (the setting is saved);
  pictures `arcade_cabinet_probe --forms=aburner2,sharrier,nightstr,outrun,lostwsga` (`form_`, `formside_`, `formseat_`, `formlap_`, `formtilt_`).

## 2c. The rhythm games' own controllers

(2026-10-26.) beatmania, pop'n music, GuitarFreaks, DrumMania, Taiko no Tatsujin and Mambo a Go-Go were `music`: an upright with a stick and six buttons, whatever the game. The form is now **built for six
instruments**, one per family of controller (`ArcadeInstruments`, `Scripts/Data/systems/arcade_instruments.gd`: the data, where each part stands and which of MAME's buttons it is; `ArcadeCabinetBuilder._build_instrument`
draws it). The table's `i` names the instrument (`ideck ipopn iguitar idrums itaiko iconga`, `ArcadeGameProfile.instrument()`); `gen_game_index.py` sets it from the description with the patterns of `INSTRUMENT` in
order, so beatmania IIDX and beatmania III match first and say **none**, and **Keyboardmania, IIDX and beatmania III stay the generic panel** (a form with no known instrument keeps `layout_panels`). A set is a
`music` game when its description says so (`MUSIC_DESC`): 165 romsets in 88 families, 139 of them with an instrument.

| instrument | games (romsets, families) | MAME's own names (verbatim, `konami/djmain.cpp`, `konami/ksys573.cpp`, `namco/namcos10.cpp`) | what is built |
|---|---|---|---|
| `deck` | every beatmania set: 1st to 7th Mix, Complete Mix 1 and 2, Final, DCT... (18, 13) | `beatmania_btn`: `BUTTON1` to `BUTTON5` of player 1 and of player 2, `IPT_DIAL` `TT1` and `TT2` ("turn table 1P/2P"), `START1`, `START2`, `START3` named "Effect" | a deck a player, side by side: **a turntable on the outside and five keys** (three white in the front row, two black behind, as a keyboard's), START and no effect button (the third START is nothing a pad has); the second deck is the first seen in a mirror and its keys are still numbered from the left; the turntable is a platter (`DialPivot`, `reach` its radius) that turns with LEFT/RIGHT, as every dial, and a hand takes it anywhere on the platter |
| `popn` | pop'n music 1 to 9 and the animation and Mickey sets (19, 11) | `popnmusic_btn`: `BUTTON1` to `BUTTON9` of player 1 | **nine domes across the panel** in two rows (the five of the front row white, green, red, green, white, the four behind yellow, blue, blue, yellow: button 1 the leftmost); each dome is a cap with a rim and sinks alone |
| `guitar` | GuitarFreaks 1st Mix to 11th Mix, V, V3 and the Japanese updates (46, 17) | `gtrfrks`: "P1 Button R", "P1 Button G", "P1 Button B" = `BUTTON1` to `BUTTON3`, "P1 Pick" = `BUTTON6`, "P1 Wailing" = `BUTTON7`, `IPT_DIAL` "P1 Effect Knob", a `START` each | a guitar a player lying on the deck, its neck on the outside (the second mirrored): **three fret buttons at the neck's end, a pick bar, a wail button and the effect knob on the body**. A real one is held and its wail is a tilt of the neck: here it is a button |
| `drums` | DrumMania 1 to 10, V, V2, V3 and Percussion Freaks (43, 16) | `drmn`: "High Tom" `BUTTON1`, "Low Tom" `BUTTON2`, "Hi-Hat" `BUTTON3`, "Snare" `BUTTON4`, "Cymbal" `BUTTON5`, "Bass Drum" `BUTTON6`, "Select L/R" the joystick left/right | **five pads in an arc** (hi-hat, snare, two toms, cymbal) and **the bass drum's pedal on the floor in front of the cabinet** (it goes DOWN, `press_offset`, and a hand or the pad's R presses it); a deeper deck for the kit (+0.20 m) |
| `taiko` | Taiko no Tatsujin 2 to 11 and RT (11, 11) | `taiko`: "P1R Rim" `BUTTON1`, "P1R Surface" `BUTTON2`, "P1L Surface" `BUTTON3`, "P1L Rim" `BUTTON4` (the cabinet's "Select Up/Down" and "Enter" are the test menu's) | **a drum a player** (a deck +0.25 m deep): a shell with **four zones**, the left and right half of the face and the left and right half of the rim (sectors of a ring, each a finger zone of its own: a neighbour's box would cover it), **and a pair of drumsticks** in a cradle each side of it, each on a cord into the apron (2026-10-27, `arcade.md` "Captive gear"): taken out like a gun, hit with by a swing, the trigger and A / B in a headset and the mouse on the desktop |
| `conga` | Mambo a Go-Go (2, 1) | `mamboagg`: "Left/Centre/Right Pad 1 (Top Left/Top Right)", "Pad 2 (Middle Left/Bottom Left)", "Pad 3 (Middle Right/Bottom Right)" = `BUTTON1` to `BUTTON9` (pad n of drum d is `BUTTON(3(n-1)+d)`) | **three drums side by side, each of three pads** (the top half, the bottom left and bottom right quarters), a deeper deck (+0.12 m) |

- **MAME's buttons 7 to 10.** A rhythm game has more buttons than the pad's six (`B A Y X L R`), so `ArcadeProfiles.BUTTON_COUNT` is 10: buttons 7 to 10 are the pad's L2, R2, L3 and R3 and the desktop keys V, B, N, M. *That
  libretro-mame binds MAME's `BUTTON7` to `BUTTON10` to those pad buttons is an estimate: nothing here ran a nine-button game on a core* (`pop'n`'s domes 7 to 9 and GuitarFreaks' "Wailing" are the first to need it).
- **A part is found by name**, not by node: `Btn1`..`Btn10` (a key, a dome, a pad, a sector, the bass pedal's tread), `DialPivot` (a turntable or a knob), `Start`. What has no button (a guitar's neck and body, a drum's shell) is
  drawn and nothing else. A part may stand on another (`z`: a fret on the neck, a zone on the shell). Each panel's `x0 x1 y0 y1` is the reach of everything on it **including START**, so the body is wide enough
  and the panel's grip (the one pointable thing, `ArcadePanelGrip`) covers it (a first draft left a drum pad and Taiko's START outside it; the suite found both).
- **Hands.** A fingertip presses a key, a dome or a pad where it rests (the same zones as any cap, from the mesh's box); **a sector's zone is the sector** (`ArcadePanelHands.sector_reading`: radius, angle and height, so the left
  face and the left rim never both read as pressed); the turntable is taken anywhere on its platter; the bass pedal sinks `press_offset` (down in the cabinet's frame), not into the deck's slope.
- **Estimated**: every size, position, colour and the pedal's place (`BASS_PEDAL_Z`); which side the pop'n front row and the guitar's neck are on; the guitar's wail as a button; how deep the Taiko and DrumMania decks are.
  **Research** (a haiku agent's search summaries, `WebFetch` reached no host, no page was opened): beatmania has five keys, three white and two black in a piano's zigzag, a turntable each; **which side the 1997 original's turntable was on is a conflict** (one
  summary: right of the keys, another that player 1's was later "relocated to the left"): IIDX's, the home controller's and the built one are left for player 1 and mirrored for player 2. pop'n music has nine buttons in two rows
  (a listing: white, yellow, green, blue, red, blue, green, yellow, white; one unsourced summary the reverse of the ends, which is not what is built). GuitarFreaks: three neck buttons red, green, blue, a pick on the body's face, a
  "Wailing" lane played by raising the neck, a small effect knob by the pick. DrumMania: five pads (a modified e-drum kit) and a bass pedal; pad colours not found. Taiko: a drum a player, red face (don) and blue rim (ka) (built cream and
  red), the face's diameter not found (the prototype was modelled on a 48 cm drum; 37 cm is built). Mambo a Go-Go: three drums of three zones. DDR: a 3x3 pad with the arrows on the four edge middles; Solo adds the two front corners.
  Karaoke Mix and Kids: nothing found.
  *The research summaries agree on the layouts of the buttons (the MAME names say them too) and not on measurements; no photograph was seen.* **Not built**: the Effect button of beatmania, IIDX's seven keys and two
  effect buttons, beatmania III, Keyboardmania's keyboard, DrumMania's second player, DrumMania's sticks, the guitar as a thing held and tilted. (**The Taiko's sticks are built since 2026-10-27**, `arcade.md` "Captive gear: a Taiko drummer's sticks".)
- Tests: `arcade_form_tests music/` (58 checks: the instrument of every set, the panel counts and the deeper decks, the mirrored deck's order, each part's name, its place and its MAME button, nothing hidden, the grip covers the panel,
  START where the layout puts it, a sector's mesh facing out, a finger in a Taiko zone through the hands' own pokes, the platter's reach, the bass pedal on the floor going down, the colours of the nine domes), `arcade_tests`
  (ten buttons, the desktop keys); pictures `arcade_cabinet_probe --forms=bm2ndmix,popn1,gtrfrks,drmn,taiko6,mamboagg`.

## 2d. Rotary joysticks (a stick that twists)

(2026-10-26.) A player's list began with Top Gunner's bootleg (`topgunbl`, "Rotary Joystick" in MAME's own description), and 147 romsets (56 families) have the same two controls in `-listxml`: a joystick AND a dial
(`dial+joy`; `dial+stick` for 10 more): Ikari Warriors, Victory Road, Heavy Barrel, Bermuda Triangle, Gondomania, Downtown, Calibr 50, Ikari III, Tron... They were drawn as a spinner and no stick (`panel_kind`
took the dial and stopped). **The panel is now `rotary`**: a stick as any other (`StickPivot`, the ball, the lean from the D-pad), with a **collar on its shaft** that turns (`DialPivot` on the stick's pivot, `DialKnob`
of light metal and a red `DialMark` on top so the turn shows): LEFT and RIGHT turn it, as every dial, and a hand takes it below the ball (`DialGrab`, measured in the stick's own leaned frame).

- **What the real ones were** (research, search summaries, `hw2/flight.md`): SNK's LS-30 stick, from Ikari Warriors, is a stick whose shaft also twists, with a 12-way rotary switch and two buttons (fire and grenade); Top Gunner (Jackal's
  North American name) was modelled on SNK's TNK III and Ikari sticks, one stick steering and aiming the turret for eight directions; **which control `topgunbl` has is not established** ("an eight-way rotary stick" or an Ikari-style dial, one source each).
  MAME says the bootleg has both a joystick and a positional (a rotary encoder), which is what is built.
- **A paddle is not a twist**: a dial with a joystick and a PADDLE (`wrally`, `gtmr`: Gaelco's World Rally, Great 1000 Miles Rally) is a driving game's wheel and gear lever and stays the dial panel; a dial with a trackball is a trackball
  (`ball`, Discs of Tron), with a pedal a wheel (`wheel`).
- **What the core is sent**: libretro-mame binds a dial to the left stick's X AND to the D-pad's decrement/increment (section 4), so on a pad the D-pad moves the joystick and turns the dial together; the collar turns with the same input as the stick
  leans. That the twist is independent on a real core is not verified.
- Tests: `arcade_form_tests rotary/` (11 checks: the panel kind of each game, the spec and its reach, the collar on the shaft below the ball, RIGHT and LEFT, a hand's grabs, a quarter turn of the hand through the leaned stick's frame, nothing else grows a collar); 13 mutations, all red;
  picture `arcade_cabinet_probe --forms=ikari` (`formdeck_`).

## 2e. A flight yoke and a fishing rod (controllers that are not a ball on a stick)

(2026-10-26.) The table's `y` (control style, `STYLE` in `gen_game_index.py`, by PARENT romset) draws a game's one stick as something other than a ball on a stick; the part a hand takes is still `StickBall` and the pivot still leans
with the input, so the input, the panel's grip and a headset's hands need nothing of their own. **Both games were `odd` (an upright with a plain stick), and Bass Fishing was worse: MAME gives it a paddle and a pedal, which drew a stand-up driving
cabinet with a steering wheel and pedals.** They are uprights now (`form_of` returns "" for a style, ahead of the driving rule).

| style | games | MAME's controls | what is built |
|---|---|---|---|
| `yoke` | Star Wars `starwars` (with `starwars1`, `starwarso`), The Empire Strikes Back `esb`, Red Baron `redbaron` (`redbarona`) | `AD_STICK_X` and `AD_STICK_Y` (a yoke), `starwars`/`esb` four buttons, Red Baron one | **Atari's flight yoke** (`_yoke_head`): a column, a hub (`StickBall`), a bar across it and **a handgrip standing up at each end in the player's colour with a trigger on its front**, 0.23 m apart; the panel is a yoke's wide (`YOKE_REACH` 0.15 m each side, the first column of caps 0.19 m on, `panel_kind` "yoke") so no cap stands under a grip |
| `rod` | Sega Bass Fishing `bassdx`, Get Bass `getbass`, Bass Fishing Deluxe `getbassdx`, Ultra `getbassur` | `AD_STICK_X/Y`, `PADDLE`, `PEDAL`, `PADDLE_V` | **a rod on a stick's pivot** (`_rod_head`): a cork grip (`StickBall`), a rod 0.64 m long rising 22 degrees toward the angler (the pivot's -Y), a reel on it and **its crank** (`DialPivot` on a `CrankMount` whose Z is the reel's axle, so the handle goes round it: LEFT and RIGHT wind it, a hand takes it on the reel, the dial's own grab) |

- **Research** (search summaries, nothing opened): Bass Fishing is a rod-style controller whose reel is cranked to land fish, the line running into the cabinet, its strain changing with the angler's moves and the fish's (the Dreamcast Tsuri Controller, a different thing: a rod body with an analog
  stick on top and a reel on the right). **Not found: how the rod stood on the arcade cabinet (a swivel base? a boat?)**, its size and the cabinet's (one listing calls the US game closest to Sega's "Blast City" sit-down); an upright is built. The yoke's grips, triggers and thumb
  buttons are Atari's (MAME has four buttons on Star Wars and two triggers are two of them); where Atari put them on the real yoke is not drawn (the caps stand on the panel).
- **Estimates**: every size and angle above; the rod's lean is a guess, the way the cork grip and reel sit on it too.
- Tests: `arcade_form_tests styles/` (14 checks: the table, uprights and not driving cabinets, a yoke's panel wider than a stick's and centred, the yoke's parts and where they stand, the caps clear of the grips, the lean and the hand's grab, the rod's parts, its direction, the crank's axle
  and its turn, the two grabs a few centimetres apart, a plain stick unchanged), `layout/` takes the three new panel kinds; 20 mutations of the code, 3 of the generator, all red.

## 2f. A rider standing on a rocking board (Top Skater, Alpine Surfer, Alpine Racer)

(2026-10-26.) Games where the player does not sit, hold a wheel or aim at the screen: they STAND on the machine's own moving platform and lean it, holding a rail. They were `odd` (an upright with a stick), which asked the player for a
joystick in the place of a skateboard. **The vehicle is the form** (`BOARD` in `gen_game_index.py`, by PARENT romset): `skate`, `snow` and `ski`, all built by `ArcadeCabinetBuilder._build_board` as ONE rig that differs only in what stands on the plate.

| form | games | MAME's controls | the real machine (research: search summaries, nothing opened, no photograph seen) | what is built |
|---|---|---|---|---|
| `skate` | Top Skater `topskatr` (`topskatrj`, `topskatru`, `topskatruo`) | **NW**; one analog `stick` with four buttons; `AD_STICK_X` "Curving" and `AD_STICK_X` "Slide", buttons "Select Left/Right", "Jump Front", "Jump Tail" | Sega 1997, a skateboard-style deck that pivots side to side or tilts (three axes, medium), handrails each side (medium-low), a 50 inch screen with two speakers aimed at the rider; that the rider STANDS is inferred from the deck | a skateboard deck 0.21 x 0.72 m with a kicktail each end and two trucks with four wheels |
| `snow` | Alpine Surfer `alpines` | **I**; `joy` (2 way), two analog `stick`s | Namco 1996, a snowboard-style foot platform the rider stands on (medium), edge pressure sets the speed (medium-low), two large handlebars (medium-low); the monitor was a SEPARATE unit | a snowboard 0.27 x 0.90 m with its ends turned up, a binding and strap for each foot |
| `ski` | Alpine Racer `alpinerd` (`alpinerc`, `alpinerjc`), Alpine Racer 2 `alpinr2b` (`alpinr2a`), Ski Super G `skisuprg` | **I**; Alpine: `AD_STICK_X` "Steps Swing" (player 1's port) and "Steps Edge" (player 2's), `joy` (2 way) | Namco 1994 / 1996, Sega 1996: the rider stands on ski-style footplates that swivel (medium) and grips two side bars or poles (the sources say "bars", "handles", "poles": conflict); a 50 inch monitor, about 2.30 x 1.26 x 3.00 m (low-medium); **Alpine Racer 2 and Ski Super G's details were not found, they are drawn as the first** | two skis 0.10 x 0.90 m a shoulder's width apart, the tips turned up, a binding on each |

**The rig** (every size an estimate, constants at the top of `_build_board`): a stand 0.86 x 1.30 m and 8 cm high, 0.84 m out (clear of the bay door's swing, as the bicycle's); on it a **plate 0.76 x 1.10 m that rocks on a lengthwise axle 0.20 m up**
(`LeanPivot`, which the control module leans with the steering by `LEAN_DEG`, 14 degrees, as a bike); the vehicle on the plate; **a rail the rider holds, the posts and the side rails 0.80 m above the axle (1.00 m above the floor: a standing person's hip)**,
a grip sleeve on each side rail (`BarGripL/R`) and a crossbar across the FRONT with START on top of its middle. The rail is part of what leans (the hands' grab finds `Handlebars` and the grips under `LeanPivot`, as a bike's). The axle stands high enough that
the plate's low edge clears the stand at full lock (0.09 m of dip against 0.094 m clearance; the test measures it). The screen is the wide body's own 0.72 x 0.54 m tube at standing height, the bicycle's; a 50 inch one would not fit its glass.

- **One rider a machine** (`PLAYERS`): MAME counts two riders for the Alpine games (two linked machines); one rig is built. Top Skater's two coins are one coin door (a rig has one controller).
- **No seat, no collision**: a person steps up to the stand and stands on the floor beside the plate or on the plate's place (the cabinet is not solid). **The pointer box stops under the rail** (stand and plate, 0.34 m up) or a laser could not reach a grip.
- **Hands**: the trigger on a grip takes the rail; **sideways 15 cm is a full lean, and the rail's middle is the middle of its two grips so that a full throw (0.49 m from it) is still held** (the let-go distance is 0.55 m: the crossbar's own middle, 0.30 m forward of the grips, would
  have been 0.575 m from a hand at the end of its throw and let go of it at full lock, the test that found it); a fingertip on START presses START.
- **Not built, and said**: the real mechanisms (Alpine Racer's footplates *swivel* and slide; Top Skater tilts about three axes: only the roll is drawn); **Alpine's second axis, "Steps Edge", is player 2's port and a second axis of Top Skater's ("Slide") is not sent: the rig steers with the left stick's X**;
  the buttons (Top Skater has four, Alpine Surfer three: none is drawn, as a bike's gear button is not); Alpine Racer's poles (the rail stands in for them); the monitor unit Alpine Surfer had; Ski Champ `skichamp` (a paddle and a pedal in MAME: nothing found says what its
  rider stood on), Sega Water Ski `segawski` (foot pads: "compared with Top Skater", low-medium) and Surf Planet `surfplnt` stay uprights. **Which way the rig leans for a given axis of the real machine is not known**: right is drawn as a lean right.
- Tests: `arcade_form_tests rider/` (46 checks: which romsets are which vehicle and nothing else is, the spec, every part of the rig on a real cabinet and nothing of the other vehicles, the rail at the waist and symmetric, the bars taken from the middle of the grips, the crossbar in front with START on top of
  it, everything on the stand, the stand clear of the door, the ends turned up, the wheels on the plate, the bindings, the skis apart, the plate clear of the stand at full lock either way, the plate and the whole rail leaning into the turn, nothing between a standing rider's eyes and the picture,
  the pointer box, no collision, the upright back); `arcade_hand_tests rider/` (21: the grab, a full throw still held, the plate drawn leaning, a hand a metre off let go, START pressed, for each vehicle). Mutation-tested line by line: the rail's height and width, the crossbar behind the grips, the bars' middle at the crossbar
  (the one the hands' test and the form's catch for different reasons), START off its place, the rail or the posts off the plate, the stand too near or too short, a pointer box over the rail, every end tipped the wrong way, wheels off the plate, a binding twice, the skis on each other, the spec on the wrong body or keeping panels, one vehicle for all, the profile counting a bike or missing a ski: all red.
  Photographs (`Tools/models/arcade_cabinet_probe --forms=topskatr,alpines,alpinerd`: `form_`, `formside_`, `formstand_` from a standing rider's eyes, `formrail_` down at the crossbar, `formlean_` leaned over): the rig, the three vehicles and the lean are as described.

## 3. Every form that is built

What each one is made of, so a new one can follow it. "Hands" is what a headset's hands do on it (`arcade.md` "Hands on the panel").

| form | games | what stands there | how it is built | hands |
|---|---|---|---|---|
| **panels by player** (any) | every game | a panel per player, the control the game has and exactly its buttons | `layout_panels`, `panel_kind` (`stick twin ball dial buttons wheel rotary`), `button_grid`; three to six players make the BODY wider (`body_width`), a door and a socket under each panel | a fingertip presses a cap; the trigger takes a stick, a dial, a trackball |
| **tate** | 3,290 romsets | the monitor on its side | its own body (`tate`: the glass 0.65 m up the slant, 1.92 m tall) and a 0.36 x 0.48 m tube; every window is cut to its tube | |
| **alternating** | 2,959 | one panel, 1P, and a 2P START | the table's `a`; one coin door | |
| **screens** | 356 | several screens side by side | the tube row; the frame holds them as one picture | |
| **service** | 14,977 | TEST and SERVICE in the compartment opposite the power switch | `ArcadeServiceModule`, only where MAME says `<input service="yes">` | VRButtons |
| `gun` | 308 (135) | guns in holsters, a pedal where the game had one (Time Crisis), a bench where it was a ride (Rail Chase) | the wide body, one gun for each light gun the game has (up to 3), START alone each | the hand takes the gun as any pickable |
| `gunm` | 57 (16) | a gun on a post, a bench where it was a ride (The Lost World) | Operation Wolf's Uzi, Terminator 2, Beast Busters (3): fixed to the post, turning about its pivot; Rail Chase's joystick-like guns, Laser Ghost's three blasters, Gunbuster's two pistols with a stick each (9.2c) | the hand turns it |
| `rifle` | 51 (7) | one rifle on a taller post | Silent Scope, Golgo 13; see above | the hand turns it |
| `race` | 355 (104) | a sit-down cockpit | the `racer` body, platform, seat, dash, wheel, two pedals, gear lever; a roof for the Model 3 twins (`ROOFED`); a moving base for Out Run, Power Drift (`q`) | wheel (clockwise is right), pedals under a finger, the lever |
| `racegun` | 2 (1) | a sit-down cockpit for two, a driver and a gunner | the `race` cockpit with a second seat, a gun each in a holster on the dash, a START at each end (Lucky & Wild, see 2) | wheel and pedal at the driver's seat, the hand takes a gun as any pickable |
| `fly` | 41 (17) | a sit-down flight cockpit | the `race` cockpit with a stick and a throttle for the wheel, a cabin where the game's had one, a moving base; see 2b | the grip leans with the hand, the throttle lever stays where it is left |
| `stand` | 123 (34) | a stand-up driving cabinet | the wheel on the panel, a lever beside it, the pedals on the floor in front (Pole Position, Out Run, Final Lap) | the same |
| `bike` | 64 (19) | a ride-on motorbike | a bike on a stand in front of the `racer` body; it LEANS (`LeanPivot`) | the bars: sideways 15 cm is a full lean |
| `cycle` | 2 (1) | a bicycle | see Prop Cycle | bars (two axes), crank |
| `skate`, `snow`, `ski` | 4 (1), 1 (1), 6 (3) | a rider standing on a rocking plate, a rail round the front | see 2f: a stand, a plate that leans (`LeanPivot`), a skateboard, a snowboard or two skis on it, the rail | the rail's grips: sideways 15 cm is a full lean; START with a fingertip |
| `holo` | 2 (1) | a deep stage behind the glass | see Time Traveler | |
| `slot` | 2 (1) | two levers in one slot | see Panic Park | the lever slides |
| `dance` | 53 (32) | a stage of four arrows a dancer (a Solo cabinet's six, 9.2) | a 10 cm platform with a square of nine 30 cm panels, a safety bar; the arrows sink with the directions | the body over an arrow presses it, a click on the platform stands the player up on it, a finger can press an arrow too (9.2b) |
| `pump` | 22 (14) | a stage of five panels | Pump It Up's diagonals, the buttons' own | the same |
| `music` | 165 (88), 139 with an instrument | a rhythm game's own controller: a beatmania deck, pop'n's domes, a guitar, a drum kit, a Taiko drum, Mambo's congas (2c) | `ArcadeInstruments` (data) and `_build_instrument`; the parts are named for the control module (`Btn1`..`Btn10`, `DialPivot`) | a fingertip presses a key, a dome, a pad or a zone of a drum (a sector); the turntable is taken anywhere on its platter |

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
| ski and board | **built since (2f)**: Alpine Racer `alpinerd` 3, Alpine Racer 2 `alpinr2b` 2, Ski Super G `skisuprg` 1 (skis), Alpine Surfer `alpines` 1 (a snowboard), Top Skater `topskatr` 4 (a skateboard). **Left**: Ski Champ `skichamp` 1 (**NW**), Sega Water Ski `segawski`, Surf Planet `surfplnt` | Alpine: `AD_STICK_X` "Steps Swing" (player 1) and `AD_STICK_X` "Steps Edge" (player 2's port); Top Skater: `AD_STICK_X` "Curving", `AD_STICK_X` "Slide", buttons "Select Left/Right", "Jump Front", "Jump Tail"; Ski Champ: `PADDLE`, `PEDAL` | nothing found says what Ski Champ's rider stood on (a paddle and a pedal in MAME), Water Ski's foot pads are "compared with Top Skater" (low-medium) and nothing at all was found on Surf Planet's: the rig of 2f with the vehicle they had, once known; **the built rig steers with ONE axis**, the second ("Edge", "Slide") is not sent |
| jet ski, kayak, raft | Aqua Jet `aquajet` 1, Jet Wave `jetwave` 3 (**I**); Wave Runner `waverunr` 1, Rapid River `rapidrvr` 3 (**NW**) | Aqua Jet: `PADDLE`, `PEDAL`, `AD_STICK_Y`; Jet Wave: `PADDLE` "Steering Handle", `PEDAL` "Accelerator", button "Angle", "Tilt Left/Right"; Wave Runner: `AD_STICK_X` "Handle Bar" and "Roll", `AD_STICK_Y` "Throttle Lever" and "Pitch"; Rapid River: `AD_STICK_Y` "Yaw", `AD_STICK_X` "Pitch" | the `bike` form's bars and lean on a jet ski's hull; a throttle lever (`slide`'s sibling); a paddle in both hands |
| fishing | **built since (2e)**: Sega Bass Fishing `bassdx`, Get Bass `getbass`, Deluxe and Ultra: a rod and a reel's crank on an upright (how the rod stood on the real cabinet is not known) | `AD_STICK_X`, `AD_STICK_Y`, `PEDAL`, `PADDLE_V`, `PADDLE` | |
| horse | Final Furlong `finfurl` 1, Final Furlong 2 `finfurl2` 2 (**NW**) | `AD_STICK_X` "Handle", `AD_STICK_Y` "Swing", buttons "Whip Button L/R" | a saddle you sit on (`CockpitSeat`) and reins to pull |
| tank and pod cockpits | Tokyo Wars `tokyowar` 2 (**I**); Desert Tank `desert` 1 (**NW**); Cyber Sled `cybsled` 2 (**I**); Big Run `bigrun` 2 (**G**); Magical Truck Adventure `magtruck` 1 (**NW**) (Emergency Call Ambulance `eca` is a `race` cockpit now) | Tokyo Wars: `PADDLE` "Steering Wheel", `PEDAL` "Forward Pedal", `PEDAL2` "Backward Pedal", "Left/Right Trigger"; Cyber Sled: two `AD_STICK` pairs a player, "Missile", "Gun", "Viewport Change"; Desert Tank: `PADDLE`, `PEDAL`, `AD_STICK_Y`, "Machine Gun", "Cannon", three "VR" buttons | the `race` cockpit with the extra triggers; a pod with two sticks a seat |
| vector cockpits | Star Wars `starwars` 3, The Empire Strikes Back `esb` 1, Red Baron `redbaron` 2 (**G**; **the yoke is built since, 2e**: the upright's, not the sit-down pod), Battlezone `bzone` 4 (**G**) | `AD_STICK_X` and `AD_STICK_Y` (a yoke); Battlezone two sticks (a plain `twin` panel already) | the sit-down pod round the yoke; Battlezone's periscope |
| striking | Punch-Out!! `punchout` 5, Super Punch-Out!! `spnchout` 3, Arm Wrestling `armwrest` 1 (**G**); Boxing Mania `boxingm` 1 (**NW**) | a joystick and buttons (Punch-Out: two stacked screens); Boxing Mania "Select L/R" | two stacked monitors (the `s2` frame is side by side now); gloves as two hand poses |
| light-gun oddities | Hammer `hammer` 1, Mallet Madness `maletmad` 1 (**G**); GunMania `gunmania` 1 (**NW**); Lucky & Wild `luckywld` 2 (**G**; built since: the `racegun` form, section 2) (Rail Chase `rchase` is a gun ride with a bench now) | `LIGHTGUN_X/Y`; Lucky & Wild also `PADDLE` and two pedals | a mallet on the gun's hit point; a seat for a driver beside a gunner |
| rhythm | ParaParaParadise `ppp` 2, `ppp11` 1, ParaParaDancing `ppd` 1 (**I**); `ppp2nd` 2, Dance Maniax `dmx2m`, `dmx2majp` (**NW**) (Mambo a Go-Go `mamboagg` is built since: 2c) | almost nothing: only SERVICE and two buttons are MAME inputs (sensors are not emulated) | none until the sensors are |
| spinner on an upright | Kick `kick` 3, Kickman `kickman` 1 (**G**) | `IPT_DIAL` | **already a dial panel**: the `odd` mark is redundant |
| other | Jambo! Safari `jambo` 1 (**NW**) | not found | |
| **music** | **built since (2c)**: beatmania `bm*`, GuitarFreaks `gtrfrk*`, DrumMania `drmn*`, Percussion Freaks `pcnfrk*`, pop'n music `popn*`, Taiko `taiko*`, Mambo a Go-Go. **Still the generic panel**: beatmania IIDX `bmiidx`..., beatmania III `bm3*`, Keyboardmania `kbm*` (26 romsets) | IIDX: seven keys, two effect buttons and a turntable (a trackball to MAME); Keyboardmania: two octaves of keys | IIDX's deck is the beatmania `deck` with two more keys and the effect buttons; Keyboardmania's keyboard a row of 24 keys |

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
| ski / board | Alpine Racer `alpinerd` 2 `alpinr2b` Surfer `alpines` I, Top Skater `topskatr` NW, Ski Champ `skichamp` NW (**built since, 2f**, but Ski Champ) | swing and edge ski plates, poles; a skateboard deck | hips shift = swing, grip roll = edge |
| boat / jet ski | Aqua Jet `aquajet` I, Jet Wave `jetwave` I, Wave Runner `waverunr` NW, Rapid River `rapidrvr` NW | a jet ski's bars and throttle; a raft's paddle | bars and a lean; an oar in both hands |
| fishing | Fisherman's Bait `fbaitbc` `fbait2bc` `fbaitmc` I, Sega Bass Fishing `bassdx` / Get Bass `getbass` NW | a rod, a reel | jerk the rod, crank the reel |
| striking | Punch-Out!! `punchout` Super `spnchout` Arm Wrestling `armwrest` G, Heavyweight Champ `hwchamp` G, Title Fight `titlef` I, Boxing Mania `boxingm` NW, Mallet Madness `maletmad` Hammer `hammer` Mole Attack `mole` G, Kick & Kick `kicknkick` I | punch, swing a mallet, kick a ball | punch at height, swing (the hit point is a gun's x/y) |
| music | beatmania `bm1stmix` pop'n music `popn1` Keyboardmania `kbm` I (about 40 more), GuitarFreaks `gtrfrks` I, DrumMania `drmn` NW, ParaParaParadise `ppp` I, Mambo a Go Go `mamboagg` NW | keys and a turntable, nine buttons, a guitar, drums, sensor bars, congas | the instrument itself; hands through the bars |
| hologram / multi-screen | Time Traveler `timetrv` G (laserdisc), Holosseum `holo` I, Starblade `starblad` I, Darius `darius` G (3 screens), Ninja Warriors `ninjaw` I, Super Dead Heat `spdheat` (4), Cyberball `cyberbal` G, Hard Dunk `harddunk` I (6P), Punch-Out!! (2 stacked), Silent Scope `sscope` NW (the scope's view) | a figure floating over a black stage; a bank of screens | a floating plane; a curved bank; the scope's view in the eyepiece |
| cockpit / flight / tank | Star Wars `starwars` ESB `esb` Firefox `firefox` Red Baron `redbaron` G, Battlezone `bzone` G, Tokyo Wars `tokyowar` I, Cyber Sled `cybsled` I, G-LOC R360 `glocr360` G, After Burner II `aburner2` Space Harrier `sharrier` G, Steel Talons `steeltal` G, Densha de GO! `dendego` I, Desert Tank `desert` NW | a yoke, tread sticks, a periscope, a 360 degree capsule, a train's controller | the driving seat with a yoke, a stick or a lever |
| a special control on an upright | Tempest `tempest` Tron `tron` Discs of Tron `dotrone` Kick `kick` G (spinner), Marble Madness `marble` G (+ about 130 trackball games), Paperboy `paperboy` 720 `720` G, Toobin' `toobin` G, Super Off-Road `offroad` Hot Rod `hotrod` Super Sprint `ssprint` G (3-8 wheels), Ms. Pac-Man `mspacman` cocktail | a spinner, handlebars, paddle buttons, several wheels, a table | a panel module each |
| other | Panic Park `panicprk` NW (two levers in one slot), Lucky & Wild `luckywld` G (a driver and a gunner: built, the `racegun` form), Rail Chase `rchase` G (a moving cart), GunMania `gunmania` NW, Jambo! Safari `jambo`, Emergency Call Ambulance `eca` NW, Final Lap 3 `finalap3` I (twin seats), Police 24/7 `p911ed` NW (body-dodge sensors) | | seats with guns; the lever |

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

## 9. The audit of the games a player asked about (2026-10-26)

A player listed 143 romsets and asked whether each spawns with the hardware it had. Each was read in MAME 0.289's `-listxml`, the driver source (raw files from `mamedev/mame` at the
`mame0289` tag: the port blocks give every button's own name) and the table, and judged against the research notes. **19 of the names are not MAME 0.289 romsets** (they are a
short form or another emulator's name): `bm2nd` / `bm2ndm` are `bm2ndmix` / `bm2ndmixa`, `bm4th` `bm4thmix`, `bm5th` `bm5thmix`, `bm6th` `bm6thmix`, `bmcompm` `bmcompmx`, `bass` `bassdx` (Sega Bass
Fishing), `guitarfr` `gtrfrks` (and its mixes), `drummania` `drmn`, `popn` `popn1`..`popn9`, `alpinesa` `alpines`, `raveracw` `raverace`, `gunbulet` `gunbuletw` / `gunbuletj` (Point
Blank's Japanese name, a clone of `ptblank`), `jurassicp` `jpark`, `r360` `glocr360` / `wingwar360`, `warpspd` `warpsped` (a 1979 prototype), `interstellar` `istellar` (Funai/Gakken's laserdisc
game); **`lamborcc` and `jubeat` are in no MAME**. The profile of a game is by ROMSET NAME, so a name MAME knows and another system uses for a different game would borrow the wrong cabinet; the cabinet only
follows the game on `arcade` boards (`on_media_inserted`), which is why a Daphne `badlands` or `roadblst` is still a laserdisc upright.

### 9.1 What was wrong in the data (found by the audit, fixed in the generator)

- **Taito F3's two spare dials.** The board's `f3` port set declares two paddle dials (`DIAL.0`, `DIAL.1`, the Z/X and N/M keys) for ALL 35 of its games; only Arkanoid Returns reads
  them. With them every F3 game (about 110 romsets: Puzzle Bobble 2-4, Elevator Action Returns, Kaiser Knuckle, Bubble Symphony, Darius Gaiden...) was drawn with a spinner where its joystick
  was. `SPURIOUS` in `gen_game_index.py` drops a control a driver's SHARED port set gives every game: `(source file, kind) -> the families that really have it`.
  `Tools/arcade/shared_controls.py mame0289.xml` lists every driver whose games ALL carry a rare control: it found no other with the same fault (the pinball keypads are not a cabinet's, Exidy's and American Laser Games' guns are real, Hard Drivin's stick is the gear lever).
- **Players.** The F3 board takes four whatever the game: Darius Gaiden (and the Extra Version) is a two-player upright, `PLAYERS`.
- **Arkanoid Returns' joystick.** With the rotary panel (2d) a dial AND a joystick draws a stick that twists, and the F3 board's menu joystick would have given the one F3 game that does read a paddle a stick beside its spinner: `UNUSED` in `gen_game_index.py` (family -> controls its cabinet had none of) drops it and keeps the four buttons it carried.
- **Driving games with no wheel in MAME.** A Chihiro, Naomi, Hikaru or Triforce game is given the joystick panel of its board (the wheel is read through the JVS), a Lindbergh or System 246
  game declares no controls at all, and Road Blasters' wheel is an analog stick: all were uprights with a stick. `DRIVING_FORM` files each as the cabinet it came in (a game that declares
  no players or no coins gets one player and two coins): **sit-down cockpits** for OutRun 2 (and Special Tours, SP SDX), Crazy Taxi High Roller, Wangan Midnight (1, R, Maximum Tune 1 and 2),
  Initial D Arcade Stage (6 sets, Initial D4), Club Kart (5), Ferrari F355 Challenge (3), Driving Simulator, The King of Route 66, Tokyo Bus Guide, NASCAR Arcade, Sega Race-TV,
  Hummer Extreme, F-Zero AX (and Monster Ride), Mario Kart Arcade GP (1 and 2), Ace Driver 3, Ridge Racer V Arcade Battle, Battle Gear 3, WGP and WGP 2; a **ride-on motorbike** for
  Namco's MotoGP; **stand-up cabinets with the wheel on the panel and the pedal at the foot** for Road Blasters and Night Driver. Every one of these is the cabinet type from memory and
  the research notes (low confidence on the exact deluxe variants), not read in a driver.
- **Bad Lands' dial is a steering wheel**, one for each of two players, with no pedals (the gas is a button): the table's `h`, `ArcadeGameProfile.steering_dial()`, a `wheel` panel
  without pedals or lever (`panel()`'s `wheel` kind). Its bootleg is a joystick game and stays a joystick cabinet.
- **Wing War R360** is G-LOC R360's pod (a seat, a cage round it, a base that moves): `wingwar` joins the flight cockpits, so its clone does too. The pod's rotation stays unbuilt.
- **Star Wars Arcade** (`swa`, two analog sticks and a throttle read as a pedal) was a plain upright with a stick each; the research (two listings, medium) says two seats, a pilot and a gunner, so it has the bench
  of two seats and a 50 inch class screen (2b). **TX-1** was a stand-up for its date; it is a seated cockpit of three screens (`DRIVING_FORM`; the research says a force-feedback
  wheel, an accelerator, a brake and a gearshift, the side screens tilted about 30 degrees).
- **World Combat / Warzaid** (Konami Viper, 2002): one optical light gun a player and one trigger each (MAME's `viper.cpp`; players take cover by aiming off the screen, there is no pedal). MAME lists its 4P sets as two
  buttons only, because the gun axes are an undefined TODO there, and files only the 2P set (`wcombatu`) as a gun game: the table had a clone as a gun cabinet and its parent and two other clones as a plain upright. All four are two guns in holsters now (`UNTYPED_GUNS`); all four sets are `NOT_WORKING`.

### 9.2 DDR Solo's six panels

`ddr4ms`, `ddr4mps`, `ddrs2k`, `ddrsbm` (and their clones `ddr4msj`, `ddrs2kj`) are the one-player Solo cabinets (a compact main unit, 159 kg on one listing, and a stage with
**six panels**: the four arrows and the up-left and up-right ones: the research, two sources). `ArcadeGameProfile.stage_arrows()` reads the table's `n6` (the generator sets it for a dance game
whose description says "Solo"); the stage builds the top row of the square (up-left, up, up-right), the left and right middles and the bottom middle, and the centre and the two bottom corners
are bare tiles. **The corners are MAME's buttons 3 and 4** (`ksys573.cpp`, `ddrsolo`: "P1 Up-Left 1" and "2" are `IPT_BUTTON3`, "P1 Up-Right 1" and "2" `IPT_BUTTON4`; "P1 Select L" and "R" are
buttons 1 and 2), so `PadUpLeft` and `PadUpRight` sink with the pad's Y and X and a fingertip on them presses those. Estimated: where the real corner panels stood (the names say the upper
corners), their size (the same 27 cm as the others), and whether the Solo's menu "Select" buttons are anything but the pad's left and right arrows. Karaoke Mix (one player, no source on its cabinet) and
Kids (one player, a smaller cabinet) keep four arrows. `arcade_form_tests solo/`.

### 9.2b The stage is walked on and stood on (2026-10-27)

The platform of every dance stage is **10 cm high** (`ArcadeCabinetBuilder.STAGE_H`) with the nine panels flush on its top (the arrows 6 mm over it): at 2 cm it sank into any floor that was
not dead flat and left the arrows half buried. The base may clip at its foot; the panels may not. There are two ways to dance, and a headset does either:

- **Walking on it.** Nothing tracks feet, so the body is the head's place on the floor: a step forward, back or sideways that puts it over a panel presses that panel (`ArcadePanelHands.update_body`,
  `foot_on`, fed by `ArcadeInput._body_point()`). The press joins the hands' (a fingertip still works), needs no attaching, and goes out through the same `netplay_route`. A panel is pressed while the point
  is over its square grown by 2 cm, with the floor under it within 18 cm below the panel's top to 6 cm above it. Estimated: those margins, and that the head stands over the feet (a dancer who
  leans out over an arrow presses it).
- **Standing up on it** (`StageSeat<n>`, one a square, a `CockpitSeat` with a trigger over the whole top, an `EyePoint` 1.62 m over the platform and a `StandPoint` 62 cm to the side, on the floor): the
  stage is a standing seat. Pointing at the platform and pressing sits the player on it in the usual way (`Seat`), but **the eye is not lowered**: the player's height changes by the platform's 10 cm and nothing
  else. While they stand up there their own controller plays that dancer (`ArcadeCabinetModel._on_stage_seat` attaches the panel), so WASD or the arrows, a pad's d-pad or stick and a Quest's sticks press
  the arrows; stepping down (the seat's usual get-up, the dancer goes to `StandPoint`) lets the panel go. A machine switched on with a dancer already up takes the panel then (`on_power_on`).
  The first square steps down to the left, the last to the right.

Tests: `arcade_form_tests stage/` (29 checks: heights, every arrow above the platform's top, the seats and their points, the panel attaching on sit and letting go, the body over each arrow of both squares, off the
square, on the room's floor, in the air, the machine off, a morph rebuilding the seats) and `arcade_hand_tests zone/` (`foot_on`'s limits); 15 mutants of the new code, each turned a case red. OWED: a headset (whether the
head's place is a believable foot, how the platform feels under the feet), a real dancer's pad ids on a real core, the Quest, two peers.

### 9.2c Fixed guns that are not pistols (2026-10-27)

Three games were drawn with pistols in holsters and are not that. **Every shape below is an estimate**: no photograph or manual could be read, and the sources are search summaries.

- **Rail Chase** `rchase` (MAME `segaybd.cpp`: two `lightgun`s of one button each) and **Rail Chase 2** `rchase2` (`model2.cpp`: two `stick`s of one button): "an analog stick with a trigger" (Arcade-Museum, medium; Sega Retro and
  arcade-history call both a light gun: unresolved), on a bench that moves (the DX). The first had pistols to draw; both now have **two guns fixed on posts** (`gunm`) shaped as a joystick (`Scenes/Objects/peripherals/arcade_light_stick.tscn`,
  `gen_arcade_gun.gd --variant=stick`: a tall rounded handle, a ball with a red cap, the trigger, a short nose that points where it aims). The pistol's own grip, trigger, cord boss and grab point, so it is aimed
  by pointing it, not by tilting a stick. The table's `ystick`.
- **Laser Ghost** `lghost` (`segas18.cpp`: three `lightgun`s of two buttons): three guns, one a player, fixed to the cabinet, each a **blaster** (`arcade_light_blaster.tscn`, `--variant=blaster`, the table's `yblaster`): 40 cm from
  grip to muzzle (a pistol's 24), a finned barrel, the "top-mounted laser imaging unit" the research names (a box with a domed lens on its back), a power cell along its side, a thick grip with a fire cap and a special-weapon cap
  (the limited-use second button). Sources (medium): players 1 and 3 sit, player 2 stands; a mirror throws the picture and each shot a red beam. The size and shape beyond "top-mounted laser imaging unit" are the request's ("huge") and ours:
  the one review that was found calls them "small laser-imaging devices on the guns". The swivel is 22 cm ahead of the grip, so the muzzle rests 3 cm short of the glass.
- **Gunbuster** `gunbustr` (`taito/gunbustr.cpp`): MAME has TWO stations, each an 8-way joystick, two buttons and a light gun, and a **link device** (`gunbustr_link.h`, shared RAM between two machines): four players are two cabinets
  linked, two stations each. "Four mounted light guns on a dual-screen cabinet" (LaunchBox) and "up to four players in two teams" (Wikipedia) are low-confidence summaries and a core has no port for a third and fourth gun,
  so two stations are built: a pistol fixed on a post and, new, **a stick with two buttons** beside it (the table's `j`, `ArcadeGameProfile.gun_stick()`: the stick walks and strafes while the gun aims). A port a gun owns takes the
  panel's START and coin only, a gun writing no pad of its own: for this game the four directions and the first two buttons reach the core there as well (`ArcadeInput._gun_stick_bits`). **Not built**: the linked pair of cabinets.
- Tests: `arcade_form_tests specs/ guns/ seating/` (the shapes, the scene each gun is built from, every gun fixed, the muzzle clear of the glass, the stick bits), `arcade_variants_tests guns/` (every shape keeps the pistol's cord boss,
  grab point and cord), `arcade_tests game/` (the table). Picture `--forms=rchase,gunbustr,lghost`.

### 9.2d Road Blasters' yoke (2026-10-27)

Atari's Road Blasters was drawn as a stand-up with a steering WHEEL and two pedals; MAME's own port list says otherwise (`atarisy1.cpp`: one steering axis (`IPT_AD_STICK_X`, 7 bits, reversed; `IPT_DIAL` in the older versions), **two buttons**, "Lasers"
(`IPT_BUTTON2`) and "Special Weapon" (`IPT_BUTTON3`), no BUTTON1, **one analog pedal** `IPT_PEDAL`, three coin inputs) and the research agrees (search summaries, medium): a **yoke** ("X Yoke", Arcade-Museum; "instead of a steering wheel", TopGear) in the
style of Atari's Star Wars yoke, which only turns (handles fixed, no push or pull), about 270 degrees from lock to lock, a pair of triggers for the lasers and thumb buttons for the special weapons, one gas pedal, no brake, no shifter. Built:

- **The yoke** (`ArcadeCabinetBuilder._helm`, the table's `yhelm`): the wheel's own column and `WheelPivot` (so the input, the hands and the lock find it as they find a wheel, `WheelRim` gone), a hub with a bar across it and a handgrip standing out of each
  end toward the driver, 14.5 cm from the hub (`HELM_SPAN`), a trigger on each grip's upper side and a red cap on its end. It turns 135 degrees each way (`lock_deg` on the pivot, `ArcadeControlModule.wheel_lock_deg()`: a wheel's is 120).
- **The hands**: a hand takes it by a GRIP, within `HELM_GRIP_ARC` (0.9 rad) of one by angle about the axle (`ArcadePanelHands.near_helm_grip`), never by the middle of the bar; the holding hand's **A / X is Lasers (button 2) and its B / Y Special Weapon
  (button 3)**, the buttons that are on the grips (`WheelGrab.bits`). The pointer shapes of a cockpit's yoke are its hub, its bar and a box round each grip (`_helm_shapes`), no rim.
- **The buttons**: the table's `u23` (`ArcadeGameProfile.used_buttons`, `button_visible`): caps `Btn2` (red) and `Btn3` (yellow) either side of the yoke's base on the stand-up's deck, on the dash to its right in the cockpit, and **no `Btn1`**: the panel has no
  cap for a button the game does not read.
- **One gas pedal** (`_pedals(..., gas_only)`), in the middle and as wide as the two were, and no brake; no gear lever.
- **The cockpit sets**: MAME's own descriptions name them ("Road Blasters (cockpit, rev 2)"): `roadblstc`, `roadblstc1` and `roadblstcg` are the seated cockpit (`COCKPIT_BY_DESC`), the other eight sets the stand-up. The sit-down cabinet's details (the seat's shape,
  "a plastic lens over the monitor that reads as about 25 inches", a three-board stack) are the research's (low) and not built beyond the standard seated cockpit.
- **Estimated**: the yoke's size and shape, its lock (the wiki and a forum thread say about 270; a 2003 poster argued 180), that its triggers and thumb switches are the two buttons (TopGear, medium) and where the caps stand (on the deck, not on the
  turning grips, so a fingertip and the panel's keys reach them as any cap; in a headset the grips' own A / X and B / Y are the same buttons). Not found: the cabinet's dimensions, panel, marquee, coin door and force feedback.
- Tests: `arcade_tests game/` (the table), `arcade_form_tests helm/` (the spec, the yoke, the one pedal, the buttons, the pointer shapes; Pole Position and Daytona keep their wheels), `arcade_hand_tests helm/ zone/` (taken by a grip and not by the top of
  its bar, 135 degrees is all the way and 120 is not, A / X and B / Y, let go). Picture `--forms=roadblst,roadblstc`.

### 9.2e Monitors that were never one flat picture (2026-10-27)

A player asked that the multi-screen cabinets have their monitors "placed and angled as the real ones": TX-1's three screens face the driver and are not "all flat in a row like a widescreen". Every multi-screen cabinet was
surveyed (no page could be opened: DNS and the proxy refused Wikipedia, Arcade Museum, Giant Bomb and the rest, so **every line below rests on search summaries**; **medium** = two or more independent summaries agree,
**low** = one summary, a store line, or sources in conflict; nothing reached high, because no flyer, manual or photograph was read).

| game(s) (romsets) | what the real cabinet had | confidence | what is built |
|---|---|---|---|
| TX-1 (`tx1`, `tx1jb`, `tx1jc`; Tatsumi, 1983) | three monitors side by side, the main one ahead of the wheel, **the two side ones tilted 30 degrees** (which way is not said), the left for score and position, the right counting cars passed | three screens medium, 30 degrees low | **a bank**: the centre square, the wings turned in 30 degrees (below) |
| Buggy Boy / Speed Buggy (`buggyboy`, `buggyboyb`; Tatsumi, 1985) | the cockpit: three screens as one panorama (the Junior, `buggyboyjr`, is a one-screen upright) | medium (the Junior: low) | the same bank; MAME's "(cockpit)" sets are the sit-down cockpit now (they were drawn as an upright with a wide glass) |
| Race Drivin' Panorama (`racedrivpan`; Atari, 1990) | MAME gives it three screens, the middle one FIRST (`c4.03,0,4,3/0,0,4,3/8.06,0,4,3`) | MAME's layout; the cabinet's angles were not researched | the same bank, the parts sorted left to right |
| Driver's Eyes (`driveyes`; Namco, 1990) | three CRTs "for a pseudo-panoramic view", three System 21 boards | three screens medium; angles not found | the same bank (a three-screen driving cockpit with its side monitors flat would show them at a slant to the driver: assumed, as for TX-1) |
| Darius, Darius II / Sagaia (`darius`, `darius2`; Taito) | three CRTs, the centre one behind a half-silvered mirror facing the seat, the outer two low and tipped up into the glass: **one wide, continuous picture** | medium for Darius, low for Darius II | one wide glass (the mirror is what makes the picture one), a bench in front (2b) |
| Ninja Warriors (`ninjaw`; Taito) | a centre screen, two more low in the cabinet, their images mirrored out to each side | medium | one wide glass, as Darius |
| Warrior Blade (`warriorb`; Taito) | "dual-screen", from publisher listings only | low | a wide pair |
| Run and Gun (`rungun`, `rungun2`; Konami, 1993) | two monitors, each covering one end of the court (Run and Gun 2 with two screens: not found) | medium | a wide pair on a body that grows to hold four players |
| Cyberball (`cyberbal`; Atari, 1988) | two monitors in one large cabinet, two control sets per screen; the four-player Cyberball 2072 is dual-monitor, "tilted about 45 degrees with a strip between" (one unattributed summary) | medium; the tilt: low | a wide pair; **the 45 degrees is not built** |
| Subs (1979), Cyber Tank (`cybertnk`) | two monitors, one a player (Cyber Tank never shipped: low) | low | a wide pair; angles: not found |
| PlayChoice-10 (`pc_*`), Punch-Out!! (`punchout`), Super Punch-Out!!, Arm Wrestling, Mega-Tech (`mt_*`) | two screens one over the other: the upper for menus, stats and portraits, the lower the play | medium | a portrait pair in the tall body |
| Vs. DualSystem, Keyboardmania (`kbm`), F1 Exhaust Note, Outrunners (`orunners`), Air Rescue | two screens, one a player (Vs. DualSystem: a separate game on each) | medium to low | a wide pair (Keyboardmania's are portrait: the tate pair) |
| Silent Scope | the second screen is the scope's LCD | medium | in the rifle's eyepiece (`arcade.md` "Several screens") |
| X-Men (`xmen6p`) | "a lower screen with a mirror that widened the picture" (Kotaku), "side by side" (Hardcore Gaming 101): in conflict | conflict | a wide pair on a six-player body |

Not found for any of them: a monitor size, a mirror's position, an angle other than TX-1's. **A bank is built for the four driving cockpits and for nothing else**: a flat pair or an over-under pair that the sources
do not say was angled is drawn flat.

**How it is drawn** (`ArcadeCabinetSpecs.bank_layout`, `ArcadeCabinetBuilder._build_monitor`, `ArcadeScreenModule`; `arcade.md` "Several screens"): three quads in the monitor's own frame, each as tall as the tube and as wide as its
part of MAME's frame is in the frame's shape (4:3 for three equal thirds: 0.48 x 0.36 m in the cockpit's 1.44 m tube); the centre `CabinetScreen` square to the glass, `CabinetScreenL` and `CabinetScreenR` hinged on its edges and
turned `BANK_YAW_DEG` = 30 degrees toward the player, so the centre is set back 0.19 m and the outer edges stand on the glass's plane (`bank_layout`'s `set_back` and `span`; 1.30 m of the cockpit's 1.49 m window). A dark
case stands behind each along its own normal (`BankCase1..3`). The table says which games are banks (`dfan`, `BANK` in `gen_game_index.py`; the profile's `bank_style()`, `bank_parts()`) and the screen module lights the wings only
while the core's frame is the shape the table expects. **Estimated**: the 30 degrees and that they turn IN (a bank that wraps round the driver), the set-back it implies, the case's depth, and that Race Drivin' Panorama and Driver's
Eyes stood as TX-1's do (no source says they did). **OWED**: a real run (no core or ROM was at hand: the pictures are test cards), a headset to judge the angle from the seat, the Quest's cost of two more textured quads.
Tests: `arcade_form_tests bank/` (the layout's invariants for any yaw and for unequal parts, the spec for each set, the build with its cases behind the pictures, the screen module's every state), `arcade_tests game/` (the table and
the profile). Picture `--forms=tx1,buggyboy,racedrivpan,driveyes` (a frame of three coloured test cards, one number of bars each).

### 9.3 What the audit made worth building

Beyond the data faults of 9.1, the audit found games whose hardware was nothing like a stick and buttons. Each got a form or a part of its own; the section named has the research, the
estimates and the tests.

| the games (names of the 143) | what they really had | what is built now | where |
|---|---|---|---|
| DDR Solo (4) | a six-panel stage | the stage's two extra panels, MAME's buttons 3 and 4 | 9.2 |
| beatmania, pop'n music, GuitarFreaks, DrumMania, Taiko, Mambo a Go-Go (15) | a turntable and keys, nine domes, a guitar, a drum kit, a drum, three congas | a controller of its own for each, found by the same part names, with ten buttons a panel | 2c |
| Top Gunner (bootleg), Zwackery, Tron | a stick that also twists, or a dial beside it | the rotary stick | 2d |
| Star Wars, Red Baron, Bass Fishing | a flight yoke, a rod with a reel | a yoke, a rod with its reel and crank | 2e |
| Top Skater, Alpine Surfer | a board the rider stands on and leans | a stand, a rocking plate, a skateboard or a snowboard, a rail | 2f |
| `r360`: G-LOC R360, Wing War R360 (1) | a sphere cockpit in two rings | the rings round the cockpit | 2b |
| Darius, Darius II, Star Wars Arcade | a bench to sit on in front of the screen | a bench of two seats (and Star Wars Arcade's 50 inch class screen) | 2b |
| Lucky & Wild | a driver and a gunner | a two-seat cockpit | 2 |

Not built, and why each is a different kind of limit: the pilot's throttle of Star Wars Arcade and the real mechanisms of the board games (**unknown**: nothing found), OutRun 2's twin
seats and Wacko's second control (**work**: a second seat, a panel of a stick and a ball), the sit-down versions of the older cabinets (**evidence**: one article each; Road Blasters' yoke is built since, 9.2d),
jubeat, `lamborcc` and `interstellar` (**not MAME**).

### 9.4 The verdict, game by game

One row for each of the 143 names the player listed, in the order they were listed; **what spawns** is read from the real spec by `ArcadeCabinetSpecs.for_game` (a probe run on the committed
table), the game's line from MAME 0.289, and the **verdict** is a judgement against the research notes (every one a search summary: no photograph of any real cabinet was ever opened):

- **built**: spawns with the hardware the research and MAME give it (the note says what is estimated or left out);
- **upright**: the real cabinet was a plain upright with a panel like this one, so a plain upright is right;
- **approximate**: spawns with something near it; the note says what is missing, unknown or in dispute;
- **none**: the name is not a MAME romset, so nothing is built.

| asked | MAME's game (year, maker, driver status) | what spawns | verdict |
|---|---|---|---|
| `ddr2m` | Dance Dance Revolution 2nd Mix (GN895 VER. JAA) (1999, Konami, imperfect) | dance stage, two dancers, 4-arrow panels | **built**: the standard two-player cabinet: a pad each (a 3x3 grid, four arrows on the edge cells: the cells are inferred, medium) |
| `ddr3mk` | Dance Dance Revolution 3rd Mix - Ver.Korea2 (GN887 VER. KBA) (2000, Konami, preliminary) | dance stage, two dancers, 4-arrow panels | **built**: the same |
| `ddr3mp` | Dance Dance Revolution 3rd Mix Plus (G*A22 VER. JAA) (2000, Konami, preliminary) | dance stage, two dancers, 4-arrow panels | **built**: the same |
| `ddr4m` | Dance Dance Revolution 4th Mix (G*A33 VER. AAA) (2000, Konami, preliminary) | dance stage, two dancers, 4-arrow panels | **built**: the same |
| `ddr4mp` | Dance Dance Revolution 4th Mix Plus (G*A34 VER. JAA) (2000, Konami, preliminary) | dance stage, two dancers, 4-arrow panels | **built**: the same |
| `ddr4mps` | Dance Dance Revolution 4th Mix Plus Solo (G*A34 VER. JBA) (2000, Konami, preliminary) | dance stage, one dancer, 6-arrow panels | **built**: Solo's six panels (up-left and up-right are MAME's buttons 3 and 4; where the real corners were is inferred, low) |
| `ddr4ms` | Dance Dance Revolution 4th Mix Solo (G*A33 VER. ABA) (2000, Konami, preliminary) | dance stage, one dancer, 6-arrow panels | **built**: the same |
| `ddr5m` | Dance Dance Revolution 5th Mix (G*A27 VER. JAA) (2001, Konami, preliminary) | dance stage, two dancers, 4-arrow panels | **built**: the standard two-player cabinet: a pad each (a 3x3 grid, four arrows on the edge cells: the cells are inferred, medium) |
| `ddrextrm` | Dance Dance Revolution Extreme (G*C36 VER. JAA) (2002, Konami, preliminary) | dance stage, two dancers, 4-arrow panels | **built**: the same |
| `ddrkara` | Dance Dance Revolution Karaoke Mix (GQ921 VER. JBB) (1999, Konami, preliminary) | dance stage, one dancer, 4-arrow panels | **approximate**: one pad (MAME: one player); no page on the Karaoke Mix cabinet came back, so a karaoke screen or microphone is not drawn |
| `ddrkara2` | Dance Dance Revolution Karaoke Mix 2 (GQ947 VER. JAA) (2000, Konami, preliminary) | dance stage, one dancer, 4-arrow panels | **approximate**: one pad (MAME: one player); nothing found on the cabinet |
| `ddrkids` | Dance Dance Revolution Kids (GQAN4 JAA) (2000, Konami, imperfect) | dance stage, one dancer, 4-arrow panels | **approximate**: one pad (MAME: one player, Konami GS hardware); nothing found on a Kids cabinet |
| `ddrmax` | DDRMAX - Dance Dance Revolution 6th Mix (G*B19 VER. JAA) (2001, Konami, preliminary) | dance stage, two dancers, 4-arrow panels | **built**: the standard two-player cabinet: a pad each (a 3x3 grid, four arrows on the edge cells: the cells are inferred, medium) |
| `ddrmax2` | DDRMAX2 - Dance Dance Revolution 7th Mix (G*B20 VER. JAA) (2002, Konami, preliminary) | dance stage, two dancers, 4-arrow panels | **built**: the same |
| `ddrs2k` | Dance Dance Revolution Solo 2000 (GC905 VER. AAA) (1999, Konami, preliminary) | dance stage, one dancer, 6-arrow panels | **built**: Solo's six panels (up-left and up-right are MAME's buttons 3 and 4; where the real corners were is inferred, low) |
| `ddrsbm` | Dance Dance Revolution Solo Bass Mix (GQ894 VER. JAA) (1999, Konami, preliminary) | dance stage, one dancer, 6-arrow panels | **built**: the same |
| `ddrusa` | Dance Dance Revolution USA (G*A44 VER. UAA) (2000, Konami, preliminary) | dance stage, two dancers, 4-arrow panels | **built**: the standard two-player cabinet: a pad each (a 3x3 grid, four arrows on the edge cells: the cells are inferred, medium) |
| `aircomb` | Air Combat (AC2, US) (1992, Namco, imperfect) | flight cockpit: seat, stick, throttle, cabin | **built**: DIP "Cockpit": a full-size cockpit with a rumbling seat that does not move (research, low-medium); the throttle is MAME's own Z axis |
| `airco22b` | Air Combat 22 (Japan, ACS1 Ver.B) (1995, Namco, imperfect) | flight cockpit: seat, stick, throttle, cabin | **built**: the same cockpit ("authentic cockpit", low); a throttle lever (one listing, low) |
| `topgunbl` | Top Gunner (bootleg, Rotary Joystick) (1986, bootleg, good) | upright; 2 x rotary stick, 2 buttons; tate body, monitor on its side | **built**: a bootleg of Konami's Jackal (Top Gunner) whose set is named for its rotary joystick: a stick that also twists, built as the rotary stick (2d); which control it really used is not established (low) |
| `mach3` | M.A.C.H. 3 (set 1) (1983, Mylstar, good) | upright; stick, 2 buttons; 19" class | **upright**: an 8-way stick with a trigger and a thumb button (medium); a rarer sit-down "environmental" cabinet with a Fresnel lens existed and is not built |
| `thndrbld` | Thunder Blade (upright) (FD1094 317-0056) (1987, Sega, good) | flight cockpit: seat, stick, throttle, moving base | **built**: DIP "Deluxe": a helicopter chair on a base that follows the stick, no cabin (research, one source); the throttle is the game's own Z axis |
| `gforce2` | Galaxy Force 2 (1988, Sega, good) | flight cockpit: seat, stick, throttle, cabin, moving base | **built**: DIP "Super Deluxe / Deluxe": cabinet, seat and screen move together (research) |
| `aburner` | After Burner (VER 1.32, deluxe/upright) (1987, Sega, good) | flight cockpit: seat, stick, cabin, moving base | **built**: DIP "Moving Deluxe": an enclosed cockpit with the seat on a moving base; the first game has no throttle |
| `aburner2` | After Burner II (VER 2.00, deluxe/upright) (1987, Sega, good) | flight cockpit: seat, stick, throttle, cabin, moving base | **built**: the same cockpit with the throttle lever the second game added (DIP "Throttle Lever") |
| `outr2` | OutRun 2 (Rev A) (GDX-0004A) (2003, Sega, preliminary) | driving cockpit: seat, wheel, 2 pedals | **approximate**: OutRun 2 (Chihiro): one seat, wheel and two pedals. The real deluxe seats TWO side by side, each with their own controls (low-medium) and has a shifter (not found for this game): neither is built; no moving base |
| `outrun` | Out Run (sitdown/upright, Rev B) (1986, Sega, good) | driving cockpit: seat, wheel, 2 pedals, gear lever, moving base | **built**: sit-down: wheel, two pedals, the Low/High lever (button 3, a toggle) and a base that moves (DIP "Moving"); the deluxe seat also slid with the steering (medium), not built |
| `outr2st` | OutRun 2 Special Tours (Rev A) (GDX-0014A) (2004, Sega, preliminary) | driving cockpit: seat, wheel, 2 pedals | **approximate**: OutRun 2 Special Tours: the same one-seat cockpit; the twin and the real motion are not built |
| `lamborcc` | not a MAME romset | - | **none**: no MAME romset of this name and no Lamborghini coin-op was found (the closest are home games: Lamborghini American Challenge, from Crazy Cars III, Titus 1992, and Automobili Lamborghini, N64); nothing to spawn |
| `r360` (= `glocr360`, `wingwar360`) | G-LOC R360 (World) (1990, Sega, good) | glocr360: flight cockpit: seat, stick, R-360 rings, moving base / wingwar360: flight cockpit: seat, stick, R-360 rings, moving base; 2 screens | **built**: Sega's R-360 pod: a seat inside rings that turn about two axes (research); stick, no throttle; the pod's real harness and safety bar are not built |
| `swa` | Star Wars (Sega, US) (1994, Sega, imperfect) | upright; 2 x stick, 3 buttons; bench of 2 seats; tall body, 50" class | **approximate**: Sega's Star Wars Arcade: two seats (a pilot and a gunner) and a stick each with a trigger and a thumb button (research, medium): built as a bench of two seats at a deck with two sticks, a 50 inch class screen; the pilot's throttle is not drawn and the stick was found on the deck, not between the knees |
| `bm2nd` (= `bm2ndmix`) | beatmania 2nd MIX (ver JA-B) (1998, Konami, imperfect) | rhythm controller: 2 x deck controller; tall body, 34" class | **built**: a deck a player: a turntable and five keys (MAME's five buttons); IIDX's seven keys is another game |
| `bm2ndm` (= `bm2ndmixa`) | beatmania 2nd MIX (ver JA-A) (1998, Konami, imperfect) | rhythm controller: 2 x deck controller; tall body, 34" class | **built**: the same |
| `bm4th` (= `bm4thmix`) | beatmania 4th MIX (ver JA-A) (1999, Konami, imperfect) | rhythm controller: 2 x deck controller; tall body, 34" class | **built**: the same |
| `bm5th` (= `bm5thmix`) | beatmania 5th MIX (ver JA-A) (1999, Konami, imperfect) | rhythm controller: 2 x deck controller; tall body, 34" class | **built**: the same |
| `bm6th` (= `bm6thmix`) | beatmania 6th MIX (ver JA-A) (2001, Konami, imperfect) | rhythm controller: 2 x deck controller; tall body, 34" class | **built**: the same |
| `bmcompm` (= `bmcompmx`, `bmcompm2`) | beatmania complete MIX (ver JA-C) (1999, Konami, imperfect) | rhythm controller: 2 x deck controller; tall body, 34" class | **built**: the same |
| `taiko10` | Taiko no Tatsujin 10 (T101001-NA-A) (2007, Namco, preliminary) | rhythm controller: 2 x taiko controller; tall body, 26" class | **built**: a Taiko drum a player: four zones (rim and surface, left and right), MAME's own names, and a pair of drumsticks on cords in cradles beside it; how the two drums stood is not found (low) |
| `taiko6` | Taiko no Tatsujin 6 (Japan, TK61 Ver.A) (2004, Namco, preliminary) | rhythm controller: 2 x taiko controller; tall body, 26" class | **built**: the same |
| `taiko7` | Taiko no Tatsujin 7 (TK71-NA-A) (2005, Namco, preliminary) | rhythm controller: 2 x taiko controller; tall body, 26" class | **built**: a Taiko drum a player: four zones (rim and surface, left and right), MAME's own names, and a pair of drumsticks on cords in cradles beside it; how the two drums stood is not found (low); Namco System 246: the driver declares no controls, the cabinet is a drum a player, two players |
| `taiko8` | Taiko no Tatsujin 8 (TK8100-1-NA-A) (2006, Namco, preliminary) | rhythm controller: 2 x taiko controller; tall body, 26" class | **built**: a Taiko drum a player: four zones (rim and surface, left and right), MAME's own names, and a pair of drumsticks on cords in cradles beside it; how the two drums stood is not found (low) |
| `taiko9` | Taiko no Tatsujin 9 (TK91001-NA-A) (2006, Namco, preliminary) | rhythm controller: 2 x taiko controller; tall body, 26" class | **built**: the same |
| `bass` (= `bassdx`) | Sega Bass Fishing Deluxe (1997, Sega, preliminary) | upright; rod, 2 buttons | **approximate**: Sega Bass Fishing Deluxe: a rod with a reel and its crank on an upright; how the rod stood on the real cabinet is not found (a swivel? a boat?), and a sit-down candy model is mentioned (conflict) |
| `guitarfr` (= `gtrfrks`) | Guitar Freaks Ver 1.01 (GQ886 VER. EAD) (1999, Konami, imperfect) | rhythm controller: 2 x guitar controller; tall body, 32" class | **built**: a guitar a player: three frets, a pick bar, a wail button and the effect knob |
| `drummania` (= `drmn`) | DrumMania (GQ881 VER. JAD) (1999, Konami, preliminary) | rhythm controller: drums controller; tall body, 26" class | **built**: five pads in an arc and the bass drum's pedal on the floor |
| `popn` (= `popn1`) | Pop'n Music (ver TA-A, HDD 1.01) (1998, Konami, imperfect) | rhythm controller: popn controller | **built**: nine domes in two rows (white, yellow, green, blue, red, blue, green, yellow, white), one player |
| `jubeat` | not a MAME romset | - | **none**: no MAME driver: jubeat's 4x4 grid of touch panels (research, medium) is a controller of its own that nothing builds |
| `mamboagg` | Mambo A Go-Go (GQA40 VER. JAB) (2001, Konami, preliminary) | rhythm controller: conga controller | **built**: three drums of three pads each (Mambo a Go-Go's congas) |
| `kickgoal` | Kick Goal (set 1) (1995, TCH / Proyesel, good) | upright; 2 x stick, 3 buttons | **upright**: TCH's Kick Goal (1995), a side-view futsal game: two players, an 8-way stick and three buttons each in the driver (MAME source); an ordinary upright is inferred (low) |
| `wcombat` | World Combat (ver AAD:B) (2002, Konami, preliminary) | 2 guns in holsters | **built**: Konami's World Combat / Warzaid (Viper, 2002): one optical light gun a player, one trigger each (MAME source): two guns in holsters and no pedal (players take cover by aiming off screen); MAME lists the 4P sets as two buttons only because the gun axes are undefined (all four sets are NOT_WORKING); the 4P is two networked PCBs |
| `topskatr` | Top Skater (Export, Revision A) (1997, Sega, preliminary) | standing rider: skateboard on a rocking plate, rail round the front; wide body | **built**: Sega's Top Skater: a skateboard-style deck that pivots or tilts (three axes, medium), handrails each side (medium-low), a 50 inch screen with two speakers at the rider: the deck rocks on a plate (one axis), the rail leans with it (2f) |
| `darius` | Darius (World, rev 2) (1986, Taito, good) | upright; 2 x stick, 2 buttons; bench of 2 seats; 3 screens | **built**: three screens (centre faces the player, the outer two low and angled behind a half mirror: here side by side) and a bench-style seat with Body Sonic (research, one chain): a bench of two seats, a stick each |
| `darius2` | Darius II (triple screen) (Japan, rev 1) (1989, Taito, imperfect) | upright; 2 x stick, 2 buttons; bench of 2 seats; 3 screens | **built**: the same cabinet design; MAME's "triple screen" set |
| `dariusg` | Darius Gaiden - Silver Hawk (Ver 2.5O 1994/09/19) (1994, Taito, imperfect) | upright; 2 x stick, 4 buttons; 26" class | **upright**: an F3 two-player upright with one screen (the F3 board's four players are not the cabinet's) |
| `ninjaw` | The Ninja Warriors (World, later version) (1987, Taito, imperfect) | upright; 2 x stick, 2 buttons; 3 screens | **built**: three screens in an upright; players stand (the upright listings say standing, one review sit-down: conflict) |
| `tx1` | TX-1 (World) (1983, Tatsumi, imperfect) | driving cockpit: seat, wheel, 2 pedals; 3 screens | **approximate**: Tatsumi's TX-1: a seated cockpit with three screens (the main ahead of the wheel, two tilted 30 degrees: here all in one frame), a force-feedback wheel, a throttle, a brake and a gearshift (medium): the gearshift is not drawn |
| `warpspd` (= `warpsped`) | Warp Speed (prototype) (1979?, Meadows Games, Inc., preliminary) | upright; stick, 2 buttons; 19" class | **upright**: a 1979 prototype by Meadows Games: an upright with a stick (the sources disagree on what the game is) |
| `sidebs` | Side by Side (Ver 3.0 OK) (1996, Taito, imperfect) | driving cockpit: seat, wheel, 2 pedals | **built**: Taito's Side by Side: a sit-down racer, optionally linked in pairs, wheel and pedals (a force-feedback wheel in the hc11 output, low-medium); the sequential shift is the JOYSTICK's up and down in MAME (not a button), so no lever is drawn |
| `timetrv` | Time Traveler (1991, Virtual Image Productions, good) | hologram stage 0.30 m deep behind the glass, 1 panel | **built**: Virtual Image's Time Traveler: the upright's picture standing 0.30 m deep in a black stage (2) |
| `kurikint` | Kuri Kinton (World) (1988, Taito, good) | upright; stick, 2 buttons; START | **upright**: Taito L: an alternating upright, one panel, a 1P and a 2P START |
| `panicprk` | Panic Park (World, PNP2 Ver. A) (1997, Namco, preliminary) | two levers in one slot; tall body, 33" class | **built**: Namco's Panic Park: two levers in one slot, a 33 inch class screen (2) |
| `sscope` | Silent Scope (ver UAD, Ver 1.33) (1999, Konami, preliminary) | 1 gun rifle on a post, scope; scope screen in the rifle | **built**: Silent Scope: a rifle on a post with a scope that shows the second screen (2) |
| `sscope2` | Silent Scope 2 : Dark Silhouette (ver UAD, Ver 1.03) (2000, Konami, preliminary) | 1 gun rifle on a post, scope; scope screen in the rifle | **built**: Silent Scope 2: the same |
| `propcycl` | Prop Cycle (World, PR2 Ver.A) (1996, Namco, imperfect) | bicycle (bars, crank, saddle); wide body | **built**: Namco's Prop Cycle: a bicycle with bars, a crank and a saddle (2) |
| `finalap3` | Final Lap 3 (World, Rev C) (1992, Namco, imperfect) | driving cockpit: seat, wheel, 2 pedals, gear lever | **built**: Namco's Final Lap 3 (System 2): a sit-down cockpit with a gear lever (the table's button 1, a toggle) (2) |
| `manxtt` | Manx TT Superbike - DX/Twin (Revision D) (1995, Sega, preliminary) | ride-on motorbike (leans, saddle is a seat) | **built**: Sega's Manx TT Superbike DX/Twin: a motorbike you straddle, that leans (the seat is inferred, medium-low) |
| `hangon` | Hang-On (Rev A) (1985, Sega, good) | ride-on motorbike (leans, saddle is a seat) | **built**: Sega's Hang-On: a motorbike you straddle (which cabinet has the throttle and brake is in dispute) |
| `radikalb` | Radikal Bikers (version 2.02) (1998, Gaelco, imperfect) | ride-on motorbike (leans, saddle is a seat) | **approximate**: Gaelco's Radikal Bikers: a motorbike (research: a handlebar panel with throttle and brake, or a 2-way stick with a paddle: conflict; whether the rider sat is not found) |
| `alpinesa` (= `alpines`) | Alpine Surfer (World, AF2 Ver.A) (1996, Namco, imperfect) | standing rider: snowboard on a rocking plate, rail round the front; wide body | **built**: Namco's Alpine Surfer: a snowboard-style platform with two large handlebars, edge pressure sets the speed (medium-low); the separate monitor unit is not built (2f) |
| `cybrcycc` | Cyber Cycles (World, CB2 Ver.C) (1995, Namco, imperfect) | ride-on motorbike (leans, saddle is a seat) | **built**: Namco's Cyber Cycles: a motorbike you sit on (seated, medium) |
| `motoxgo` | Motocross Go! (World, MG3 Ver. A) (1997, Namco, preliminary) | ride-on motorbike (leans, saddle is a seat) | **approximate**: Namco's Motocross Go!: a motorbike; whether the bike swivelled and whether the rider sat are not found |
| `raveracw` (= `raverace`) | Rave Racer (World, RV2 Ver.B) (1995, Namco, imperfect) | driving cockpit: seat, wheel, 2 pedals | **built**: Namco's Rave Racer (System 22): a sit-down cockpit, wheel and pedals |
| `harley` | Harley-Davidson and L.A. Riders (Revision B) (1997, Sega, preliminary) | ride-on motorbike (leans, saddle is a seat) | **built**: Sega's Harley-Davidson and L.A. Riders: a motorcycle seat and bars (research) |
| `daytona` | Daytona USA (Revision A) (1994, Sega, imperfect) | driving cockpit: seat, wheel, 2 pedals | **built**: Sega's Daytona USA (Model 2): a sit-down cockpit; the four-speed lever is an H pattern (the table lists five "gears" buttons), which a two-position lever cannot show, so none is drawn |
| `daytona2` | Daytona USA 2: Battle on the Edge (Revision A) (1998, Sega, preliminary) | driving cockpit: seat, wheel, 2 pedals, roof | **built**: Daytona USA 2 (Model 3): the Model 3 twins' roof over the seat |
| `scud` | Scud Race / Sega Super GT - Twin/DX (1996, Sega, preliminary) | driving cockpit: seat, wheel, 2 pedals, roof | **built**: Scud Race / Super GT Twin/DX: a sit-down cockpit with the overhead marquee of the Model 3 twins |
| `scudplus` | Scud Race Plus / Sega Super GT Plus - Twin/DX (Revision A) (1997, Sega, preliminary) | driving cockpit: seat, wheel, 2 pedals, roof | **built**: the same |
| `f1lap` | F1 Super Lap (World) (1993, Sega, imperfect) | driving cockpit: seat, wheel, 2 pedals, gear lever | **built**: Sega's F1 Super Lap: a sit-down cockpit with a sequential shifter (up on button 1, down on 2) |
| `f1en` | F1 Exhaust Note (World, Rev A) (1991, Sega, imperfect) | driving cockpit: seat, wheel, 2 pedals, gear lever; 2 screens | **built**: Sega's F1 Exhaust Note: a sit-down cockpit with a sequential shifter and MAME's two screens (a twin/deluxe unit's) |
| `dirtdash` | Dirt Dash (World, DT2 Ver.C) (1995, Namco, imperfect) | driving cockpit: seat, wheel, 2 pedals | **built**: Namco's Dirt Dash (System 22): a sit-down cockpit (unverified: nothing was found on the cabinet) |
| `racedriv` | Race Drivin' (cockpit, rev 5) (1990, Atari Games, good) | driving cockpit: seat, wheel, 2 pedals | **built**: Atari's Race Drivin': a sit-down cockpit; the stick shift and clutch (an H pattern) are not drawn |
| `harddriv` | Hard Drivin' (cockpit, rev 7) (1988, Atari Games, good) | driving cockpit: seat, wheel, 2 pedals | **built**: Atari's Hard Drivin': a sit-down cockpit; the stick shift and clutch are not drawn |
| `wecleman` | WEC Le Mans 24 (v2.01) (1986, Konami, good) | stand-up driving cabinet: wheel on the panel, gear lever, pedals on the floor | **approximate**: Konami's WEC Le Mans 24: the standard upright (a force-feedback wheel, two pedals); the mini sit-down cockpit and the deluxe Big Spin (it turned on a spindle with the wheel) are not built; the lever is MAME's Hi/Lo button (the KLOV control list has no shifter: low) |
| `turbo` | Turbo (program 1513-1515) (1981, Sega, imperfect) | stand-up driving cabinet: wheel on the panel, gear lever, pedals on the floor; tate body, monitor on its side, 19" class | **built**: Sega's Turbo (1981): the upright's 360 degree wheel, a Hi/Lo shifter (high confidence), one gas pedal (two are drawn); the sit-down and the cabaret are not built |
| `chasehq` | Chase H.Q. (World) (1988, Taito, imperfect) | stand-up driving cabinet: wheel on the panel, gear lever, pedals on the floor | **built**: Taito's Chase H.Q.: the standard upright, a wheel, one pedal, a two-position shifter with a button and a turbo button at the side (low-medium); whether a sit-down existed is disputed and is not built |
| `contcirc` | Continental Circus (World) (1987, Taito, imperfect) | driving cockpit: seat, wheel, 2 pedals, gear lever | **approximate**: Taito's Continental Circus: a sit-down cockpit with MAME's gear button as a lever; an upright existed too and the shutter 3D glasses are not built; no physical control description was found |
| `radm` | Rad Mobile (World) (1990, Sega, imperfect) | driving cockpit: seat, wheel, 2 pedals | **built**: Sega's Rad Mobile: a sit-down cockpit (no shifter found) |
| `slipstrm` | Slip Stream (Brazil 950515) (1995, Capcom, imperfect) | driving cockpit: seat, wheel, 2 pedals, gear lever | **built**: Capcom's Slip Stream (Sega System 32): a sit-down cockpit with a one-button toggle lever |
| `luckywld` | Lucky & Wild (1992, Namco, good) | two-seat cockpit: driver's wheel and pedal, a gun each, gunner's START; 25" class | **built**: Namco's Lucky & Wild: a driver's wheel and pedal and a gun each (a two-seat cockpit) |
| `policetr` | Police Trainer (Rev 1.3B, Rev 0.3 PCB) (1996, P&P Marketing, good) | 2 guns in holsters | **approximate**: Police Trainer: two guns in holsters (MAME: two light guns); nothing was found on the cabinet |
| `revx` | Revolution X (revision 2.0 9/8/94) (1994, Midway, good) | 3 guns on swivel posts | **approximate**: Revolution X: three controllers on posts (research: heavy, fixed to the panel and used like joysticks, or a mounted light gun: conflict) |
| `opwolf` | Operation Wolf (World, rev 2, set 1) (1987, Taito, imperfect) | 1 gun on swivel posts | **built**: Operation Wolf: one Uzi-style machine gun on a pivoting mount (medium); the grenade button near the barrel is not drawn |
| `opwolf3` | Operation Wolf 3 (World) (1994, Taito, good) | 2 guns in holsters | **approximate**: Operation Wolf 3: two guns in holsters; the real guns were "a completely different design" with a pump slide under the barrel (low): not drawn |
| `opwolf3u` | Operation Wolf 3 (US) (1994, Taito America, good) | 2 guns in holsters | **approximate**: the same set (US) |
| `othunder` | Operation Thunderbolt (World, rev 1) (1988, Taito, good) | 2 guns on swivel posts | **built**: Operation Thunderbolt: two positional guns on posts (a trigger and two buttons each); the recoil kickers are not drawn |
| `rchase` | Rail Chase (World) (1991, Sega, good) | 2 fixed joystick-like guns; bench of 2 seats that moves | **built**: Sega's Rail Chase: a bench of two seats that pitches with the ride (DIP "Moving"; here it stands still), two guns fixed on posts shaped as joysticks (9.2c; they were pistols in holsters) |
| `rchase2` | Rail Chase 2 (Revision A) (1994, Sega, imperfect) | 2 fixed joystick-like guns; bench of 2 seats that moves | **approximate**: Rail Chase 2: the same bench and the same joystick-like guns on posts (9.2c); the cabinet was not found |
| `timecris` | Time Crisis (World, TS2 Ver.B) (1996, Namco, imperfect) | 1 gun in holsters, foot pedal | **built**: Time Crisis: one gun with force feedback and ONE foot pedal (cover and reload) |
| `timecrs2` | Time Crisis II (US, TSS3 Ver. B) (1997, Namco, preliminary) | 1 gun in holsters, foot pedal | **built**: Time Crisis II: one gun and one pedal each; the second player is a second linked cabinet |
| `crszone` | Crisis Zone (World, CSZO4 Ver. B) (1999, Namco, preliminary) | 1 gun in holsters, foot pedal | **built**: Crisis Zone: one gun and one pedal |
| `lethalen` | Lethal Enforcers (ver UAE, 11/19/92 15:04) (1992, Konami, imperfect) | 2 guns in holsters | **built**: Konami's Lethal Enforcers: two revolver-shaped guns |
| `gunbulet` (= `gunbuletw`, `gunbuletj`) | Gun Bullet (World, GN3 Rev B) (1994, Namco, good) | 2 guns in holsters | **built**: Namco's Gun Bullet (Point Blank): two guns with recoil |
| `g13knd` | Golgo 13 Kiseki no Dandou (Japan, GLS1/VER.A) (2000, Eighting / Raizing / Namco, imperfect) | 1 gun rifle on a post, scope; scope screen in the rifle | **approximate**: Golgo 13: a rifle with a scope; the match with the romset is unverified (low) |
| `alien3` | Alien3: The Gun (World) (1993, Sega, imperfect) | 2 guns on swivel posts | **built**: Sega's Alien3: The Gun: replica pulse rifles mounted in the cabinet, one a player |
| `jurassicp` (= `jpark`) | Jurassic Park (World, Rev A) (1993, Sega, imperfect) | 2 guns on swivel posts; bench of 2 seats that moves | **approximate**: Sega's Jurassic Park: two guns on posts and a bench that moves in the sit-down version (low: controls conflict between light guns and joysticks) |
| `undrfire` | Under Fire (World) (1993, Taito, imperfect) | 2 guns in holsters | **built**: Taito's Under Fire: two guns with force feedback on the trigger |
| `gunbustr` | Gunbuster (World) (1992, Taito, imperfect) | 2 fixed guns, a stick station each | **built**: Taito's Gunbuster: two stations, each a pistol fixed on a post and a stick with two buttons (a joystick walks and the gun aims); MAME has two stations and a link device, four players being two cabinets linked, which is not built (9.2c) |
| `spacegun` | Space Gun (World) (1990, Taito, good) | 2 guns on swivel posts | **built**: Taito's Space Gun: two positional guns on posts; the pump control and the recoil are not drawn |
| `zeropnt` | Zero Point (set 1) (1998, Unico, good) | 2 guns in holsters | **approximate**: Unico's Zero Point: two guns in holsters; nothing was found on the cabinet |
| `lghost` | Laser Ghost (World) (FD1094 317-0166) (1990, Sega, good) | 3 fixed blasters | **built**: Sega's Laser Ghost: three big blasters fixed on posts (up to three players), a fire and a special-weapon cap each, the laser imaging unit on top (9.2c: the shape is an estimate) |
| `dlair` | Dragon's Lair (US Rev. F2) (1983, Cinematronics, good) | upright; stick, 1 button; 19" class | **upright**: Dragon's Lair: an upright, one stick and one button (a Pioneer laserdisc player behind it) |
| `cliffhgr` | Cliff Hanger (set 1) (1983, Stern Electronics, good) | upright; 2 x stick, 2 buttons; 19" class | **upright**: Cliff Hanger: an upright, a stick and two buttons a player |
| `usvsthem` | Us vs. Them (1984, Mylstar, good) | upright; stick, 3 buttons; 19" class | **upright**: Us vs. Them (1984): an upright, a conversion of M.A.C.H. 3's cabinet |
| `badlands` | Bad Lands (1989, Atari Games, good) | upright; 2 x wheel, 2 buttons; tall body, 31" class | **built**: Atari Games' Bad Lands: a wheel for each of two players, no pedals (MAME calls the wheel a dial; the wheels turn all the way round: one owner's account) |
| `cobram3` | Cobra Command (M.A.C.H. 3 hardware, set 1) (1984, Data East, good) | upright; stick, 2 buttons; 19" class | **upright**: Data East's Cobra Command (M.A.C.H. 3 hardware, 1984): an upright with an optical stick and two buttons (fire and missile) |
| `interstellar` (= `istellar`) | Inter Stellar (Laser Fantasy) (1983, Funai/Gakken, preliminary) | upright; stick, 2 buttons; 19" class | **upright**: Funai/Gakken's Interstellar Laser Fantasy (`istellar`; the 1984 `istellar2` is Zangus): one player, a stick (4-way in MAME, 8-way in a listing) and two buttons, an upright with an external laserdisc player; a sit-down cockpit with a woofer under the seat also existed (medium) and is not built; both sets are NOT_WORKING in MAME |
| `thayers` | Thayer's Quest (set 1) (1984, RDI Video Systems, imperfect) | upright; stick, 6 buttons; 19" class | **approximate**: Thayer's Quest: an upright whose real control was a membrane keypad and keyboard, no joystick (MAME has a full keyboard matrix): a stick and six buttons are drawn |
| `spaceace` | Space Ace (US Rev. A3) (1983, Cinematronics, preliminary) | upright; stick, 1 button; 19" class | **upright**: Space Ace: an upright, a stick and a button |
| `roadblst` | Road Blasters (upright, rev 4) (1987, Atari Games, good) | stand-up driving cabinet: a yoke on the panel, one gas pedal on the floor, two buttons; the cockpit sets a seated cockpit with the same yoke | **built** (2026-10-27, 9.2d): a yoke that turns (135 degrees each way), Lasers and Special Weapon (buttons 2 and 3, no button 1), one gas pedal and no brake; `roadblstc`, `roadblstc1` and `roadblstcg` (MAME's "cockpit" sets) are the seated cockpit, the other eight sets the stand-up |
| `astron` | Astron Belt (1983, Sega, preliminary) | upright; stick, 2 buttons; 19" class | **upright**: Sega's Astron Belt: an upright, a stick and fire; a sit-down cockpit with a 25 inch monitor and a vibrating seat also existed (low-medium) and is not built |
| `sonic` | SegaSonic The Hedgehog (Japan, rev. C) (1992, Sega, imperfect) | upright; 3 x trackball, 1 button; tall body, 26" class | **upright**: SegaSonic the Hedgehog: three players, a trackball each and a jump button (low-medium) |
| `marble` | Marble Madness (set 1) (1984, Atari Games, good) | upright; 2 x trackball; 19" class | **upright**: Marble Madness: a trackball for each of two players, no button in MAME |
| `arkanoid` | Arkanoid (World, older) (1986, Taito, good) | upright; 2 x dial, 1 button; tate body, monitor on its side | **upright**: Taito's Arkanoid: a geared spinner and a fire button, the monitor on its side |
| `dotron` | Discs of Tron (Upright, 10/4/83) (1983, Bally Midway, good) | upright; trackball, 4 buttons; 19" class | **approximate**: Discs of Tron: MAME gives it a joystick, a dial and a trackball and a trackball with four buttons is drawn; the real controls were not verified (nothing found), and an "environmental" enclosure with a two-way mirror in every version (medium-low) is not built |
| `qbert` | Q*bert (US set 1) (1982, Gottlieb, imperfect) | upright; stick; START; tate body, monitor on its side, 19" class | **upright**: Gottlieb's Q*bert: a 4-way stick turned 45 degrees (the turn is not drawn), no buttons, the monitor on its side |
| `centiped` | Centipede (revision 4) (1980, Atari, good) | upright; trackball, 1 button; tate body, monitor on its side, 19" class | **upright**: Atari's Centipede: a trackball and a fire button, the monitor on its side |
| `milliped` | Millipede (1982, Atari, good) | upright; trackball, 1 button; START; tate body, monitor on its side, 19" class | **upright**: Atari's Millipede: the same |
| `trackfld` | Track & Field (1983, Konami, good) | upright; 4 x buttons only, 3 buttons; tall body, 35" class | **upright**: Konami's Track & Field: three buttons a player and no joystick; MAME has four players (IN0 for P1 and P2, IN1 for P3 and P4); the cabinet DIP is upright or cocktail |
| `hyperspt` | Hyper Sports (1984, Konami, good) | upright; 4 x buttons only, 3 buttons; tall body, 35" class | **upright**: Konami's Hyper Sports: three buttons a player, four players in MAME |
| `starwars` | Star Wars (Atari, set 1) (1983, Atari, good) | upright; yoke, 4 buttons | **built**: Atari's Star Wars: the upright's analog yoke, four buttons in MAME (two, or a trigger and a thumb button, in listings: conflict); a sit-down cockpit also existed (medium) and is not built (2e) |
| `asteroid` | Asteroids (rev 4) (1979, Atari, good) | upright; buttons only, 5 buttons | **upright**: Atari's Asteroids: five buttons (rotate, thrust, fire, hyperspace) on an upright |
| `tempest` | Tempest (rev 3, Revised Hardware) (1980, Atari, good) | upright; dial, 2 buttons; START; tate body, monitor on its side | **upright**: Atari's Tempest: a spinner and two buttons, the monitor on its side |
| `redbaron` | Red Baron (revised hardware) (1980, Atari, good) | upright; yoke, 1 button | **built**: Atari's Red Baron: the same yoke (the monitor's orientation: conflict between sources) |
| `spacfury` | Space Fury (revision C) (1981, Sega, good) | upright; stick, 2 buttons; START | **upright**: Sega's Space Fury: a left/right stick and two buttons a player, the monitor flipped (r180); the cocktail DIP is not implemented in MAME |
| `rotaryf` | Rotary Fighter (1979, Kasco, imperfect) | upright; stick, 1 button; START; tate body, monitor on its side, 19" class | **upright**: Kasco's Rotary Fighter: a single-player upright; MAME gives a two-way stick and a button ("a rotary dial" is the brief's, not confirmed); the monitor on its side in MAME, horizontal in one listing |
| `nitedrvr` | Night Driver (1976, Atari, imperfect) | stand-up driving cabinet: wheel on the panel, pedals on the floor; 19" class | **approximate**: Atari's Night Driver (1976): the upright's wheel and ONE accelerator (two pedals are drawn); the four-gear lever (one listing, low) is not drawn; the Highway sit-down model is not built |
| `safarir` | Safari Rally (World) (1979, SNK, imperfect) | upright; stick, 1 button; tate body, monitor on its side, 19" class | **upright**: Taito's Safari Rally: an upright; its controls were not found (MAME: a stick and a button) |
| `targ` | Targ (1980, Exidy, imperfect) | upright; stick, 1 button; 19" class | **upright**: Exidy's Targ: a 4-way stick and one button |
| `wacko` | Wacko (1982, Bally Midway, good) | upright; trackball; START; 19" class | **approximate**: Bally Midway's Wacko: a trackball steers and a joystick aims and fires (low-medium; ExoticA lists two 4-way sticks): only the trackball is drawn (a panel draws one control) |
| `zwackery` | Zwackery (1984, Bally Midway, good) | upright; rotary stick, 4 buttons; 19" class | **built**: Bally Midway's Zwackery: an 8-way stick, a dial and four buttons (Sword, Shield, Spell Up, Spell Down): the rotary stick (2d) |
| `kick` | Kick (upright) (1981, Midway, good) | upright (flagged `odd`); dial, 1 button; tate body, monitor on its side, 19" class | **upright**: Midway's Kick: one kick button and a sideways control the sources dispute (an optical roller, a rotary input or a trackball: low): a dial is drawn, the monitor on its side |
| `tron` | Tron (8/9) (1982, Bally Midway, good) | upright; rotary stick, 1 button; START; tate body, monitor on its side, 19" class | **built**: Bally Midway's Tron: an 8-way stick with a trigger and a rotary dial that aims (low-medium): the rotary stick (2d) |
| `journey` | Journey (1983, Bally Midway, good) | upright; stick, 1 button; START; tate body, monitor on its side, 19" class | **upright**: Bally Midway's Journey: a stick and a button; one or two buttons and 4 or 8 ways are in dispute |

**Totals: 87 built, 28 upright, 26 approximate, 2 none (143).** What the approximations have in common is a thing no panel draws or nothing found about: a second control beside the first
(Wacko's stick, Discs of Tron's), a twin (OutRun 2's second seat), a throttle (Star Wars Arcade's pilot), a keyboard (Thayer's Quest), a yoke (Road Blasters), the sit-down version of a game that
was mostly an upright, and the games MAME runs badly or not at all whose cabinets nothing describes (Karaoke Mix, Kids, Police Trainer, Zero Point, Rail Chase 2, Operation Wolf 3).
**Never run against a core or a ROM, and never seen in a headset**: this table is what is built, not what was played.
