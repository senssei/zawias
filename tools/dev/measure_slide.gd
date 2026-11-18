extends SceneTree
## Poślizg stóp w grze: postać idzie prosto 8 pól z daną prędkością, mierzymy prędkość stopy podporowej
## w świecie (powinna być bliska 0). Użycie: godot --headless -s tools/dev/measure_slide.gd -- <id> <m/s>

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var id := args[0] if args.size() > 0 else "pc_fighter"
	var speed := float(args[1]) if args.size() > 1 else Actor.RUN_SPEED
	if args.size() > 3:   # nadpisanie naturalnej prędkości animacji: <gait> <m/s>
		Actor.gait_natural[args[2]] = float(args[3])
	var a := Actor.new()
	root.add_child(a)
	a.setup(id, id, Color.WHITE)
	a.try_load_model([id])
	a.place(Vector2i(0, 0))
	await process_frame
	var sk: Skeleton3D = _find(a, "Skeleton3D")
	var feet := [sk.find_bone("DEF-foot.L"), sk.find_bone("DEF-foot.R")]
	var path := []
	for i in 9:
		path.append(Vector2i(i, 0))
	var tw := a.walk(path, speed)
	# zapis pozycji stóp w środkowej części trasy, potem analiza (próg kontaktu liczony z tego odcinka)
	var rec := []
	var t := 0.0
	while tw.is_running():
		var dt := await _frame()
		t += dt
		if t > 1.0 and a.position.x < 7.0:
			rec.append([(sk.global_transform * sk.get_bone_global_pose(feet[0])).origin,
				(sk.global_transform * sk.get_bone_global_pose(feet[1])).origin])
	var ymin := INF
	for r in rec:
		ymin = minf(ymin, minf(r[0].y, r[1].y))
	var slides := []
	for k in range(1, rec.size()):
		for f in 2:
			if rec[k][f].y < ymin + 0.03 and rec[k - 1][f].y < ymin + 0.03:
				var v: Vector3 = (rec[k][f] - rec[k - 1][f]) * 60.0
				slides.append(Vector2(v.x, v.z).length())
	if slides.is_empty():
		print("brak próbek")
		quit(1)
		return
	slides.sort()
	print("%s @ %.2f m/s: poślizg stopy podporowej mediana %.2f m/s (%d próbek)" % [id, speed, slides[slides.size() / 2], slides.size()])
	quit()


func _frame() -> float:
	await process_frame
	return 1.0 / 60.0   # uruchamiać z --fixed-fps 60


func _find(n: Node, cls: String) -> Node:
	if n.get_class() == cls:
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r:
			return r
	return null
