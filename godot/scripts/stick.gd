class_name Stick
extends Control
## A big, forgiving multi-touch joystick. `vertical` locks it to up/down (the speed stick).

var vertical := false
var on_change: Callable        # (x: float, y: float), y up = positive
var knob := Vector2.ZERO
var touch := -1
var travel := 90.0
var knob_color := Color(1, 0.5, 0.1)


func _init(is_vertical: bool, cb: Callable) -> void:
	vertical = is_vertical
	on_change = cb
	size = Vector2(170, 290) if vertical else Vector2(290, 290)
	knob_color = Color(0.2, 0.75, 1) if vertical else Color(1, 0.45, 0.1)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed and touch == -1 and get_global_rect().grow(40).has_point(e.position):
			touch = e.index
			_move(e.position)
			get_viewport().set_input_as_handled()
		elif not e.pressed and e.index == touch:
			release()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == touch:
			_move(d.position)


func release() -> void:
	touch = -1
	knob = Vector2.ZERO
	if on_change.is_valid():
		on_change.call(0.0, 0.0)
	queue_redraw()


func _move(p: Vector2) -> void:
	var c := get_global_rect().get_center()
	var v := p - c
	if vertical:
		v.x = 0
	if v.length() > travel:
		v = v.normalized() * travel
	knob = v
	var sx := 0.0 if absf(v.x / travel) < 0.12 else v.x / travel
	var sy := 0.0 if absf(v.y / travel) < 0.12 else v.y / travel
	on_change.call(sx, -sy)
	queue_redraw()


func _draw() -> void:
	var c := size / 2
	var plate := Color(1, 1, 1, 0.16)
	if vertical:
		draw_style_box(_round(plate, 70), Rect2(c - Vector2(65, 135), Vector2(130, 270)))
	else:
		draw_circle(c, 135, plate)
	var ic := Color(1, 1, 1, 0.7)
	if vertical:
		# Fast: two up chevrons. Stop: a square.
		_tri(c + Vector2(0, -122), 0, 20, ic)
		_tri(c + Vector2(0, -100), 0, 20, ic)
		draw_rect(Rect2(c + Vector2(-15, 98), Vector2(30, 30)), ic)
	else:
		_tri(c + Vector2(0, -112), 0, 22, ic)
		_tri(c + Vector2(0, 112), PI, 22, ic)
		_tri(c + Vector2(-112, 0), -PI / 2, 22, ic)
		_tri(c + Vector2(112, 0), PI / 2, 22, ic)
	var k := c + knob
	draw_circle(k, 62, Color(1, 1, 1))
	draw_circle(k, 57, knob_color.darkened(0.25))
	draw_circle(k + Vector2(-12, -14), 34, knob_color)


func _tri(at: Vector2, ang: float, s: float, col: Color) -> void:
	var pts := PackedVector2Array([Vector2(0, -s), Vector2(s, s * 0.7), Vector2(-s, s * 0.7)])
	for i in pts.size():
		pts[i] = at + pts[i].rotated(ang)
	draw_colored_polygon(pts, col)


static func _round(col: Color, r: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(r)
	return sb
