@tool
extends EditorPlugin

func _enable_plugin():
	add_autoload_singleton("SGYP", "res://addons/sgyp/sgyp.gd")

func _disable_plugin():
	remove_autoload_singleton("SGYP")