# Ethernet LAN — network adapters, a patch lead and an eight-port hub

A GameCube with its Broadband Adapter (DOL-015) and a fat PlayStation 2 with its
Network Adapter (SCPH-10281) are each an RJ45 socket in the room. An Ethernet cable
from that socket to a hub — or straight to another console's — puts the consoles on
one LAN, the way a LAN party was cabled. Mario Kart: Double Dash!! shows **LAN MODE**
on its title menu, and Gran Turismo 4's **Multi-LAN Race** links up to six consoles.

## The wire: `ethernet-1`

Both cores speak the same protocol on the frontend's link bus (LinkCoordinator, the
serial-link API the other leads use):

- **one message is one Ethernet II frame**: destination MAC first, no preamble, no
  FCS. A full 1514-byte frame fits `MAX_PAYLOAD` (4096).
- **a message goes to everyone on the bus**, as a hub repeats a frame to every port.
  A core drops what is not addressed to it, exactly as a NIC's filter does.
- the bus is `LinkConnectGroup` over every console the room's walk finds; there is no
  switch, router or DHCP server on the wire. Each core answers its own console's DHCP
  locally, with an address only it holds (`10.x.y.z/8`, the tail of its MAC; gateway
  `10.0.0.1`, where nothing answers), so a game's "obtain automatically" just works.

Because both cores speak `ethernet-1`, a GameCube and a PlayStation 2 can share one
hub. They hear each other's broadcasts and ignore them.

## The core halves

**PS2** (our fork, branch `ethernet-lan`, `pcsx2/DEV9/link_eth.{h,cpp}` and
`link_adapter.h`). The SPEED expansion's SMAP gets a `LinkAdapter` NetAdapter; the
console attaches **link port 1** (i.LINK is 0). Core option `pcsx2_dev9_eth`:
`disabled` (no adapter), `enabled` (Sockets — the host's own network, which the room
never offers), `link` (the cable). Read at content load. MAC `00:04:1F` + bytes salted
with the frontend's handle, so consoles sharing a BIOS still differ. The adapter's
time is the IOP's: a 1 ms promise, half-promise grain, an ETH IOP event, and the
ETHiopReset/ETHvsync alignment FW.cpp uses for i.LINK, so cabled consoles line their
frames up instead of taking turns. Env: `LRPS2_ETH_LOG`, `LRPS2_ETH_PCAP=<dir>`
(one pcap per console), `LRPS2_ETH_DIAG`, `LRPS2_ETH_AHEAD_US`, `LRPS2_ETH_ALIGN`.

**Dolphin** (our fork, branch `ethernet-lan`, `Core/HW/EXI/BBA/LinkBBA.cpp`,
`DolphinLibretro/EthernetLink.cpp`). A new EXI device, `EXIDeviceType::EthernetLink`
(**15**), is the BBA with `BBADeviceType::Link` behind it; the console attaches **link
port 4** (0–3 are the controller sockets). Core option `dolphin_gc_sp1`: `"15"` is the
Ethernet Link Cable, `"255"` nothing. Read at boot. The MAC is Nintendo's OUI and three
random bytes, made per run and never written to the config. A CoreTiming event
(`BBALinkTick`) polls the bus with a 1 ms promise.

## The room half

| class | what it is |
|---|---|
| `EthernetPort` | a `PsxLinkPort` taking `ethernet_plug`; `get_machine()` walks through a `RetroExpansion` to the console it is seated on; `get_hub()`; a link LED |
| `EthernetCable` | a `PsxLinkCable` (`ethernet_cable.tscn`, 2.4 m blue Cat5, RJ45 both ends), in group `ethernet_cable` |
| `EthernetHub` | a pickable box with eight `EthernetPort`s (`Port1`..`Port8`) |
| `EthernetBus` | the static resolver every lead defers to — ILinkBus's shape |
| the adapters | expansion units `gamecube_broadband_adapter` (socket `serial_port_1`) and `ps2_network_adapter` (`expansion_bay`), each row carrying `ethernet_port` |

**The socket is on the CARD.** A unit whose row has `ethernet_port` grows an
`EthernetPort` named `EthernetPort` on its +Y face — the end left showing once
`seat_back_card_slot` has put it through the console's back panel (the stand-in box
seats both cards there, clear of the A/V row and the i.LINK socket). On the table the
socket is nobody's; seated, it is the console's. Seating or pulling the card fires
`host_changed`, and the card asks the lead in its socket to `_resolve()` — nothing
else would, because the lead itself did not move.

**Seating the card is what switches the core's adapter on**
(`ForcedCoreOptions.ethernet_adapter`): `dolphin_gc_sp1` 15/255 and
`pcsx2_dev9_eth` link/disabled, both directions, so a stale option file never leaves a
console with a network it has no card for. The Wii is always pinned to 255 (it shares
`dolphin.opt`). Both cores read the option once, at load, so a card moved while the
console runs shows a toast: switch it off and on for it to count.

**A slim PS2 has the socket built in.** A model returns its link port from
`RetroSystemModel.builtin_ethernet_port()` (default -1) and places the socket in
`place_builtin_ethernet_port`; `RetroSystem` then builds it on the console, and
`_hardware_ids()` counts the Network Adapter as present for the forced options without
naming a card among what is seated (`expansion_ids()` is for boot recipes and saves).

**No lead decides its own LAN.** `EthernetBus.settle` walks every lead, unions each
lead's two ends (a console through its adapter, or a hub), and calls
`LinkConnectGroup` once per connected set of two or more consoles, each with ITS port
(4 for a GameCube, 1 for a PS2), ordered by `LinkCable.stable_key`. Stale LANs are
parted first and only their orphans disconnected — ILinkBus's reasoning, kept in a
separate bookkeeping so a settle of one wire never parts the other's buses. A lead's
`linked_machines()` is the whole LAN, its plugs are in `any_link_plug`, so
`RetroSystem.net_link_bus()` finds a hub's far consoles; `net_refresh_link_cables`
rejoins a LAN once per frame however many spokes ask. A console switching back on
re-states its LAN after `RESTATE_COOLDOWN` frames, for `ILinkBus.watch`'s reason.

Spawn menu: the cable and the hub under the GameCube and the PlayStation 2. Saves: the
lead is a `LEAD_SCENES` row, the hub a pose-only `PLAIN_SCENES` row; a plug records its
socket as the card (`EthernetPort.get_device()` stops at a `RetroExpansion`), the hub
(`on_av_topology_changed` no-op) or the console. `netplay_session.LINK_PORTS` is
`[0, 1, 4]`.

## Verified with the real cores (2026-10-21)

Driven with `Tools/link/lan_probe.tscn` (windowed, per-console roots, a command file;
its header has the usage):

- **Mario Kart: Double Dash!!**, two GameCubes: LAN MODE appears, "2 Nintendo
  GameCube systems are connected", a Versus race on Mushroom Bridge finished 1st/2nd at
  60 fps (~18000 frames). The probe sets `SetControllerPortDevice(0, 1)` for a pad, and
  MKDD's menus want the analog stick and long holds.
- **Gran Turismo 4**, two PlayStation 2s: a full Multi-LAN Race, P1/P2, identical race
  clocks, 60 fps, ~5000 frames each way. GT4's procedure: create a network
  configuration (DHCP: yes); the HOST is set at the race menu → Option → Options → LAN
  Settings (Host: Yes, No. of Players: N), which does not survive a reboot; clients
  Connect first, the host last. `Tools/link/gt4_lan_two.txt` is the scripted walk.

Not yet run: six PS2s on GT4, more than two GameCubes, and a GameCube and a PS2 on one
hub with cores (the room's walk for that is tested; the cores ignore each other's
frames by design).

## Known issues

- **GT4 with the hardware Vulkan GS faults the GPU at the LAN car select** (nvlddmkm
  Event 13 "WIDTH CT Violation", then a reset and VK device lost). Not the cable — the
  same scene in software GS (`Software (HW)` in the probe's roots) runs. The peer then
  waits on the dead console forever, which is what a lockstep link is meant to do.
- Netplay does not replicate a card being seated (pre-existing: no expansion seating
  crosses the network), and pcsx2 is not in `NetplayCores`, so a PS2 LAN is local only.

## Tests

`ethernet_tests` (186 checks): plug gating both ways against i.LINK, the cable scene
and its sweep group, the spawn and save rows, the catalog rows and forced options, the
hub's eight sockets with facing and a seated plug outside the box, each adapter's socket
on the table and seated (owner, save round trip, facing out of the console, the core's
option on and off), a slim shell's built-in socket, a three-PS2 LAN through a hub
(pull a spoke, then another), two GameCubes and a PS2 across two chained hubs with
their own ports, and a card pulled out of a console taking it off the LAN and back.
