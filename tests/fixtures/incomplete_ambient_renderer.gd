extends Node

## Deliberately incomplete renderer used to verify strict interface reporting.

var configured := false


func configure(_profile: Dictionary = {}) -> void:
	configured = true
