class_name Heights
extends RefCounted
## Height grid baked by Blender (scripts/make_*_terrain.py): int32 N, float32 size, N*N float32.

var n := 0
var size := 1.0
var half := 0.5
var h := PackedFloat32Array()


func _init(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("missing " + path)
		return
	n = f.get_32()
	size = f.get_float()
	half = size / 2.0
	h = f.get_buffer(n * n * 4).to_float32_array()


func at(x: float, z: float) -> float:
	if n == 0:
		return 0.0
	var fx := clampf((x + half) / size * (n - 1), 0.0, n - 1.001)
	var fz := clampf((z + half) / size * (n - 1), 0.0, n - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var a := h[j * n + i]
	var b := h[j * n + i + 1]
	var c := h[(j + 1) * n + i]
	var d := h[(j + 1) * n + i + 1]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)


func normal(x: float, z: float) -> Vector3:
	var e := size / (n - 1)
	return Vector3(at(x - e, z) - at(x + e, z), 2.0 * e, at(x, z - e) - at(x, z + e)).normalized()
