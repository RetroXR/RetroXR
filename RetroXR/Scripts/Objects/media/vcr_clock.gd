## VCRClock — front-panel 7-segment time readout for the VCR player.
## A SubViewport renders a SevenSegmentDisplay; its texture is mapped onto a quad
## on the VCR front face, shown as "HH:MM:SS / HH:MM:SS" (current / total).
class_name VCRClock
extends Node3D

@onready var _viewport: SubViewport = $ClockViewport
@onready var _display: SevenSegmentDisplay = $ClockViewport/Display
@onready var _screen: MeshInstance3D = $Screen


func _ready() -> void:
	# Map the SubViewport's live texture onto the panel quad, unshaded so it
	# reads as a self-lit display regardless of room lighting.
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = _viewport.get_texture()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_screen.material_override = mat
	set_blank()


## Show current / total time. Pass total < 0 for an unknown duration.
func set_times(cur: float, total: float) -> void:
	if _display:
		_display.text = counter(cur) + " / " + counter(total)


## Show the idle "--:--:-- / --:--:--" state (no tape).
func set_blank() -> void:
	if _display:
		_display.text = "--:--:-- / --:--:--"


## One side of the readout. Static so a tape's menu (VCRTape.options_info) reads
## its place the way the deck's front panel does.
static func counter(t: float) -> String:
	if t < 0.0:
		return "--:--:--"
	var s := int(round(t))
	@warning_ignore("integer_division")
	var parts := [s / 3600, (s % 3600) / 60, s % 60]
	return "%02d:%02d:%02d" % parts
