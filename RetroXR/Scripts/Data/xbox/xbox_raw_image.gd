## XboxRawImage — a disk that is just its bytes: an Xbox Memory Unit.
##
## The hard disk is a qcow2 and has to be read through Qcow2Image's tables; a
## Memory Unit image is the 8 MB of the unit itself, byte for byte. This gives
## those bytes the same two members FatxVolume reads a disk through — read() and
## `error` — so one FATX reader serves both.
class_name XboxRawImage
extends RefCounted

var error := ""
var _bytes: PackedByteArray = PackedByteArray()


static func of(bytes: PackedByteArray) -> XboxRawImage:
	var image := XboxRawImage.new()
	image._bytes = bytes
	return image


func virtual_size() -> int:
	return _bytes.size()


## `length` bytes at `offset`, or empty with `error` set when that runs off the
## end — never a short read, which a caller would parse as a truncated table.
func read(offset: int, length: int) -> PackedByteArray:
	if offset < 0 or length < 0 or offset + length > _bytes.size():
		error = "read outside the image (%d + %d of %d)" % [offset, length, _bytes.size()]
		return PackedByteArray()
	return _bytes.slice(offset, offset + length)


func close() -> void:
	pass
