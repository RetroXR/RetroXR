## A model that comes in colors, for the suites: it remembers the one it was
## told to be. Named by path in a model row (system_tests, spawn_menu_tests).
extends RetroSystemModelDefault

var told: Array[String] = []


func apply_variant(variant: String) -> void:
	told.append(variant)
