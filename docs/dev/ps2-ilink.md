# The PlayStation 2's i.LINK — a cable and a six-port hub

## The core half

Our PS2 fork (`github.com/RetroXR/ps2`, branch `retroxr`, `pcsx2/FW.cpp`) models the
console's i.LINK controller. Each console attaches ONE link port, index 0, protocol
`ps2-ilink-1394`, at the IOP's 36.864 MHz, behind the core option `pcsx2_ilink`
(default on, restart to change). It is a real IEEE 1394 bus, not a pair: every console
on the wire is a node, bus index is the PHY id, the highest is root, up to 64 nodes.

Verified by the fork: two consoles on Time Crisis II and Gran Turismo 3, and **six** on
GT3's i.LINK Battle (all six get Console IDs, two race, four show trackside views).
Consoles sharing one NVRAM get distinct EUI-64s because each salts its i.LINK ID with
the handle the frontend gave it. Savestates carry the controller (`iLink` block); the
cable itself is not saved. `LRPS2_ILINK_LOG=1` logs bus resets, self-IDs and every
packet; `LRPS2_FW_LOG=1` every register access.

## The room half

| class | what it is |
|---|---|
| `ILinkPlug` | an `RcaPlug` in group `ilink_plug`, **and** in `LinkPlug.ANY_GROUP` |
| `ILinkPort` | a `PsxLinkPort` taking `ilink_plug`; `get_hub()` beside `get_machine()` |
| `ILinkCable` | a `PsxLinkCable` (`ilink_cable.tscn`, 1.8 m, black 4-pin ends) |
| `ILinkHub` | a pickable box with six `ILinkPort`s (`ilink_hub.tscn`) |
| `ILinkBus` | the static resolver every lead defers to |

A PS2 wears the socket because `SystemInfo/ps2.tres` sets `serial_port`, and
`RetroSystemModelDefault.build_serial_port` picks `ilink_port.tscn` for `ps2` — on the
back panel beside the A/V row, where every stand-in console puts its link socket. The
spawn menu offers both the lead and the hub under the PlayStation 2 (and in the
generic list). Saves: the lead is a `LEAD_SCENES` row, the hub a pose-only
`PLAIN_SCENES` row; a lead records its own seat as the hub plus `Port1`..`Port6`,
which works because the hub answers `on_av_topology_changed` (a no-op, `RfSwitch`'s
trick) so `RcaPort.get_device()` finds it.

**No lead decides its own bus.** `ILinkBus.settle` walks every lead in the
`ilink_cable` group, unions each lead's two ends (console or hub), and calls
`LinkConnectGroup` once per connected set with two or more consoles, ordered by
`LinkCable.stable_key` so every netplay peer names the same bus head. Two hubs joined
by a lead are one bus. Stale buses are parted FIRST and only their orphans are
disconnected: `ConnectGroup` takes a listed port off its old bus by itself, so parting
a console that is moving would be a second reset for nothing, and parting it after the
join would undo it.

A lead's `linked_machines()` is the WHOLE bus, not its two ends, and its plugs are in
`any_link_plug`, so `RetroSystem.net_link_bus()` sees a hub's far consoles. The PS1,
Saturn and Jaguar plugs are NOT in that group; their sweep only finds a machine's own
lead. (pcsx2 is not in `NetplayCores` today, so no session covers a PS2 yet; the lead
still routes every join and part through `netplay_took_bus`.)

A seated plug's nose sits inside the hub's shell and a seated plug is kinematic, so the
hub adds a collision exception for whatever a socket picks up — exactly what
`RetroSystem` does for its own sockets — or plugging in shoves the hub off the table.

## The one behaviour a hub makes easy to hit

GT3's driver (Polyphony's PDI1394.IRX over Sony's ILINK.IRX) only learns who is on the
bus from a bus reset that arrives AFTER it has started. Every join and part is a reset
for everyone on the wire, and a console switching back on re-states its whole bus after
`ILinkBus.RESTATE_COOLDOWN` physics frames (the same as the PlayStation lead's re-state).
What is left is a console cabled before it booted that then never sees another plug
move: it sits on its Console ID screen. Replugging any lead on that bus fixes it.

The hub is unpowered, which a real one is not (the PS2's 4-pin port carries no bus
power). Deliberately: a hub that stays dark until a player finds its brick looks broken.

## Tests

`link_tests` covers the plug gating both ways, the spawn and save rows, the PS2's socket
(and that a PlayStation has none), the hub's six sockets, their facing (measured in the
hub's frame: authored inside out, the step is negative), a seated shell standing
outside the box with its collision exception made and undone, a three-console bus
through one hub found from every lead and from `net_link_bus()`, a pulled spoke, a hub
left with one console, two chained hubs and a plain console-to-console pair beside them.
All with real `system.tscn` consoles and real socket seating; no core, so the bus is
checked through `ILinkBus`'s bookkeeping rather than peer counts.

**Owed:** a real multi-console run through the ROOM — hub, leads and GT3 in a headset
or a windowed probe. The fork verified six consoles on the bus directly; this layer is
covered by the headless suite only.
