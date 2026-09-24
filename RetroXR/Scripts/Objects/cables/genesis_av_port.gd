## The Genesis Model 2's A/V OUT: a 9-pin mini-DIN carrying the picture and both
## audio channels. How one hole carries three signals is MultiAvPort's business; the
## only thing that is this console's own is which leads it takes.
##
## Its own group rather than the Nintendo ones. The shells are nothing alike, and even
## Sega's own sockets differ across the machine's life: the Model 1 wears an 8-pin DIN
## that this lead does not fit, which is why a Model 1 A/V cable is a separate product.
## A Model 3 (same 9-pin socket) would belong on THIS group.
class_name GenesisAvPort
extends MultiAvPort


func plug_group() -> String:
	return "genesis_av_plug"
