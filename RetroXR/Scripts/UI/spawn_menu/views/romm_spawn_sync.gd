## RommSpawnSync — the SPAWN tab's RomM handlers: sync, download and cache.
##
## They read as notification code, and most of what they do is raise a toast in
## the menu's stack. But every one of them ends by repainting a row, a list or an
## index of the view that owns this, which is why they answer to it rather than
## to the menu: the view's row model, its owed rebuilds and its open page are
## what they touch.
##
## Keys are namespaced "romm:" so they cannot collide with the scraper's
## box/wheel/label/manual keys.
class_name RommSpawnSync
extends RefCounted

var _view: SpawnMenuSpawnView = null

## Terminal outcomes that happened while the menu was closed, flushed on open.
var _pending_notices: Array[Dictionary] = []
## rom_id -> percent, so a recycled row can show live progress when it scrolls
## back into view mid-download.
var _progress_pct: Dictionary = {}
## rom_id -> game name, remembered from the start of the download. Only the
## started signal carries it, and looking it up again per tick would mean a
## catalog scan thousands of times over one ROM — the same reason the row index
## below is resolved once.
var _dl_labels: Dictionary = {}
## rom_id -> which attempt is running, 0 for the first. Shown on the progress bar
## so a transfer that silently started over is visible as one.
var _dl_attempt: Dictionary = {}
## Row index of the in-flight download, resolved once when it starts.
var _dl_row_index: int = -1


func _init(view: SpawnMenuSpawnView) -> void:
	_view = view


## The RomM services are the menu's; the view hands them over once they are set.
## Method callables, never lambdas: a lambda would keep this object alive through
## the connection after its view is gone.
func connect_services() -> void:
	_view.romm_client.auth_failed.connect(_on_romm_auth_failed)
	_view.romm_client.reachability_changed.connect(_on_romm_reachability_changed)
	_view.romm_cache.changed.connect(_on_romm_cache_changed)
	_view.romm_catalog.sync_started.connect(_on_romm_sync_started)
	_view.romm_catalog.sync_progress.connect(_on_romm_sync_progress)
	_view.romm_catalog.sync_finished.connect(_on_romm_sync_finished)
	_view.romm_catalog.sync_aborted.connect(_on_romm_sync_aborted)
	_view.romm_downloader.download_started.connect(_on_romm_dl_started)
	_view.romm_downloader.download_progress.connect(_on_romm_dl_progress)
	_view.romm_downloader.download_retrying.connect(_on_romm_dl_retrying)
	_view.romm_downloader.download_finished.connect(_on_romm_dl_finished)
	_view.romm_downloader.download_cancelled.connect(_on_romm_dl_cancelled)
	_view.romm_downloader.cache_evicted.connect(_on_romm_cache_evicted)


## The percentage a row shows for a download in flight.
func progress_pct(rom_id: int) -> int:
	return int(_progress_pct.get(rom_id, 0))


## The menu came out: say what finished while it was away, then ask the server
## whether anything moved.
func on_menu_shown() -> void:
	_flush_romm_notices()
	_romm_check_for_changes()


## The cheapest possible "did anything change?" — /api/stats is public and ~100
## bytes. If the fingerprint matches, the library provably hasn't changed and no
## /api/roms call is made at all.
func _romm_check_for_changes() -> void:
	var romm_config := _view.romm_config
	if romm_config == null or not romm_config.is_configured():
		return
	_view.romm_client.stats(func(ok: bool, stats: Dictionary) -> void:
		if not is_instance_valid(_view):
			print("[RommSync] stats answered after the spawn view closed; ignored")
			return
		if not ok or stats.is_empty():
			return
		var changed := not romm_config.stats_unchanged(stats)
		print("[RommSync] stats %s: was %s now %s" % [
			"changed" if changed else "unchanged",
			RommConfig.fingerprint_text(romm_config.last_stats),
			RommConfig.fingerprint_text(stats)])
		if changed:
			romm_config.last_stats = stats
			if not romm_config.save_config():
				push_warning("[RommSync] could not save %s: the fingerprint will read as changed again next launch"
					% RommConfig.config_path())
		# The cached list is already on screen; this corrects it in the
		# background and costs nothing visible.
		_view.romm_fetch_platforms()
		if changed:
			_queue_delta_syncs()
	)


## The library moved since we last looked, so at least one synced platform is
## stale. Delta, not full: the watermark turns "one game was added" into a single
## small page instead of every page of the platform.
##
## Only platforms that already have an index are queued. One that has never been
## opened has nothing to bring up to date, and syncing it here would fetch a
## library the player has not asked to browse.
##
## Deletions are NOT reconciled by a delta — the merge only adds and updates, so
## a game removed on the server survives until a full sync. OPTIONS > Sync All
## remains the reconcile.
func _queue_delta_syncs() -> void:
	var stale: Array[String] = []
	for sid: String in _view._romm_platforms:
		if RommCatalog.has_index(sid):
			stale.append(sid)
	if stale.is_empty() or _view._menu == null:
		return
	print("[RommSync] queuing delta syncs for %d indexed platform(s): %s" % [stale.size(), ", ".join(stale)])
	_view._menu.queue_romm_sync(stale, false)


## Toasts can only be seen while the menu panel is open. A 4 GB download keeps
## running while the user plays, so terminal outcomes are queued and flushed
## (coalesced) the next time the menu opens, rather than vanishing unseen.
func _romm_notify_or_queue(key: String, icon: String, msg: String, dwell: float,
						   progress: float = -1.0) -> void:
	if _view._menu_shown:
		_view.notify(key, icon, msg, progress, dwell)
	elif progress < 0.0:
		# Only outcomes are worth keeping for later. Queueing progress ticks
		# would bank hundreds of them and then replay a finished download.
		_pending_notices.append({"ok": icon == "✅", "msg": msg})


## Called when the menu becomes visible.
func _flush_romm_notices() -> void:
	if _pending_notices.is_empty():
		return
	var done := 0
	var failed := 0
	for n: Dictionary in _pending_notices:
		if bool(n["ok"]):
			done += 1
		else:
			failed += 1
	_pending_notices.clear()

	# One summary, not a replay of every toast.
	if done > 0 and failed == 0:
		_view.notify("romm:flush", "✅", "%d download%s finished" % [done, "" if done == 1 else "s"],
			-1.0, MenuToasts.DWELL_INFO)
	elif done == 0 and failed > 0:
		_view.notify("romm:flush", "❌", "%d download%s failed" % [failed, "" if failed == 1 else "s"],
			-1.0, MenuToasts.DWELL_FAIL)
	else:
		_view.notify("romm:flush", "✅", "%d finished · %d failed" % [done, failed],
			-1.0, MenuToasts.DWELL_FAIL)


func _on_romm_auth_failed(detail: String) -> void:
	push_warning("[SpawnView] auth failed: %s" % detail)
	_view.notify("romm:conn", "❌", "RomM sign-in expired — check OPTIONS", -1.0, MenuToasts.DWELL_FAIL)


## Fires only on a transition, so a dead server can't produce a toast stream.
##
## Repaints in BOTH directions: the cached index keeps listing server-only titles
## whether or not the server answers, so the rows have to say which of them can
## still be acted on — and say it again when it comes back.
func _on_romm_reachability_changed(reachable: bool) -> void:
	if is_instance_valid(_view._romm_list):
		_view._romm_list.rebind_visible()
	_view._romm_update_empty_label()
	if reachable:
		return
	_view.notify("romm:conn", "❌", "RomM unreachable", -1.0, MenuToasts.DWELL_FAIL)


## Fires twice: once before the first request, then again with the real total
## once page one lands. The toast updates in place.
func _on_romm_sync_started(systemid: String, total: int) -> void:
	var label := _view._system_label(systemid)
	if total <= 0:
		_view.notify("romm:sync:" + systemid, "⏳", "Fetching the %s list from RomM…" % label, -1.0)
	else:
		_view.notify("romm:sync:" + systemid, "⏳",
			"Syncing %s · 0 / %s" % [label, _commas(total)], 0.0)
	# The toolbar button is this platform's stop button for as long as this runs.
	update_resync_btn()


func _on_romm_sync_progress(systemid: String, done: int, total: int) -> void:
	var frac := (float(done) / float(total)) if total > 0 else -1.0
	_view.notify("romm:sync:" + systemid, "⏳",
		"Syncing %s · %s / %s" % [_view._system_label(systemid), _commas(done), _commas(total)], frac)


func _on_romm_sync_finished(systemid: String, ok: bool, added: int, removed: int, error: String) -> void:
	var key := "romm:sync:" + systemid
	var label := _view._system_label(systemid)
	# Back to offering a resync, whichever way this ended.
	update_resync_btn()

	if not ok:
		push_warning("[RommSync] %s failed: %s" % [systemid, error])
		_view.notify(key, "❌", "RomM sync failed — %s" % error, -1.0, MenuToasts.DWELL_FAIL)
		# Still announced: this is what pumps the sync queue, so returning
		# quietly strands every platform behind the one that failed.
		_view.romm_state_changed.emit()
		return

	# Record the watermark so the next open can skip the network entirely.
	var meta := RommCatalog.read_meta(systemid)
	_view.romm_config.set_sync_state(systemid, str(meta.get("updated_after", "")), int(meta.get("total", 0)))
	print("[RommSync] %s finished: +%d -%d, watermark %s" % [systemid, added, removed,
		str(meta.get("updated_after", "")) if meta.has("updated_after") else "(none)"])
	if not _view.romm_config.save_config():
		push_warning("[RommSync] could not save %s: %s will full-sync again next launch"
			% [RommConfig.config_path(), systemid])

	if added > 0:
		_view.notify(key, "✅", "%s · %d new game%s" % [label, added, "" if added == 1 else "s"],
			-1.0, MenuToasts.DWELL_INFO)
	elif removed > 0:
		_view.notify(key, "✅", "%s · %d game%s removed" % [label, removed, "" if removed == 1 else "s"],
			-1.0, MenuToasts.DWELL_INFO)
	else:
		_view.notify(key, "✅", "%s · up to date" % label, -1.0, 1.5)

	# The open detail page is showing a stale list — rebuild it against the new index.
	if systemid == _view._romm_detail_systemid:
		_view._owe(false, false, true)
	_view.romm_state_changed.emit()


## Paint the toolbar button for what pressing it will do right now — resync this
## platform, or stop the sync that is already running on it.
func update_resync_btn() -> void:
	var btn := _view._romm_resync_btn
	if not is_instance_valid(btn):
		return
	var label := _view._system_label(_view._romm_detail_systemid)
	if _romm_syncing_this_platform():
		btn.text = String.chr(MenuIcons.CROSS)
		btn.add_theme_color_override("font_color", MenuIcons.TINT_DELETE)
		btn.tooltip_text = "Stop syncing %s" % label
	else:
		btn.text = String.chr(MenuIcons.RETRY)
		btn.remove_theme_color_override("font_color")
		btn.tooltip_text = \
			"Check RomM for changes to %s, and drop entries the server has lost" % label


func _romm_syncing_this_platform() -> bool:
	var catalog := _view.romm_catalog
	return catalog != null and catalog.is_syncing() \
		and catalog.syncing_systemid() == _view._romm_detail_systemid


## Resync, or stop — whichever the button is currently offering. Everything the
## stop needs to tidy up happens in _on_romm_sync_aborted, so that a cancel from
## OPTIONS cleans up identically.
##
## Delta by default — this is the "I just added a game" button, and a full
## re-fetch of a large platform is ~20 pages. A platform with no index yet is
## already having a full sync started for it by the open itself.
func on_resync_pressed(systemid: String) -> void:
	if _view._menu == null:
		return
	var catalog := _view.romm_catalog
	if catalog != null and catalog.is_syncing() \
			and catalog.syncing_systemid() == systemid:
		catalog.abort_sync()
		return
	if not RommCatalog.has_index(systemid):
		return
	_view._menu.queue_romm_sync([systemid], false)


## Tidy up after a cancelled sync, from wherever it was cancelled.
##
## The half-written index is not a concern — pages go to index.jsonl.part and
## swap in atomically at the end, so the previous index survives untouched.
## Emitting romm_state_changed is what advances the queue: only this platform
## was stopped, and anything queued behind it still wants to run. OPTIONS clears
## the queue before it aborts, so its Stop really does stop everything.
func _on_romm_sync_aborted(systemid: String) -> void:
	# The catalog's teardown stop is not announced (RommCatalog._exit_tree), so
	# this only runs for a stop someone asked for. `if _menu` inside the notify
	# wrappers would not catch a freed menu — a freed Object is still truthy.
	if not is_instance_valid(_view._menu):
		return
	_view.notify_clear("romm:sync:" + systemid)
	_view.notify("romm:conn", "⏹", "Stopped syncing %s" % _view._system_label(systemid),
		-1.0, MenuToasts.DWELL_OK)
	update_resync_btn()
	_view._romm_update_empty_label()
	_view.romm_state_changed.emit()


func _on_romm_dl_started(rom_id: int, label: String, total_bytes: int) -> void:
	_dl_labels[rom_id] = label
	# A ROM tapped again after a failed run must not inherit that run's count.
	_dl_attempt[rom_id] = 0
	_view.notify_clear("romm:dl:%d:why" % rom_id)
	_view.notify("romm:dl:%d" % rom_id, "⬇", "%s · %s" % [label, ByteSize.human(total_bytes)], 0.0)
	# Resolved once; a scan per progress tick would be O(rows) on an 11k list.
	_dl_row_index = -1
	var rows := _view._romm_rows
	for i in rows.size():
		if _view.romm_catalog.rom_id_at(int(rows[i].get("index", -1))) == rom_id:
			_dl_row_index = i
			break


## Progress arrives every 256 KB — ~700 times for a 178 MB ROM, ~16,000 for a
## 4 GB one. Rebinding the whole visible window each time meant thousands of
## row binds, each doing a gamelist scan and several file_exists calls on the
## main thread; with an emulator running that reads as a hard freeze. Only act
## when the displayed percentage actually changes, and touch one row.
func _on_romm_dl_progress(rom_id: int, received: int, total: int) -> void:
	# Clamped because the total is the catalog's size for the ROM, while the body
	# may be a container the server generated around it — a few hundred bytes
	# larger. "101%" reads as a bug in the bar rather than what it is.
	var frac := clampf(float(received) / float(total), 0.0, 1.0) if total > 0 else -1.0
	var pct := int(frac * 100.0) if frac >= 0.0 else 0
	if int(_progress_pct.get(rom_id, -1)) == pct:
		return
	_progress_pct[rom_id] = pct
	var attempt := int(_dl_attempt.get(rom_id, 0))
	_view.notify("romm:dl:%d" % rom_id, "⬇",
		"%s%s · %d%% · %s / %s" % [_romm_dl_label(rom_id),
			"" if attempt <= 0 else "  (attempt %d)" % attempt, pct,
			ByteSize.human(received), ByteSize.human(total)], frac)
	if is_instance_valid(_view._romm_list):
		_view._romm_list.rebind_index(_dl_row_index)


## The reason gets a toast of its own, not the download's.
##
## A retry resumes within its backoff and the first progress tick lands 256 KB
## later, which on a LAN is immediate — sharing the download's key meant the only
## place the failure was ever named got overwritten before it could be read, and
## a run that failed three times looked like one that simply stopped. This one
## dwells like any other failure, beside the bar rather than on top of it.
func _on_romm_dl_retrying(rom_id: int, attempt: int, max_attempts: int, reason: String) -> void:
	_dl_attempt[rom_id] = attempt
	_view.notify("romm:dl:%d" % rom_id, "⏳",
		"%s — retry %d/%d" % [_romm_dl_label(rom_id), attempt, max_attempts], -1.0)
	_view.notify("romm:dl:%d:why" % rom_id, "⚠",
		"%s — %s" % [_romm_dl_label(rom_id),
			reason if not reason.is_empty() else "the transfer failed"],
		-1.0, MenuToasts.DWELL_FAIL)


## What this download is fetching, for every bar after the first.
func _romm_dl_label(rom_id: int) -> String:
	var label := str(_dl_labels.get(rom_id, ""))
	return label if not label.is_empty() else "Download"


func _on_romm_dl_finished(rom_id: int, ok: bool, path: String, error: String) -> void:
	var key := "romm:dl:%d" % rom_id
	var menu := _view._menu
	if ok:
		_romm_notify_or_queue(key, "✅", "%s ready" % path.get_file().get_basename(), MenuToasts.DWELL_OK)
		# A ROM that arrived by download is one nobody browsed to, so nobody is
		# going to press Scrape on it either. Queued, not fetched now: the
		# scraper is rate-limited and a batch download would outrun it.
		if menu != null and "auto_scraper" in menu:
			var scraper: AutoScraper = menu.get("auto_scraper")
			if scraper != null:
				scraper.request(path, AutoScraper.systemid_for_path(path))
	else:
		_romm_notify_or_queue(key, "❌", "%s — %s" % [_romm_dl_label(rom_id), error],
			MenuToasts.DWELL_FAIL)
		# The server answered that this row's file is gone, which is the one
		# failure that will never come good on a retry. Take the row out now
		# rather than leaving a button that can only fail again — the next sync
		# would have done it, but not before the player pressed it twice.
		if error == RommHttp.ERR_GONE and _view.romm_catalog != null \
				and not _view._romm_detail_systemid.is_empty():
			_view.romm_catalog.remove_rows(_view._romm_detail_systemid, [rom_id])
	_dl_labels.erase(rom_id)
	_dl_attempt.erase(rom_id)
	# The final message names the same failure, so leaving the retry note up
	# would say it twice.
	_view.notify_clear("romm:dl:%d:why" % rom_id)
	_dl_row_index = -1
	_view._romm_meta_cache.clear()
	# The download merged its game into gamelist.json through its own manager.
	if ok and _view.gamelist_manager != null:
		_view.gamelist_manager.invalidate(AutoScraper.systemid_for_path(path))
	_view._invalidate_local_scan()
	_view._owe(false, false, true)
	# A game downloaded from the global search must turn into one you can spawn
	# there too: left as it was, its row still offered the download, and a second
	# tap fetched the file again (the downloader does not check the cache). Only
	# the local half re-runs; a server row reads its path from the cache as it
	# draws, and RomM's answer has not changed.
	var browser := _view._cartridges_browser
	if ok and browser != null \
			and browser.current_systemid() == GameSearch.PAGE_ID \
			and SearchFold.fold(_view._gs_query).length() >= GameSearch.MIN_QUERY:
		print("[GameSearch] rom %d downloaded; refreshing '%s'" % [rom_id, _view._gs_query])
		_view._global_search_local(_view._gs_query)
		_view._render_global_results()


func _on_romm_dl_cancelled(rom_id: int) -> void:
	_dl_labels.erase(rom_id)
	_dl_attempt.erase(rom_id)
	_view.notify_clear("romm:dl:%d" % rom_id)
	_view.notify_clear("romm:dl:%d:why" % rom_id)
	_view._owe(false, false, true)


## Files silently vanishing from a library reads as data loss — always say so.
func _on_romm_cache_evicted(freed_bytes: int, count: int) -> void:
	_view.notify("romm:cache", "🗑", "Freed %s — removed %d game%s"
		% [ByteSize.human(freed_bytes), count, "" if count == 1 else "s"], -1.0, 4.0)


## Eviction can change a server row from local to downloadable and can remove
## companion-only rows, so rebuild the model rather than merely re-binding it.
func _on_romm_cache_changed() -> void:
	_view._romm_meta_cache.clear()
	_view._invalidate_local_scan()
	_view._owe(false, false, true)


static func _commas(n: int) -> String:
	var s := str(n)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out
