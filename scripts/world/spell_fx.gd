# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
class_name SpellFX
extends RefCounted
## Efekty czarów używane przez walkę i podgląd pipeline’u.


static func play(parent: Node3D, id: String, origin: Vector3, aim: Vector3, recipients: Array = [], slot := 0, hit := true, footprint: Array = []) -> Tween:
	var spell := Spellcasting.spell(id)
	var profile := DB.entry("spell_fx", id)
	var color := Color.from_string(str(profile.get("color", "")), Color("#b58bfc"))
	var seconds := float(profile.get("seconds", 0.45))
	var root := Node3D.new()
	root.name = "SpellFX"
	parent.add_child(root)
	var tw := root.create_tween().set_parallel()
	var start := origin + Vector3.UP * 1.08
	var finish := aim + Vector3.UP * 0.95
	var area: Dictionary = spell.get("area", {})
	for point in footprint:
		var tile := PlaneMesh.new()
		tile.size = Vector2.ONE * 0.88
		var mark := _mesh(root, tile, point + Vector3.UP * 0.08, Color(color, 0.24))
		tw.tween_property(mark, "transparency", 1.0, seconds * 0.85)
	if not hit and id in ["fire_bolt", "ray_of_frost"]:
		finish += (finish - start).normalized() * 1.2 + Vector3.UP * 0.35
	match profile.get("kind", "bolt"):
		"bolt", "volley":
			var count := 1
			if profile.kind == "volley":
				count = int(spell.get("darts", 1)) + maxi(0, slot - int(spell.level)) * int(spell.get("upcast_darts", 0))
			var side := (finish - start).cross(Vector3.UP).normalized()
			for i in count:
				var offset := side * (i - (count - 1) * 0.5) * 0.18
				var orb := _orb(root, start + offset, color, 0.13)
				var delay := i * seconds * 0.25 / count
				tw.tween_property(orb, "position", finish + offset * 0.25, seconds * 0.62).set_delay(delay)
				tw.tween_property(orb, "transparency", 1.0, seconds * 0.12).set_delay(delay + seconds * 0.62)
			if id == "fire_bolt":
				for i in 4:
					var ember := _orb(root, start, color.lerp(Color.WHITE, 0.12), 0.095 - i * 0.014)
					var delay := seconds * (0.04 + i * 0.05)
					ember.hide()
					tw.tween_callback(ember.show).set_delay(delay)
					tw.tween_property(ember, "position", finish, seconds * 0.61).set_delay(delay)
					tw.tween_property(ember, "transparency", 1.0, seconds * 0.70).set_delay(delay)
			if hit or id != "fire_bolt":
				_ring(root, tw, finish - Vector3.UP * 0.8, color, 0.65, seconds * 0.35, seconds * 0.60)
				if id == "fire_bolt":
					_sparks(root, tw, finish, color, seconds, 0.62, false)
		"beam":
			if start.distance_squared_to(finish) > 0.01:
				var beam := _ray(root, start, finish, color, 0.07)
				tw.tween_property(beam, "transparency", 1.0, seconds)
				var core := _ray(root, start, finish, color.lerp(Color.WHITE, 0.8), 0.033)
				tw.tween_property(core, "transparency", 1.0, seconds * 0.75)
			if hit:
				_sparks(root, tw, finish, color, seconds, 0.18, true)
		"pillar":
			var pillar := _ray(root, aim + Vector3.UP * 0.12, aim + Vector3.UP * 3.7, color, 0.18)
			tw.tween_property(pillar, "transparency", 1.0, seconds)
			_ring(root, tw, aim + Vector3.UP * 0.12, color, 0.85, seconds)
		"burst":
			var radius := float(area.get("radius", 0.5)) + 0.45
			_ring(root, tw, aim + Vector3.UP * 0.12, color, radius, seconds)
			for i in (0 if id == "sleep" else 10):
				var direction := Vector3(cos(TAU * i / 10.0), 0.3, sin(TAU * i / 10.0))
				var spark := _orb(root, aim + Vector3.UP * 0.35, color, 0.08)
				tw.tween_property(spark, "position", spark.position + direction * radius, seconds)
				tw.tween_property(spark, "transparency", 1.0, seconds)
		"cone":
			var forward := Vector3(aim.x - origin.x, 0, aim.z - origin.z).normalized()
			if id == "thunderwave":
				var front := Node3D.new()
				root.add_child(front)
				front.position = origin + Vector3.UP * 0.28
				var distance := float(area.get("length", 3))
				for i in (range(-4, 4) if not forward.is_zero_approx() else []):
					var a := forward.rotated(Vector3.UP, i * PI / 16.0) * distance
					var b := forward.rotated(Vector3.UP, (i + 1) * PI / 16.0) * distance
					var segment := _ray(front, a, b, color, 0.14)
					tw.tween_property(segment, "transparency", 1.0, seconds * 0.45).set_delay(seconds * 0.55)
				front.scale = Vector3.ONE * 0.16
				tw.tween_property(front, "scale", Vector3.ONE, seconds).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
			for wave in (0 if id == "thunderwave" else 3):
				var delay := wave * seconds * 0.14
				var tint := color.lerp(Color.WHITE, 0.12 + wave * 0.10)
				for i in range(-4, 5):
					var angle := clampf((i + (wave - 1) * 0.32) * PI / 16.0, -PI / 4.0, PI / 4.0)
					var direction := forward.rotated(Vector3.UP, angle)
					var spark := _orb(root, start, tint, 0.12 + 0.025 * wave)
					spark.basis = Basis(Quaternion(Vector3.UP, direction if not direction.is_zero_approx() else Vector3.UP))
					spark.scale = Vector3(0.9, 2.6, 0.9)
					var distance := float(area.get("length", 3)) * (1.0 - wave * 0.17)
					var end := origin + direction * distance + Vector3.UP * (0.35 + 0.24 * wave)
					spark.visible = wave == 0
					if wave > 0:
						tw.tween_callback(spark.show).set_delay(delay)
					tw.tween_property(spark, "position", end, seconds * 0.72).set_delay(delay).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
					tw.tween_property(spark, "scale", spark.scale * 1.7, seconds * 0.72).set_delay(delay)
					tw.tween_property(spark, "transparency", 1.0, seconds * 0.36).set_delay(delay + seconds * 0.36)
		"aura":
			for recipient in recipients if not recipients.is_empty() else [aim]:
				if id == "shield":
					var dome := _orb(root, recipient + Vector3.UP * 0.85, Color(color, 0.30), 0.9)
					dome.scale = Vector3(0.8, 1.1, 0.8)
					tw.tween_property(dome, "transparency", 1.0, seconds)
				for i in (1 if id == "shield" else 3):
					var position: Vector3 = recipient + Vector3.UP * (0.18 + i * 0.44)
					_ring(root, tw, position, color, 0.78, seconds * 0.78, i * seconds * 0.10)
	tw.chain().tween_callback(root.queue_free)
	return tw


static func _mesh(parent: Node3D, shape: Mesh, position: Vector3, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = shape
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	m.material_override = material
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	m.position = position
	return m


static func _orb(parent: Node3D, position: Vector3, color: Color, radius: float) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	return _mesh(parent, mesh, position, color)


static func _ray(parent: Node3D, start: Vector3, finish: Vector3, color: Color, radius: float) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.height = start.distance_to(finish)
	mesh.top_radius = radius * 0.6
	mesh.bottom_radius = radius
	mesh.radial_segments = 12
	var ray := _mesh(parent, mesh, (start + finish) * 0.5, color)
	ray.basis = Basis(Quaternion(Vector3.UP, (finish - start).normalized()))
	return ray


static func _ring(parent: Node3D, tw: Tween, position: Vector3, color: Color, radius: float, seconds: float, delay := 0.0) -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.91
	mesh.outer_radius = 1.0
	mesh.rings = 24
	mesh.ring_segments = 8
	var ring := _mesh(parent, mesh, position, color)
	ring.scale = Vector3.ONE * 0.12
	ring.visible = delay == 0.0
	if delay > 0.0:
		tw.tween_callback(ring.show).set_delay(delay)
	tw.tween_property(ring, "scale", Vector3.ONE * radius, seconds).set_delay(delay)
	tw.tween_property(ring, "transparency", 1.0, seconds).set_delay(delay)


static func _sparks(parent: Node3D, tw: Tween, center: Vector3, color: Color, seconds: float, phase: float, ice: bool) -> void:
	var delay := seconds * phase
	var life := seconds - delay
	for i in 7:
		var direction := Vector3(cos(TAU * i / 7.0), 0.5 + 0.15 * (i % 3), sin(TAU * i / 7.0))
		var spark := _orb(parent, center, color.lerp(Color.WHITE, 0.42), 0.075)
		if ice:
			spark.scale = Vector3(0.45, 2.6, 0.45)
			spark.basis = Basis(Quaternion(Vector3.UP, direction.normalized())).scaled(spark.scale)
		spark.hide()
		tw.tween_callback(spark.show).set_delay(delay)
		tw.tween_property(spark, "position", center + direction * 0.52, life).set_delay(delay)
		tw.tween_property(spark, "transparency", 1.0, life).set_delay(delay)
