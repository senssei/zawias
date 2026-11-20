# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
extends SceneTree
## Mierzy naturalną prędkość chodu animacji (m/s przy speed_scale=1): jak szybko stopa podporowa
## przesuwa się do tyłu względem modelu. Użycie: godot --headless -s tools/dev/measure_gait.gd -- <id> [anim...]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var id := args[0] if args.size() > 0 else "pc_fighter"
	var anims: Array = args.slice(1) if args.size() > 1 else ["walk", "run"]
	var a := Actor.new()
	root.add_child(a)
	a.setup(id, id, Color.WHITE)
	if not a.try_load_model([id]):
		print("brak modelu ", id)
		quit(1)
		return
	await process_frame
	var sk: Skeleton3D = _find(a, "Skeleton3D")
	var feet := []
	for i in sk.get_bone_count():
		var n := sk.get_bone_name(i).to_lower()
		if "foot" in n and not "ik" in n:
			feet.append(i)
	print("stopy: ", feet.map(func(i): return sk.get_bone_name(i)))
	var ap: AnimationPlayer = a._anim
	for wanted in anims:
		var an: String = a._anim_name(wanted)
		if an == "":
			continue
		ap.play(an)
		var length := ap.current_animation_length
		var n := 120
		var samples := []
		for k in n + 1:
			ap.seek(length * k / n, true)
			var ys := []
			var zs := []
			for f in feet:
				var g: Vector3 = (sk.global_transform * sk.get_bone_global_pose(f)).origin
				ys.append(g.y)
				zs.append(g.z)
			samples.append([ys, zs])
		# prędkość stopy podporowej (blisko ziemi: do 3 cm nad najniższym położeniem) w osi przód-tył;
		# trucht ma fazę lotu, więc „niższa stopa” nie wystarcza
		var ymin := INF
		for smp in samples:
			ymin = minf(ymin, minf(smp[0][0], smp[0][1]))
		var vels := []
		var dt := length / n
		for k in n:
			for f in 2:
				if samples[k][0][f] < ymin + 0.03 and samples[k + 1][0][f] < ymin + 0.03:
					vels.append(absf(samples[k + 1][1][f] - samples[k][1][f]) / dt)
		vels.sort()
		print("%s: długość %.2f s, prędkość stopy (mediana) %.2f m/s" % [wanted, length, vels[vels.size() / 2]])
	quit()


func _find(n: Node, cls: String) -> Node:
	if n.get_class() == cls:
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r:
			return r
	return null
