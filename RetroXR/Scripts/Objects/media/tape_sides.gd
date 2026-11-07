## TapeSides — where everything is on a two-sided medium: a Compact Cassette or an LP. Pure arithmetic, no nodes.
##
## An album's tracks are cut into side A and side B by the `#SIDE B` line of its playlist (RomLibrary.music_sides);
## each side's tracks follow one another from the side's start, by their real lengths (MusicLengths), and whatever is
## left of the side after its last track is BLANK: tape running on in silence, or an LP's run-out groove.
##
## A cassette is a standard length, C46 / C60 / C90 / C120 (minutes for both sides), the shortest whose side holds the
## longer side's music. Its tape has ONE place, `pos`, 0 at side A's start and 1 at its end, which is also side B's
## start turned round: playing side A winds pos up, playing side B winds it down, so a tape stopped 60 % into side A
## and turned over is 40 % into side B, as a real one is. AudioCassette.tape_progress holds it (the share of the tape
## on side A's take-up hub, which CompactCassette winds the packs from).
class_name TapeSides
extends RefCounted

## Compact Cassette lengths, minutes for both sides (IEC 60094-7 names them by playing time).
const TAPE_TYPES: Array[int] = [46, 60, 90, 120]
## Leader-to-leader slack past the longer side's music: a C46 holding 23:00 exactly would end on the last note.
const SIDE_MARGIN_S := 5.0


## Each track's start on its side, seconds, and the side's music in all as the last entry (size n + 1).
static func starts(lens: PackedFloat64Array) -> PackedFloat64Array:
	var out := PackedFloat64Array([0.0])
	var at := 0.0
	for l in lens:
		at += maxf(l, 0.0)
		out.append(at)
	return out


## A side's music, seconds: its tracks end to end.
static func music_s(lens: PackedFloat64Array) -> float:
	var s := starts(lens)
	return s[s.size() - 1]


## The cassette for an album whose sides hold `a_s` and `b_s` seconds of music: the shortest standard tape whose side
## holds the longer one with SIDE_MARGIN_S to spare. Longer than a C120's side: that side's own length, rounded up.
static func tape_minutes(a_s: float, b_s: float) -> float:
	var need := maxf(a_s, b_s) + SIDE_MARGIN_S
	for m in TAPE_TYPES:
		if m * 30.0 >= need:
			return float(m)
	return ceilf(need / 30.0)


## One side's running time on a cassette of `minutes`, seconds.
static func side_s(minutes: float) -> float:
	return minutes * 30.0


## A cassette's name for the display and the Debug tab: "C60", or "C142" for an odd one.
static func tape_name(minutes: float) -> String:
	return "C%d" % roundi(minutes)


## Where `t` seconds into a side falls: {track, into, blank}. `track` is the track playing and `into` how far into it;
## past the last track (or on a side with none) `track` is the track count and `blank` the seconds into the blank run,
## else `blank` is -1. A time before 0 is the side's start.
static func locate(lens: PackedFloat64Array, t: float) -> Dictionary:
	var s := starts(lens)
	var n := lens.size()
	t = maxf(t, 0.0)
	if t >= s[n]:
		return {"track": n, "into": 0.0, "blank": t - s[n]}
	for i in n:
		if t < s[i + 1]:
			return {"track": i, "into": t - s[i], "blank": -1.0}
	return {"track": n, "into": 0.0, "blank": 0.0}


## The time on a side of `into` seconds into `track`; `track` = the track count is the blank run, `into` into it.
static func time_of(lens: PackedFloat64Array, track: int, into: float) -> float:
	var s := starts(lens)
	return s[clampi(track, 0, lens.size())] + maxf(into, 0.0)


## The time on `side` (0 = A, 1 = B) of a tape at `pos`, its sides `side_len` long.
static func side_time(pos: float, side: int, side_len: float) -> float:
	pos = clampf(pos, 0.0, 1.0)
	return (pos if side == 0 else 1.0 - pos) * side_len


## The tape's place for `t` seconds into `side`.
static func pos_of(side: int, t: float, side_len: float) -> float:
	if side_len <= 0.0:
		return 0.0
	var f := clampf(t / side_len, 0.0, 1.0)
	return f if side == 0 else 1.0 - f


## "A" or "B".
static func side_name(side: int) -> String:
	return "B" if side == 1 else "A"
