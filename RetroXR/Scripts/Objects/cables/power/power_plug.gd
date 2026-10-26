class_name PowerPlug
extends RcaPlug

## A wall plug or an appliance connector. Which one is its `connector`, set in
## the cord's scene; what else it fits (a two-prong US plug in a grounded outlet)
## is Connectors.ALSO_FITS.
func _init() -> void:
	connector = "nema_5_15_plug"

