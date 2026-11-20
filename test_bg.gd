extends SceneTree
## プレイ中の背景(水着)がステージごとに切り替わるかの検証。
## 2-1 / 3-1 で 1-1 の水着が残るバグの再発防止。

var checks := 0
var fails := 0
var main


func ok(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("FAIL: " + msg)
	else:
		print("OK: " + msg)


func _init() -> void:
	main = preload("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main._start_game()
	main.enemies.foes.clear()

	var t1 = main.bg_tex
	var m1: PackedByteArray = main.mask_bytes
	ok(t1 == main._stage_texture(0, 1), "ST1(1-1) の背景は gal1_1")

	main.stage_number = 1
	main._start_stage()
	var t2 = main.bg_tex
	var m2: PackedByteArray = main.mask_bytes
	ok(main.gal_index == 0 and main.stage_in_gal == 2, "ST2 は 1-2")
	ok(t2 == main._stage_texture(0, 2), "ST2(1-2) の背景は gal1_2")
	ok(t2 != t1, "ST2 の背景が ST1 と別画像")
	ok(m2 != m1, "ST2 のシルエットマスクも変わっている")

	main.stage_number = 2
	main._start_stage()
	var t3 = main.bg_tex
	var m3: PackedByteArray = main.mask_bytes
	ok(main.gal_index == 0 and main.stage_in_gal == 3, "ST3 は 1-3")
	ok(t3 == main._stage_texture(0, 3), "ST3(1-3) の背景は gal1_3")
	ok(t3 != t2 and t3 != t1, "ST3 の背景が ST1/ST2 のどちらも違う")
	ok(m3 != m2 and m3 != m1, "ST3 のシルエットマスクも変わっている")

	# 4ステージ目(同じ女の子でレベル2)も確認
	main.stage_number = 3
	main._start_stage()
	ok(main.gal_index == 1 and main.stage_in_gal == 1, "ST4 は 2-1")
	ok(main.bg_tex == main._stage_texture(1, 1), "ST4(2-1) の背景は gal2_1")

	# 背景は Main 自身の _draw() で描く -> 再描画が仕掛けられているか
	var src := FileAccess.get_file_as_string("res://main.gd")
	var i := src.find("func _apply_stage_visuals")
	var body := src.substr(i, 420)
	ok("queue_redraw()" in body, "_apply_stage_visuals が Main 自身の再描画を要求している")

	print("---- %d checks, %d failed ----" % [checks, fails])
	quit(1 if fails > 0 else 0)
