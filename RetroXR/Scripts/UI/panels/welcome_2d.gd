## Welcome2D — the page of the first-time popup (WelcomePanel): what to do in
## RetroXR, and what not to.
##
## Built in code from MenuStyle, like every *_2d panel. The copy is consts so
## welcome_tests can hold it to the real bindings: a page that tells a new player
## the wrong key is worse than no page, and the README had the desktop drop on
## Ctrl + click while the code had it on Shift.
##
## The headset and the desktop get different pages, picked once when it is built:
## a player in VR has no Tab key, and one at a desk has no left stick. A Quest's page
## also loads files differently: through the Web File Manager only (QUEST_ROMS_LINE),
## with a DON'T for every other way in (DONT_QUEST).
##
## Two columns: the copy on the left; on the right a looping clip of the menu
## being used (MENU_CLIP, recorded from the real menu by
## Tools/room/welcome_clip_probe) and, on the headset's page, the STAGE: an empty
## box the 3D controllers (ControllerDemo) stand in front of, with the step they
## are showing written under it (set_step).
##
## Emits:
##   dismissed — Got it pressed
class_name Welcome2D
extends Control

signal dismissed

const TITLE := "Welcome to RetroXR"
## Where the ROM folder goes in a line (roms_folder()).
const ROMS_TOKEN := "{roms}"

const DO_VR: Array[String] = [
	"Click the LEFT stick to open the menu. Every console, TV and game comes from it.",
	"First, download the emulators: CORES > Download > Download All Recommended.",
	"Put your own game files in a folder per system (snes/, n64/, psx/ ...) inside " + ROMS_TOKEN
		+ ". Or connect a RomM server in OPTIONS > RomM.",
	"Build it like the real thing: cartridge or disc in the console, AV cable to the TV, "
		+ "controller in a port, then flip the power switch.",
	"Grip grabs things, up close or along the laser. Something that stays in your hand "
		+ "comes off with grip + trigger + stick click.",
	"Point at anything and click the left stick for its options.",
	"Point your right hand at a TV and click the right stick to bring its picture in front "
		+ "of you. Do it again to put it back.",
]

const DO_DESKTOP: Array[String] = [
	"Press Tab to open the menu. Every console, TV and game comes from it.",
	"First, download the emulators: CORES > Download > Download All Recommended.",
	"Put your own game files in a folder per system (snes/, n64/, psx/ ...) inside " + ROMS_TOKEN
		+ ". Or connect a RomM server in OPTIONS > RomM.",
	"Build it like the real thing: cartridge or disc in the console, AV cable to the TV, "
		+ "controller in a port, then flip the power switch.",
	"Click to pick something up and click again to put it down; Shift + click puts down "
		+ "anything, even a light gun. The scroll wheel moves it nearer or further.",
	"Look at anything and press Tab for its options.",
	"Look at a TV and press F11 to fill the window with its picture. F11 again to come back.",
]

const DONT: Array[String] = [
	"Don't download games or BIOS files you don't own. RetroXR comes with none, and it "
		+ "never sends game files between players.",
]

## On a Quest the ROM line (the one carrying ROMS_TOKEN) is this instead: Android
## lets RetroXR manage only files it wrote itself, so the Web File Manager, which
## writes them AS RetroXR, is the one way in.
const QUEST_ROMS_LINE := "Load your own game files with the Web File Manager: switch it on in " \
	+ "OPTIONS > File Server, open the address it shows in a browser on the same Wi-Fi, enter " \
	+ "the PIN and upload into roms, a folder per system (snes, n64, psx ...). Or connect a " \
	+ "RomM server in OPTIONS > RomM."

## A Quest's own DON'T. A file that a file manager app, a PC over USB or adb puts in
## the app's folder belongs to that other owner (uid): RetroXR, which Android runs as
## a user of its own, can read such a file at best and never change or delete it,
## and a folder made that way it may not even be let into (docs/dev/quest-device.md).
const DONT_QUEST: Array[String] = [
	"Don't copy files into RetroXR's folder with a file manager app, over USB or with adb. "
		+ "Android files them under another owner (uid), so RetroXR can't change or delete them "
		+ "and may not see them at all. Use the Web File Manager only.",
]

const COLOR_DO := Color(0.45, 0.85, 0.45)
const COLOR_DONT := Color(1.0, 0.55, 0.50)
const COLOR_ITEM := Color(0.86, 0.86, 0.96)

## The menu being opened and used, looping, silent. A missing clip leaves a
## note in its place rather than an empty hole.
const MENU_CLIP := "res://Textures/welcome/menu_clip.ogv"
const CLIP_CAPTION := "The menu: open it, download the emulators from CORES, then SPAWN a console and a TV."

const PAD := 48
const TITLE_PT := 46
const HEADER_PT := 32
const ITEM_PT := 27
const CAPTION_PT := 22
## Pixel sizes of the two columns' parts. The clip is the menu (2200 x 1800) at
## 0.4; the stage is what the two controllers stand in front of.
const TEXT_WIDTH := 1150
const CLIP_SIZE := Vector2(880, 720)
const STAGE_SIZE := Vector2(880, 400)
const COLOR_STAGE := Color(0.13, 0.13, 0.24)

## Which page to build: -1 asks MenuStyle whether the headset is running, 0 the
## desktop page, 1 the headset's. Set before the page enters the tree; for tests.
var vr_override := -1
## The same for the Quest's file lines: -1 asks the OS, 0 no, 1 yes. For tests.
var android_override := -1
## The same for a page built where nothing can set vr_override first (inside the
## panel's viewport): a probe filming the headset's page on a desk sets it.
static var force_vr := -1

## The rounded plate everything is on; its minimum size is the page's.
var _plate: Control = null
var _clip: VideoStreamPlayer = null
var _stage: Control = null
var _step_label: Label = null


## The lines under DO for the headset or the desktop, with the ROM folder filled
## in, or on a Quest (`android`) the Web File Manager in place of the folder.
static func do_lines(vr: bool, android := OS.has_feature("android")) -> Array[String]:
	var out: Array[String] = []
	for line: String in (DO_VR if vr else DO_DESKTOP):
		if ROMS_TOKEN in line and android:
			out.append(QUEST_ROMS_LINE)
		else:
			out.append(line.replace(ROMS_TOKEN, roms_folder()))
	return out


## The lines under DON'T, a Quest's own (`android`) after the rest.
static func dont_lines(android := OS.has_feature("android")) -> Array[String]:
	var out: Array[String] = DONT.duplicate()
	if android:
		out.append_array(DONT_QUEST)
	return out


## The ROM folder as a desktop player finds it.
static func roms_folder() -> String:
	return DataPaths.media_root("roms")


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


func _is_android() -> bool:
	return OS.has_feature("android") if android_override < 0 else android_override == 1


func _is_vr() -> bool:
	var pick := vr_override if vr_override >= 0 else force_vr
	return MenuStyle.is_vr_mode() if pick < 0 else pick == 1


func _build() -> void:
	var vr := _is_vr()
	var android := _is_android()
	var margin := MenuStyle.panel_root(self, MenuStyle.COLOR_BG, 18, PAD)
	_plate = margin.get_parent() as Control
	var vbox := MenuStyle.vbox(14)
	margin.add_child(vbox)

	var title := MenuStyle.label(TITLE, TITLE_PT, MenuStyle.COLOR_TITLE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	vbox.add_child(MenuStyle.spacer(4))

	var columns := MenuStyle.hbox(44)
	vbox.add_child(columns)
	var copy := MenuStyle.vbox(14, false)
	copy.custom_minimum_size.x = TEXT_WIDTH
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(copy)
	var shown := MenuStyle.vbox(12, false)
	columns.add_child(shown)

	copy.add_child(MenuStyle.label("DO", HEADER_PT, COLOR_DO))
	for line: String in do_lines(vr, android):
		copy.add_child(_item(line, COLOR_DO))
	copy.add_child(MenuStyle.spacer(8))

	copy.add_child(MenuStyle.label("DON'T", HEADER_PT, COLOR_DONT))
	for line: String in dont_lines(android):
		copy.add_child(_item(line, COLOR_DONT))

	_build_clip(shown)
	if vr:
		_build_stage(shown)

	# The button sits at the foot of the page, a fixed gap under the copy when the
	# page is fitted to it (WelcomePanel), and at the bottom of a taller one.
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(fill)
	vbox.add_child(MenuStyle.spacer(20))

	var row := MenuStyle.hbox(0)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(row)
	var got_it := MenuStyle.row_button("Got it", 34, 360, 88, false)
	got_it.name = "GotIt"
	var style := MenuStyle.rounded(MenuStyle.COLOR_BTN_DL, 10)
	for state: String in ["normal", "hover", "pressed"]:
		got_it.add_theme_stylebox_override(state, style)
	got_it.pressed.connect(_on_got_it)
	row.add_child(got_it)

	var again := MenuStyle.label("You can see this again from the menu's ABOUT page.",
		18, MenuStyle.COLOR_DESC)
	again.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(again)


## The menu clip, looping, framed, with what it shows written under it.
func _build_clip(parent: Container) -> void:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", MenuStyle.rounded(Color.BLACK, 8))
	parent.add_child(frame)
	if ResourceLoader.exists(MENU_CLIP):
		_clip = VideoStreamPlayer.new()
		_clip.name = "MenuClip"
		_clip.stream = load(MENU_CLIP) as VideoStream
		_clip.custom_minimum_size = CLIP_SIZE
		_clip.expand = true
		_clip.loop = true
		_clip.autoplay = true
		_clip.volume_db = -80.0
		frame.add_child(_clip)
	else:
		push_warning("[Welcome] no menu clip at %s; the page shows a note instead" % MENU_CLIP)
		var note := MenuStyle.label("(the menu clip is missing from this build)", CAPTION_PT,
			MenuStyle.COLOR_DESC)
		note.custom_minimum_size = CLIP_SIZE
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		frame.add_child(note)
	parent.add_child(_caption(CLIP_CAPTION))


## The headset page's stage: the controllers stand in front of it (ControllerDemo),
## and the step they show is written under it.
func _build_stage(parent: Container) -> void:
	_stage = Panel.new()
	_stage.name = "Stage"
	_stage.custom_minimum_size = STAGE_SIZE
	_stage.add_theme_stylebox_override("panel", MenuStyle.rounded(COLOR_STAGE, 12))
	parent.add_child(_stage)
	_step_label = _caption("")
	_step_label.name = "StepCaption"
	_step_label.add_theme_color_override("font_color", COLOR_ITEM)
	_step_label.add_theme_font_size_override("font_size", ITEM_PT)
	_step_label.custom_minimum_size.y = 80
	parent.add_child(_step_label)


func _caption(words: String) -> Label:
	var l := MenuStyle.label(words, CAPTION_PT, MenuStyle.COLOR_DESC)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size.x = CLIP_SIZE.x
	return l


## Where the stage is on the page, in page pixels; empty on the desktop page.
func stage_rect() -> Rect2:
	return _stage.get_global_rect() if _stage != null else Rect2()


## Write the step the controllers are showing under the stage.
func set_step(index: int, count: int, caption: String) -> void:
	if _step_label != null:
		_step_label.text = "%d / %d    %s" % [index + 1, count, caption]


## The clip's player, or null when the build has no clip.
func clip_player() -> VideoStreamPlayer:
	return _clip


## How tall the page has to be to hold everything on it, in pixels, at the width
## it is laid out at. Read a frame after it enters the tree: a wrapped line not yet
## laid out measures itself at whatever width it last had.
func content_height() -> float:
	return _plate.get_combined_minimum_size().y if _plate != null else 0.0


## One line under a heading: a bullet in the heading's colour, the text beside it,
## wrapping under itself rather than back under the bullet.
func _item(text: String, bullet_color: Color) -> HBoxContainer:
	var row := MenuStyle.hbox(14)
	var bullet := MenuStyle.label("•", ITEM_PT, bullet_color)
	bullet.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(bullet)
	var body := MenuStyle.label(text, ITEM_PT, COLOR_ITEM)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(body)
	return row


func _on_got_it() -> void:
	dismissed.emit()
