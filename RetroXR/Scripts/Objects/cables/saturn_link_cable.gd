## A Sega Saturn Link Cable (HSS-0107 in Japan, the Taisen cable) -- Daytona USA
## CCE, Gungriffon II, Hyper Duel, Steeldom and Virtual On all take one, with a
## disc in each console.
##
## Two consoles, one wire, peers: everything PsxLinkCable already does. Which
## SH-2 drives the clock is the games' business and the core's; the room only
## says the two machines share a wire. _console_end walks to a PsxLinkPort, and a
## SaturnLinkPort is one, so nothing here needs overriding but the name.
class_name SaturnLinkCable
extends PsxLinkCable
