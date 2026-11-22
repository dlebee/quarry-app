class_name Tap
extends Control
## A touch target drawn by a callback: `painter.call(self)` draws, `on_tap.call()` on press.

var on_tap: Callable
var painter: Callable
var animated := false


func _init(sz: Vector2, paint: Callable, tap: Callable = Callable(), anim := false) -> void:
	size = sz
	painter = paint
	on_tap = tap
	animated = anim
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_d: float) -> void:
	if animated and is_visible_in_tree():
		queue_redraw()


func _input(event: InputEvent) -> void:
	if not on_tap.is_valid() or not is_visible_in_tree():
		return
	if event is InputEventScreenTouch and event.pressed and get_global_rect().has_point(event.position):
		get_viewport().set_input_as_handled()
		on_tap.call()


func _draw() -> void:
	if painter.is_valid():
		painter.call(self)
