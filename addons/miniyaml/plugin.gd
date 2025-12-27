@tool
extends EditorPlugin

func _enable_plugin():
	add_autoload_singleton("YAML", "res://addons/miniyaml/miniyaml.gd")

func _disable_plugin():
	remove_autoload_singleton("YAML")
