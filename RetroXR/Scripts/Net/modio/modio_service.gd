## Modio — the autoload that owns the mod browser's services.
##
## mod.io's catalogue (ModioClient), the pack downloader (ModDownloader), the
## tiles' preview images (ModArtCache) and the downloads waiting for the player's
## answer (ModReviews).
##
## An autoload, and not children of the spawn menu as they first were, because
## the menu rides the player rig and the rig leaves the tree on every room
## change: a child's _exit_tree fired there, and ModDownloader's cancels every
## download. A pack is tens of megabytes on a headset's wifi, and walking into
## another room should not throw one away.
##
## Declared after Mods, which the downloader hands its files to. Nothing here
## reaches the network at boot: the first request is made when the player opens
## the MODS tab, and then only for mod.io's terms.
extends Node

var client: ModioClient = null
var downloader: ModDownloader = null
var art: ModArtCache = null
var reviews := ModReviews.new()


func _ready() -> void:
	client = ModioClient.new()
	client.name = "ModioClient"
	add_child(client)

	downloader = ModDownloader.new()
	downloader.name = "ModDownloader"
	# A finished download stops at the review instead of going straight into the
	# mods folder. Bound to an object that lives as long as the downloader does.
	downloader.install_hook = reviews.stage
	add_child(downloader)

	art = ModArtCache.new()
	art.name = "ModArtCache"
	add_child(art)
