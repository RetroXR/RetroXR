## SpawnMenuModsPacksPage — the MODS tab's Packs page: mod.io collections.
##
## A pack is a list of mods somebody put together on mod.io. Installing one is
## installing its members, each fetched and vetted exactly as a single mod is,
## and then ONE question for the lot: what the pack replaces, where two of its
## members want the same file, and what could not be installed and why. Every
## member lands DISABLED unless the player says otherwise there.
##
## Removing a pack removes only what it alone brought: a member the player also
## installed on its own, or that another pack still wants, stays
## (ModCollectionPlan.plan_remove).
##
## The page is built into a column the view owns, and borrows the view's tiles,
## pictures, toasts and download review. It keeps the batches: which downloads
## belong to each pack being installed, and what became of each.
##
## Packs QUEUE. Install on a second pack while the first is still coming down
## puts its members in the downloader's queue behind the first's (it fetches one
## file at a time anyway), and each pack's question is asked in turn, in the
## order Install was pressed. A queued pack can be taken off the queue.
class_name SpawnMenuModsPacksPage
extends RefCounted

var _view: SpawnMenuModsView = null
var _scroll: ScrollContainer = null

var _list: VBoxContainer = null       ## toolbar + grid + pager
var _detail: VBoxContainer = null     ## one pack
var _review: VBoxContainer = null     ## the question before a pack is installed
var _search_edit: LineEdit = null
var _search_timer: Timer = null
var _sort := str(ModioClient.COLLECTION_SORTS[0][1])
var _status_lbl: Label = null
var _grid: HFlowContainer = null
## Members a pack skipped because they were already coming down another way:
## {pack, mod, confirmed}. Once the pack is installed AND the member is, the
## member is recorded as the pack's too (tag_pending) -- else removing the pack
## would leave it behind.
var _pending_tags: Array = []
var _prev_btn: Button = null
var _next_btn: Button = null
var _page_lbl: Label = null
var _packs: Array[Dictionary] = []
var _total := 0
var _offset := 0
var _fetched := false
var _request_serial := 0

var _open_pack: Dictionary = {}
## The open pack's members as mod.io last listed them, and whether that arrived.
var _members: Array[Dictionary] = []
var _members_total := 0
var _members_state := ""              ## "" asking, "ok", or the error
var _member_serial := 0

## The packs being installed, in the order Install was pressed. Each is
## {id, name, keys, done, staged, skip, have, ready, cancelled}:
##   keys       job key -> the member mod, for every download asked for
##   done       job keys that finished, either way
##   staged     job keys whose pack was fetched, vetted and waits for the answer
##   skip       Array of {name, why}
##   have       members already here at mod.io's file
##   ready      every download is in and the pack waits for its question
##   cancelled  the player took it back
var _batches: Array[Dictionary] = []
## The batch whose question is on screen, {} for none.
var _reviewing: Dictionary = {}
## pack id -> true while mod.io is asked what its mods need, before its batch.
var _asking: Dictionary = {}


func _init(view: SpawnMenuModsView, into: VBoxContainer, scroll: ScrollContainer) -> void:
	_view = view
	_scroll = scroll
	_list = MenuStyle.vbox(10)
	into.add_child(_list)
	_detail = MenuStyle.vbox(10)
	_detail.visible = false
	into.add_child(_detail)
	_review = MenuStyle.vbox(8)
	_review.visible = false
	into.add_child(_review)
	_build_list()


## True for a download this page asked for, so the view leaves its toasts and
## its single-mod review alone.
func owns(key: String) -> bool:
	return not _batch_owning(key).is_empty()


## The batch that asked for download `key`, {} for none.
func _batch_owning(key: String) -> Dictionary:
	for batch: Dictionary in _batches:
		if (batch["keys"] as Dictionary).has(key):
			return batch
	return {}


## The batch installing pack `pack_id`, {} for none.
func _batch_of(pack_id: int) -> Dictionary:
	for batch: Dictionary in _batches:
		if int(batch["id"]) == pack_id:
			return batch
	return {}


## Every pack id with a batch, in queue order. For the suite.
func queued_packs() -> Array[int]:
	var ids: Array[int] = []
	for batch: Dictionary in _batches:
		ids.append(int(batch["id"]))
	return ids


## The pack whose question is on screen, 0 for none. For the suite.
func reviewing_pack() -> int:
	return int(_reviewing.get("id", 0))


func ensure_fetched() -> void:
	if not _fetched:
		_fetch(0)


## The player withdrew their agreement: nothing fetched before it may stay.
func forget() -> void:
	# The view has already cancelled the downloads and thrown the reviews away.
	_batches.clear()
	_pending_tags.clear()
	_reviewing = {}
	_asking.clear()
	_fetched = false
	_packs.clear()
	_total = 0
	_open_pack = {}
	_show(_list)
	SpawnMenuModsView._clear(_grid)
	_status_lbl.text = ""


func on_mods_changed() -> void:
	if _detail.visible:
		_fill_detail()
	elif _list.visible and _fetched:
		_rebuild_grid()


func _show(which: Control) -> void:
	for panel: Control in [_list, _detail, _review]:
		panel.visible = panel == which
	_scroll.scroll_vertical = 0


func _back_to_list() -> void:
	_open_pack = {}
	_show(_list)
	if _fetched:
		_rebuild_grid()


# ── the list ──────────────────────────────────────────────────────────────────

func _build_list() -> void:
	var bar := MenuStyle.hbox(10)
	bar.custom_minimum_size = Vector2(0, 56)
	_list.add_child(bar)

	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = "Search packs"
	_search_edit.clear_button_enabled = true
	_search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_edit.custom_minimum_size = Vector2(0, 52)
	_search_edit.add_theme_font_size_override("font_size", 20)
	_search_edit.text_changed.connect(func(_t: String) -> void:
		_search_timer.start(SpawnMenuModsView.SEARCH_DEBOUNCE))
	_search_edit.text_submitted.connect(func(_t: String) -> void:
		_search_timer.stop()
		_fetch(0))
	bar.add_child(_search_edit)

	_search_timer = Timer.new()
	_search_timer.one_shot = true
	_search_timer.timeout.connect(func() -> void: _fetch(0))
	_list.add_child(_search_timer)

	var sort_drop := VRDropdown.create("Sort", ModioClient.COLLECTION_SORTS, _sort, 1, Vector2(240, 52), 18)
	sort_drop.item_selected.connect(func(id: Variant) -> void:
		_sort = str(id)
		_fetch(0))
	bar.add_child(sort_drop)

	var refresh_btn := MenuStyle.row_button("Refresh", 18, 130, 52, false)
	refresh_btn.pressed.connect(func() -> void: _fetch(_offset))
	bar.add_child(refresh_btn)

	_status_lbl = MenuStyle.label("", 16, MenuStyle.COLOR_DESC)
	_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_list.add_child(_status_lbl)

	_grid = HFlowContainer.new()
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	_list.add_child(_grid)

	var pager := MenuStyle.hbox(10)
	pager.alignment = BoxContainer.ALIGNMENT_CENTER
	_list.add_child(pager)
	_prev_btn = MenuStyle.row_button("Previous", 18, 160, 52, false)
	_prev_btn.pressed.connect(func() -> void: _fetch(maxi(0, _offset - ModioClient.PAGE_SIZE)))
	pager.add_child(_prev_btn)
	_page_lbl = MenuStyle.label("", 18, MenuStyle.COLOR_LICENSE)
	_page_lbl.custom_minimum_size = Vector2(200, 0)
	_page_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pager.add_child(_page_lbl)
	_next_btn = MenuStyle.row_button("Next", 18, 160, 52, false)
	_next_btn.pressed.connect(func() -> void: _fetch(_offset + ModioClient.PAGE_SIZE))
	pager.add_child(_next_btn)

	_list.add_child(HSeparator.new())
	_list.add_child(MenuStyle.hint(
		"A pack is a list of mods somebody put together on mod.io. Installing "
		+ "one installs its mods, and nothing in it runs until you enable it."))
	_update_pager()


func _fetch(offset: int) -> void:
	if _view.client == null:
		_status_lbl.text = "The mod browser is unavailable in this build."
		return
	_request_serial += 1
	var serial := _request_serial
	_status_lbl.text = "Asking mod.io…"
	_view.client.list_collections(_search_edit.text, _sort, offset,
		func(ok: bool, packs: Array[Dictionary], total: int, error: String) -> void:
			if serial != _request_serial:
				return
			if not ok:
				_status_lbl.text = error
				return
			_fetched = true
			_packs = packs
			_total = total
			_offset = offset
			_rebuild_grid())


func _rebuild_grid() -> void:
	SpawnMenuModsView._clear(_grid)
	for pack: Dictionary in _packs:
		_grid.add_child(_tile(pack))
	if _packs.is_empty():
		_status_lbl.text = "No pack on mod.io matches that." \
			if not _search_edit.text.strip_edges().is_empty() \
			else "No packs have been published yet."
	else:
		_status_lbl.text = "%d pack%s on mod.io" % [_total, "" if _total == 1 else "s"]
	_update_pager()


func _update_pager() -> void:
	var pages := maxi(1, ceili(float(_total) / float(ModioClient.PAGE_SIZE)))
	_page_lbl.text = "Page %d of %d" % [_offset / ModioClient.PAGE_SIZE + 1, pages]
	_prev_btn.disabled = _offset <= 0
	_next_btn.disabled = _offset + ModioClient.PAGE_SIZE >= _total
	for control: Control in [_prev_btn, _next_btn, _page_lbl]:
		control.visible = pages > 1


func _tile(pack: Dictionary) -> Button:
	var sub := str(pack["author"])
	if int(pack["file_size"]) > 0:
		sub += ("  ·  " if not sub.is_empty() else "") + MenuStyle.human_bytes(int(pack["file_size"]))
	# The members are not known until the pack is opened, so the tile can only
	# say whether anything on this device came from it.
	var here := not installed_from(int(pack["id"])).is_empty()
	var tile := _view._make_tile(str(pack["name"]), sub,
		"On this device" if here else "",
		MenuStyle.COLOR_RECOMMENDED if here else MenuStyle.COLOR_DESC)
	_view._bind_art(tile, str(pack["logo_small"]))
	tile.pressed.connect(func() -> void: _open(pack))
	return tile


## True when a member that is already here is not yet recorded as this pack's.
## Installing the pack then downloads nothing and still has something to do.
static func _untagged(have: Array, collection_id: int) -> bool:
	for mod: Dictionary in have:
		var rec := Mods.find_by_source("modio_id", int(mod["id"]))
		if rec != null and not ModCollectionPlan.collections_of(Mods.source(rec.id)).has(collection_id):
			return true
	return false


## The ids of the installed mods pack `collection_id` brought in.
static func installed_from(collection_id: int) -> Array[String]:
	var out: Array[String] = []
	for rec: ModRecord in Mods.all_mods():
		if ModCollectionPlan.collections_of(Mods.source(rec.id)).has(collection_id):
			out.append(rec.id)
	return out


## modio_id -> file_id for every mod.io mod on this device.
static func installed_files() -> Dictionary:
	var out := {}
	for rec: ModRecord in Mods.all_mods():
		var source := Mods.source(rec.id)
		if int(source.get("modio_id", 0)) > 0:
			out[int(source["modio_id"])] = int(source.get("file_id", 0))
	return out


# ── one pack ──────────────────────────────────────────────────────────────────

func _open(pack: Dictionary) -> void:
	_open_pack = pack
	_members.clear()
	_members_total = 0
	_members_state = ""
	_fill_detail()
	_show(_detail)
	_fetch_members()


func _fetch_members() -> void:
	_member_serial += 1
	var serial := _member_serial
	var pack_id := int(_open_pack["id"])
	_members_state = ""
	_view.client.list_collection_mods(pack_id,
		func(ok: bool, mods: Array[Dictionary], total: int, error: String) -> void:
			if serial != _member_serial or int(_open_pack.get("id", 0)) != pack_id:
				return
			_members = mods
			_members_total = total
			_members_state = "ok" if ok else error
			if _detail.visible:
				_fill_detail())


func _fill_detail() -> void:
	SpawnMenuModsView._clear(_detail)
	if _open_pack.is_empty():
		return
	var pack := _open_pack
	var pack_id := int(pack["id"])
	var back := SpawnMenuModsView._narrow(MenuStyle.row_button("←  All packs", 20, 220, 52, false))
	back.pressed.connect(_back_to_list)
	_detail.add_child(back)

	var head := MenuStyle.hbox(16)
	_detail.add_child(head)
	var picture := _view._art_panel(Vector2(480, 270))
	head.add_child(picture)
	_view._bind_art(picture, str(pack["logo_large"]))

	var facts := MenuStyle.vbox(6)
	facts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(facts)
	var title := MenuStyle.label(str(pack["name"]), 26, MenuStyle.COLOR_TITLE)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	facts.add_child(title)
	if not str(pack["author"]).is_empty():
		facts.add_child(MenuStyle.label("put together by " + str(pack["author"]), 18, MenuStyle.COLOR_LICENSE))

	var installed := installed_files()
	var plan := ModCollectionPlan.plan_install(_members, installed)
	var fetch: Array = plan["fetch"]
	var skip: Array = plan["skip"]
	var state := ModCollectionPlan.pack_state(_members, installed)
	var batch := _batch_of(pack_id)

	var lines := PackedStringArray()
	if _members_state == "ok":
		lines.append("%d mod%s" % [_members.size(), "" if _members.size() == 1 else "s"])
		if _members_total > _members.size():
			lines.append("first %d of %d shown" % [_members.size(), _members_total])
	if int(pack["file_size"]) > 0:
		lines.append(MenuStyle.human_bytes(int(pack["file_size"])))
	if int(pack["downloads"]) > 0:
		lines.append("%d downloads" % int(pack["downloads"]))
	if not lines.is_empty():
		facts.add_child(MenuStyle.label("  ·  ".join(lines), 16, MenuStyle.COLOR_DESC))
	if bool(pack["incomplete"]):
		facts.add_child(MenuStyle.label(
			"mod.io says a mod in this pack is no longer available.", 16, MenuStyle.COLOR_BTN_UPD))
	if not ModCollectionPlan.state_text(state).is_empty():
		facts.add_child(MenuStyle.label(ModCollectionPlan.state_text(state), 18,
			MenuStyle.COLOR_RECOMMENDED if state == "installed" else Color(0.95, 0.75, 0.35)))

	var actions := MenuStyle.hbox(10)
	facts.add_child(actions)
	if not batch.is_empty():
		_batch_status(batch, facts, actions)
	elif _asking.has(pack_id):
		facts.add_child(MenuStyle.label("Asking mod.io what its mods need…", 16, MenuStyle.COLOR_DESC))
	elif _members_state == "ok" and (not fetch.is_empty() or _untagged(plan["have"], pack_id)):
		var label := "Update pack" if state == "update" else "Install pack"
		var get_btn := MenuStyle.row_button(label, 20, 220, 56, false)
		get_btn.add_theme_stylebox_override("normal", MenuStyle.rounded(MenuStyle.COLOR_BTN_DL, 6))
		get_btn.pressed.connect(func() -> void: _install(pack))
		actions.add_child(get_btn)
	if batch.is_empty() and not installed_from(pack_id).is_empty():
		# Two presses, as on a single mod: this deletes files.
		var remove := MenuStyle.row_button("Remove pack", 20, 220, 56, false)
		remove.pressed.connect(func() -> void:
			if remove.text != "Really remove?":
				remove.text = "Really remove?"
				remove.add_theme_stylebox_override("normal",
					MenuStyle.rounded(MenuStyle.COLOR_BTN_CLEAR, 6))
				return
			_remove(pack))
		actions.add_child(remove)

	if not str(pack["summary"]).is_empty():
		var summary := MenuStyle.label(str(pack["summary"]), 18, MenuStyle.COLOR_LICENSE)
		summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail.add_child(summary)

	_detail.add_child(HSeparator.new())
	if _members_state.is_empty():
		_detail.add_child(MenuStyle.hint("Asking mod.io what is in this pack…"))
	elif _members_state != "ok":
		_detail.add_child(MenuStyle.label(_members_state, 16, MenuStyle.COLOR_BTN_UPD))
		var retry := SpawnMenuModsView._narrow(MenuStyle.row_button("Try again", 18, 200, 52, false))
		retry.pressed.connect(func() -> void:
			_fetch_members()
			_fill_detail())
		_detail.add_child(retry)
	else:
		var why := {}
		for entry: Dictionary in skip:
			why[str(entry["name"])] = str(entry["why"])
		for mod: Dictionary in _members:
			_detail.add_child(_member_row(mod, installed, why))
		if not skip.is_empty():
			_detail.add_child(MenuStyle.hint("%d of %d can be installed now." % [
				_members.size() - skip.size(), _members.size()]))

	_detail.add_child(HSeparator.new())
	var links := MenuStyle.hbox(10)
	_detail.add_child(links)
	if not str(pack["profile_url"]).is_empty():
		var page_btn := MenuStyle.row_button("Open on mod.io", 18, 240, 52, false)
		page_btn.pressed.connect(func() -> void: _view._open_link(str(pack["profile_url"])))
		links.add_child(page_btn)
		# mod.io's terms: everything a game shows must be reportable. A pack is
		# reported from its own page; each mod in it has its own Report button.
		_detail.add_child(MenuStyle.hint(
			"Hosted by mod.io. To report this pack, open it on mod.io; to report "
			+ "one of its mods, open the mod here."))


## One member: its name, and what installing the pack would do with it. Opens
## the mod itself on the Browse page.
func _member_row(mod: Dictionary, installed: Dictionary, why: Dictionary) -> Button:
	var mod_id := int(mod["id"])
	var note := ""
	if why.has(str(mod["name"])):
		note = "Cannot be installed: " + str(why[str(mod["name"])])
	elif installed.has(mod_id):
		note = "Installed" if int(installed[mod_id]) == int(mod["file_id"]) else "Update available"
	var text := "  " + str(mod["name"])
	if not str(mod["author"]).is_empty():
		text += "  —  " + str(mod["author"])
	if not note.is_empty():
		text += "      " + note
	var row := Button.new()
	row.text = text
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.custom_minimum_size = Vector2(0, 56)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_font_size_override("font_size", 18)
	row.clip_text = true
	row.pressed.connect(func() -> void: _view.open_mod(mod))
	return row


# ── installing a pack ─────────────────────────────────────────────────────────

func _install(pack: Dictionary) -> void:
	var pack_id := int(pack["id"])
	if not _batch_of(pack_id).is_empty() or _asking.has(pack_id) \
			or _view.downloader == null or _members_state != "ok":
		return
	# The members as they are NOW: the player may open another pack before
	# mod.io answers, and _members is the open pack's.
	var members := _members.duplicate()
	if not members.any(func(m: Dictionary) -> bool: return bool(m.get("dependencies", false))):
		_install_mods(pack, members)
		return
	# What its mods need comes down with them, as members, whether or not the
	# pack lists it: a member without it would arrive unable to run.
	_asking[pack_id] = true
	_view.notify(_toast(pack_id), "⏳", "Asking mod.io what %s needs…" % str(pack["name"]))
	_fill_detail()
	_view.fetch_needs(members, func(ok: bool, needs: Array[Dictionary], error: String) -> void:
		_asking.erase(pack_id)
		if not ok:
			_view.notify(_toast(pack_id), "❌", "%s: mod.io did not say what its mods need (%s)" % [
				str(pack["name"]), error], -1.0, MenuToasts.DWELL_FAIL)
			if _detail.visible:
				_fill_detail()
			return
		_install_mods(pack, ModCollectionPlan.with_needs(members, needs)))


func _install_mods(pack: Dictionary, mods: Array) -> void:
	if not _batch_of(int(pack["id"])).is_empty():
		return
	if _view.client != null and not _view.has_consent():
		return
	var plan := ModCollectionPlan.plan_install(mods, installed_files())
	var batch := {"id": int(pack["id"]), "name": str(pack["name"]), "keys": {}, "done": [],
		"staged": [], "skip": (plan["skip"] as Array).duplicate(true),
		"have": (plan["have"] as Array).duplicate(true), "ready": false, "cancelled": false}
	for mod: Dictionary in (plan["fetch"] as Array):
		var key := SpawnMenuModsView._job_key(int(mod["id"]))
		# A member already on its way down for some other reason is not fetched
		# twice, and is not this pack's to answer for.
		var other := _batch_owning(key)
		if not other.is_empty():
			(batch["skip"] as Array).append({"name": str(mod["name"]),
				"why": "comes with %s, queued before it" % str(other["name"])})
			_pending_tags.append({"pack": int(pack["id"]), "mod": mod, "confirmed": false})
			continue
		if _view.downloader.is_queued(key) or _view.has_review(key):
			(batch["skip"] as Array).append({"name": str(mod["name"]),
				"why": "is already being downloaded"})
			_pending_tags.append({"pack": int(pack["id"]), "mod": mod, "confirmed": false})
			continue
		(batch["keys"] as Dictionary)[key] = mod
	_batches.append(batch)
	if (batch["keys"] as Dictionary).is_empty():
		_finish_batch(batch)
		return
	for key: String in (batch["keys"] as Dictionary):
		var mod: Dictionary = (batch["keys"] as Dictionary)[key]
		_view.downloader.enqueue(key, str(mod["name"]), str(mod["download_url"]),
			int(mod["file_size"]), str(mod["file_md5"]),
			{"modio_id": int(mod["id"]), "file_id": int(mod["file_id"]),
				"profile_url": str(mod["profile_url"])})
	var count := (batch["keys"] as Dictionary).size()
	if _started(batch):
		_view.notify(_toast(int(batch["id"])), "⏳", "Downloading %s" % str(batch["name"]), 0.0)
	else:
		_view.notify(_toast(int(batch["id"])), "⏳", "%s queued — %d mod%s" % [
			str(batch["name"]), count, "" if count == 1 else "s"], -1.0, MenuToasts.DWELL_INFO)
	_fill_detail()


## One toast per pack, so two in the queue do not write over each other.
static func _toast(pack_id: int) -> String:
	return "mods:pack:%d" % pack_id


## Whether any of the batch's downloads has begun.
func _started(batch: Dictionary) -> bool:
	if not (batch["done"] as Array).is_empty():
		return true
	return _view.downloader != null \
		and (batch["keys"] as Dictionary).has(_view.downloader.current_key())


## Where a pack in the queue has got to, and the button that answers for it.
func _batch_status(batch: Dictionary, facts: VBoxContainer, actions: HBoxContainer) -> void:
	if bool(batch["ready"]):
		facts.add_child(MenuStyle.label("Downloaded — review it to install", 16, Color(0.95, 0.75, 0.35)))
		if _reviewing.is_empty() or int(_reviewing["id"]) != int(batch["id"]):
			var review := MenuStyle.row_button("Review and install", 20, 280, 56, false)
			review.add_theme_stylebox_override("normal", MenuStyle.rounded(MenuStyle.COLOR_BTN_DL, 6))
			review.pressed.connect(func() -> void: _open_review_of(batch))
			actions.add_child(review)
		return
	var total := (batch["keys"] as Dictionary).size()
	var started := _started(batch)
	var text := ""
	if started:
		text = "Downloading %d of %d" % [mini((batch["done"] as Array).size() + 1, total), total]
	else:
		var ahead := 0
		for other: Dictionary in _batches:
			if int(other["id"]) == int(batch["id"]):
				break
			if not bool(other["ready"]):
				ahead += 1
		text = "Queued — %d mod%s, " % [total, "" if total == 1 else "s"]
		text += ("behind %d pack%s" % [ahead, "" if ahead == 1 else "s"]) if ahead > 0 \
			else "behind the downloads ahead of it"
	facts.add_child(MenuStyle.label(text, 16, MenuStyle.COLOR_DESC))
	var cancel := MenuStyle.row_button("Cancel" if started else "Remove from queue",
		20, 200 if started else 260, 56, false)
	cancel.pressed.connect(func() -> void: _cancel_batch(batch))
	actions.add_child(cancel)


## A download began. The first of a queued pack moves it from Queued to
## Downloading, on the page and in its toast.
func on_job_started(key: String) -> void:
	var batch := _batch_owning(key)
	if batch.is_empty():
		return
	if (batch["done"] as Array).is_empty():
		_view.notify(_toast(int(batch["id"])), "⏳", "Downloading %s" % str(batch["name"]), 0.0)
	if _detail.visible:
		_fill_detail()


## One of a batch's downloads ended. `staged` is true when its pack was
## fetched and vetted and now waits in the view's reviews.
func on_job_done(key: String, staged: bool, error: String) -> void:
	var batch := _batch_owning(key)
	if batch.is_empty() or (batch["done"] as Array).has(key):
		return
	(batch["done"] as Array).append(key)
	var mod: Dictionary = (batch["keys"] as Dictionary)[key]
	if staged:
		(batch["staged"] as Array).append(key)
	else:
		(batch["skip"] as Array).append({"name": str(mod["name"]),
			"why": error if not error.is_empty() else "the download was cancelled"})
	var total := (batch["keys"] as Dictionary).size()
	var done := (batch["done"] as Array).size()
	if done < total:
		if not bool(batch["cancelled"]):
			_view.notify(_toast(int(batch["id"])), "⏳", "Downloading %s — %d of %d" % [
				str(batch["name"]), done + 1, total], float(done) / float(total))
		if _detail.visible:
			_fill_detail()
		return
	_finish_batch(batch)


## Stop a pack: what is downloading and what is still queued. What already
## came down is still offered, as a pack cut short.
func _cancel_batch(batch: Dictionary) -> void:
	if _batch_of(int(batch["id"])).is_empty() or bool(batch["ready"]):
		return
	batch["cancelled"] = true
	for key: String in (batch["keys"] as Dictionary).keys():
		if not (batch["done"] as Array).has(key):
			_view.downloader.cancel(key)


## Every download of `batch` is in. Ask its question (now, or when the one on
## screen is answered), or say why there is none to ask.
func _finish_batch(batch: Dictionary) -> void:
	var toast := _toast(int(batch["id"]))
	if (batch["staged"] as Array).is_empty():
		var skipped := (batch["skip"] as Array).size()
		_tag_have(batch)
		# Nothing of its own to confirm: the pack counts as installed for the
		# members it skipped, unless it was cancelled.
		for t: Dictionary in _pending_tags:
			if int(t["pack"]) == int(batch["id"]):
				t["confirmed"] = not bool(batch["cancelled"])
		_pending_tags = _pending_tags.filter(func(t: Dictionary) -> bool:
			return int(t["pack"]) != int(batch["id"]) or bool(t["confirmed"]))
		tag_pending()
		_drop(batch)
		var name := str(batch["name"])
		if bool(batch["cancelled"]):
			_view.notify(toast, "❌", "%s cancelled" % name, -1.0, MenuToasts.DWELL_INFO)
		elif skipped > 0:
			_view.notify(toast, "❌", "%s: nothing could be installed (%d skipped)" % [
				name, skipped], -1.0, MenuToasts.DWELL_FAIL)
		else:
			_view.notify(toast, "✅", "%s is already installed" % name, -1.0, MenuToasts.DWELL_OK)
		if _detail.visible:
			_fill_detail()
		return
	batch["ready"] = true
	_view.notify(toast, "✅", "%s is downloaded — review it to install" % str(batch["name"]),
		-1.0, MenuToasts.DWELL_FAIL)
	if _reviewing.is_empty():
		_open_review_of(batch)
	elif _detail.visible:
		_fill_detail()


func _drop(batch: Dictionary) -> void:
	for i in range(_batches.size()):
		if int(_batches[i]["id"]) == int(batch["id"]):
			_batches.remove_at(i)
			return


func _open_review_of(batch: Dictionary) -> void:
	_reviewing = batch
	_fill_review()
	_show(_review)


## The question on screen was answered: the next pack waiting for one, in
## queue order, else the pack the player had open, else the list they went
## back to while it came down (the detail page draws nothing with no pack open).
func _after_review() -> void:
	_reviewing = {}
	for batch: Dictionary in _batches:
		if bool(batch["ready"]):
			_open_review_of(batch)
			return
	if _open_pack.is_empty():
		_back_to_list()
		return
	_fill_detail()
	_show(_detail)


## Members that were already here are this pack's too, from now on.
func _tag_have(batch: Dictionary) -> void:
	var m := _view._manager()
	for mod: Dictionary in (batch["have"] as Array):
		var rec := m.find_by_source("modio_id", int(mod["id"])) as ModRecord
		if rec != null:
			m.set_source(rec.id, ModCollectionPlan.source_after_install(m.source(rec.id),
				int(mod["id"]), int(mod["file_id"]), str(mod["profile_url"]), int(batch["id"])))


## Record each skipped member whose pack is installed and that is here now as
## that pack's too. Run when a pack is confirmed and after every install.
func tag_pending() -> void:
	if _pending_tags.is_empty():
		return
	var m := _view._manager()
	var left: Array = []
	for t: Dictionary in _pending_tags:
		var mod: Dictionary = t["mod"]
		var rec := m.find_by_source("modio_id", int(mod["id"])) as ModRecord
		if not bool(t["confirmed"]) or rec == null:
			left.append(t)
			continue
		m.set_source(rec.id, ModCollectionPlan.source_after_install(m.source(rec.id),
			int(mod["id"]), int(mod["file_id"]), str(mod["profile_url"]), int(t["pack"])))
	_pending_tags = left


## Forget any pack's claim on the member downloaded as `key`: its own download
## failed or was thrown away, so a LATER install of it is not the pack's doing.
func drop_tags_for(key: String) -> void:
	_pending_tags = _pending_tags.filter(func(t: Dictionary) -> bool:
		return SpawnMenuModsView._job_key(int((t["mod"] as Dictionary)["id"])) != key)


## Show the question download `key` is answered in: its pack's review once the
## pack has all come down (or the one ahead of it in the queue), else the pack
## page as it stands while the rest comes down.
func show_review_of(key: String) -> void:
	var batch := _batch_owning(key)
	if batch.is_empty() or not bool(batch["ready"]):
		return
	_open_review_of(_reviewing if not _reviewing.is_empty() else batch)


func _fill_review() -> void:
	SpawnMenuModsView._clear(_review)
	var batch := _reviewing
	var staged: Array = batch["staged"]
	var title := MenuStyle.label("Install the pack %s?" % str(batch["name"]), 26, MenuStyle.COLOR_TITLE)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_review.add_child(title)
	if bool(batch["cancelled"]):
		_review.add_child(MenuStyle.hint("Cancelled part way: only what came down is here."))
	var waiting := 0
	for other: Dictionary in _batches:
		if bool(other["ready"]) and int(other["id"]) != int(batch["id"]):
			waiting += 1
	if waiting > 0:
		_review.add_child(MenuStyle.hint("%d more pack%s waiting to be reviewed after this one." % [
			waiting, "" if waiting == 1 else "s"]))
	_review.add_child(MenuStyle.hint(SpawnMenuModsView.TRUST_WARNING))

	# What each member replaces, and where two mods want the same file: the
	# pack's own members, and the mods already installed.
	var claims := SpawnMenuModsView.installed_claims()
	for key: String in staged:
		if not _view.has_review(key):
			continue
		var review := _view.review(key)
		var manifest: ModManifest = review["manifest"]
		claims[manifest.name] = Array(manifest.shadowing_claims())
		_review.add_child(MenuStyle.label("%s  %s" % [manifest.name, manifest.version],
			18, MenuStyle.COLOR_LICENSE))
		for path: String in manifest.shadowing_claims():
			_review.add_child(MenuStyle.label("    Replaces " + path, 15, MenuStyle.COLOR_BTN_UPD))
	for line: String in ModCollectionPlan.conflicts(claims):
		_review.add_child(MenuStyle.label("! " + line, 16, MenuStyle.COLOR_BTN_UPD))

	var have: Array = batch["have"]
	if not have.is_empty():
		_review.add_child(MenuStyle.hint("%d already installed." % have.size()))
	for entry: Dictionary in (batch["skip"] as Array):
		_review.add_child(MenuStyle.label("Skipped %s: %s" % [str(entry["name"]), str(entry["why"])],
			15, MenuStyle.COLOR_BTN_UPD))

	_review.add_child(HSeparator.new())
	var enable := MenuStyle.switch_row(_review, "Enable all", false)
	var actions := MenuStyle.hbox(10)
	_review.add_child(actions)
	var install := MenuStyle.row_button("Install %d mod%s" % [staged.size(),
		"" if staged.size() == 1 else "s"], 20, 260, 56, false)
	install.add_theme_stylebox_override("normal", MenuStyle.rounded(MenuStyle.COLOR_BTN_DL, 6))
	install.pressed.connect(func() -> void: _confirm(enable.button_pressed))
	actions.add_child(install)
	var discard := MenuStyle.row_button("Discard", 20, 200, 56, false)
	discard.pressed.connect(_discard)
	actions.add_child(discard)


func _confirm(enable: bool) -> void:
	if _reviewing.is_empty():
		return
	var batch := _reviewing
	var pack_id := int(batch["id"])
	var installed := 0
	var failed := PackedStringArray()
	var m := _view._manager()
	# The whole pack is one change to the loader: one write, one rebuild of the
	# lists, not one of each per member in the frame the button was pressed.
	m.hold_changes()
	for key: String in (batch["staged"] as Array):
		# A member whose review is gone was answered some other way: reading it
		# here stopped the install half way with the loader's changes still held,
		# and nothing was saved or redrawn for the rest of the session.
		if not _view.has_review(key):
			continue
		var mod: Dictionary = (batch["keys"] as Dictionary)[key]
		var manifest: ModManifest = _view.review(key)["manifest"]
		var source := ModCollectionPlan.source_after_install(m.source(manifest.id),
			int(mod["id"]), int(mod["file_id"]), str(mod["profile_url"]), pack_id)
		var out := _view.finish_review(key, source, enable)
		if bool(out.get("ok", false)):
			installed += 1
		else:
			failed.append("%s (%s)" % [str(mod["name"]), str(out.get("error", ""))])
	_tag_have(batch)
	for t: Dictionary in _pending_tags:
		if int(t["pack"]) == pack_id:
			t["confirmed"] = true
	tag_pending()
	var name := str(batch["name"])
	_drop(batch)
	m.release_changes()
	var toast := _toast(pack_id)
	var step := _view.next_step(installed != 1)
	if not failed.is_empty():
		_view.notify(toast, "❌", "%s: not installed — %s" % [name, ", ".join(failed)],
			-1.0, MenuToasts.DWELL_FAIL)
	else:
		_view.notify(toast, "✅", "%s installed (%d mod%s)%s" % [name, installed,
			"" if installed == 1 else "s", "" if step.is_empty() else " — " + step],
			-1.0, MenuToasts.DWELL_FAIL)
	_after_review()


func _discard() -> void:
	if _reviewing.is_empty():
		return
	var batch := _reviewing
	for key: String in (batch["staged"] as Array):
		_view.discard_review(key)
	# A pack not installed claims none of the members it skipped.
	_pending_tags = _pending_tags.filter(func(t: Dictionary) -> bool:
		return int(t["pack"]) != int(batch["id"]))
	_drop(batch)
	_view.notify(_toast(int(batch["id"])), "❌", "%s discarded" % str(batch["name"]),
		-1.0, MenuToasts.DWELL_INFO)
	_after_review()


# ── removing a pack ───────────────────────────────────────────────────────────

func _remove(pack: Dictionary) -> void:
	var sources := {}
	for rec: ModRecord in Mods.all_mods():
		if not Mods.source(rec.id).is_empty():
			sources[rec.id] = Mods.source(rec.id)
	var plan := ModCollectionPlan.plan_remove(int(pack["id"]), sources)
	var restart := false
	var failed := 0
	for id: String in (plan["remove"] as Array):
		var out: Dictionary = Mods.remove(id)
		if not bool(out.get("ok", false)):
			failed += 1
		restart = restart or bool(out.get("restart", false))
	var kept: Dictionary = plan["keep"]
	for id: String in kept:
		Mods.set_source(id, kept[id])
	var removed := (plan["remove"] as Array).size() - failed
	var msg := "Removed %d mod%s" % [removed, "" if removed == 1 else "s"]
	if not kept.is_empty():
		msg += ", kept %d you also wanted" % kept.size()
	if restart:
		msg += " — some at the next restart"
	_view.notify("mods:pack", "❌" if failed > 0 else "✅", msg, -1.0, MenuToasts.DWELL_OK)
	_fill_detail()
