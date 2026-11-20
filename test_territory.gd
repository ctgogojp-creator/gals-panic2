extends SceneTree
## 実行: godot --headless --path <プロジェクトdir> -s test_territory.gd
## 終了コード 0 = 全部OK。AIエージェントは territory_grid.gd を触るたびにこれを実行すること。

const TG = preload("res://territory_grid.gd")

var fails := 0
var checks := 0
var DIRS := {"U": Vector2i.UP, "D": Vector2i.DOWN, "L": Vector2i.LEFT, "R": Vector2i.RIGHT}


func _init() -> void:
	test_straight_cut()
	test_cross_is_rejected()
	test_start_from_claimed_area_and_join_frame()
	test_non_rectangle_shape()
	test_u_turn_blocked()
	test_two_enemies_keep_both_sides()
	test_no_enemy_keeps_largest()
	test_fuzz()
	print("---- %d checks, %d failed ----" % [checks, fails])
	quit(1 if fails > 0 else 0)


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func walk(g, moves: String, enemies: Array = []) -> int:
	var last := -1
	for c in moves:
		last = g.step(DIRS[c], true, enemies)
	return last


## 20x15 の盤面。外枠は x=0,19 / y=0,14。プレイヤー初期位置は (10,14)。
func test_straight_cut() -> void:
	var g = TG.new(20, 15)
	var enemy := Vector2i(15, 5)
	var r: int = walk(g, "UUUUUUUUUUUUUU", [enemy]) # 14回: 13マス描いて外枠(10,0)に接続
	check(r == TG.StepResult.CLOSED, "直線で外枠から外枠へ繋ぐと確定する（四角く囲まなくても取れる）")
	check(g.get_cell(Vector2i(5, 7)) == TG.Cell.CLAIMED, "敵と反対側(左)が自陣になった")
	check(g.get_cell(Vector2i(15, 5)) == TG.Cell.EMPTY, "敵のいる側(右)は取られない")
	check(g.last_gained == 13 + 117, "増えたセル数 = 線13 + 面積117 (got %d)" % g.last_gained)
	check(g.count_claimed_playable() == 130 and absf(g.get_claim_ratio() - 130.0 / 234.0) < 1e-6, "占有率カウンタが数え直しと一致")


func test_cross_is_rejected() -> void:
	var g = TG.new(20, 15)
	var enemy := Vector2i(15, 5)
	walk(g, "UUUUU", [enemy])           # (10,9)
	walk(g, "RR", [enemy])              # (12,9)
	walk(g, "DD", [enemy])              # (12,11)
	walk(g, "L", [enemy])               # (11,11)
	var before: PackedByteArray = g.cells.duplicate()
	var r: int = walk(g, "L", [enemy])      # (10,11) は自分の線 → 交差
	check(r == TG.StepResult.SELF_CROSS, "自分の線に交差すると SELF_CROSS")
	check(g.cells == before, "SELF_CROSS では盤面を一切変更しない（陣は取れない）")
	g.cancel_trail()
	var trail_left := 0
	for v in g.cells:
		if v == TG.Cell.TRAIL:
			trail_left += 1
	check(trail_left == 0 and not g.drawing and g.player == Vector2i(10, 14), "cancel_trail でTRAIL消去＆スタート地点に戻る")
	check(g.count_claimed_playable() == 0, "交差後に陣は増えていない")


func test_start_from_claimed_area_and_join_frame() -> void:
	var g = TG.new(20, 15)
	var enemy := Vector2i(15, 5)
	walk(g, "UUUUUUUUUUUUUU", [enemy])  # 左半分を取る。プレイヤーは (10,0)
	check(g.player == Vector2i(10, 0), "確定後プレイヤーは接続した外枠セルに居る")
	walk(g, "DDDDDDD", [enemy])         # 新しい縁(x=10)を下へ歩く → (10,7)
	check(g.player == Vector2i(10, 7) and not g.drawing, "新しくできた縁の上を歩ける")
	# 自陣の縁から右へ描き、右の外枠(19,7)につなぐ
	var r: int = walk(g, "RRRRRRRRR", [enemy])
	check(r == TG.StepResult.CLOSED, "自陣の縁から描き始めて外枠につなぐと確定する")
	check(g.get_cell(Vector2i(15, 10)) == TG.Cell.CLAIMED, "敵と反対側(下)が自陣")
	check(g.get_cell(Vector2i(15, 5)) == TG.Cell.EMPTY, "敵側(上)は残る")
	# 自陣の縁から描き始めて、別の自陣の縁につなぐ（外枠でなくてよい）
	var g2 = TG.new(20, 15)
	walk(g2, "UUUUUUUUUUUUUU", [enemy])
	walk(g2, "DDDD", [enemy])           # (10,4)
	walk(g2, "RRRR", [enemy])           # (14,4) まで描く
	walk(g2, "DDDD", [enemy])           # (14,8)
	var r2: int = walk(g2, "LL", [enemy])   # (12,8)
	check(r2 == TG.StepResult.DRAWING, "途中経過 DRAWING")
	r2 = walk(g2, "L", [enemy])         # (11,8) 隣は縁(10,8)
	r2 = walk(g2, "L", [enemy])         # (10,8) に接続
	check(r2 == TG.StepResult.CLOSED, "自陣→自陣の接続でも確定する")


func test_non_rectangle_shape() -> void:
	var g = TG.new(20, 15)
	var enemy := Vector2i(15, 5)
	walk(g, "LLLLL", [enemy])           # 外枠沿いに (5,14)
	var r: int = walk(g, "UULLUULLL", [enemy])  # 階段状 → (0,10) 接続
	check(r == TG.StepResult.CLOSED, "階段状（非矩形）でも確定する")
	check(g.get_cell(Vector2i(2, 12)) == TG.Cell.CLAIMED, "階段の内側(2,12)が自陣")
	check(g.get_cell(Vector2i(4, 13)) == TG.Cell.CLAIMED, "階段の内側(4,13)が自陣")
	check(g.get_cell(Vector2i(6, 13)) == TG.Cell.EMPTY, "階段の外側(6,13)は残る")
	check(g.get_cell(Vector2i(2, 9)) == TG.Cell.EMPTY, "階段の外側(2,9)は残る")


func test_u_turn_blocked() -> void:
	var g = TG.new(20, 15)
	walk(g, "UU", [Vector2i(15, 5)])
	var r: int = g.step(Vector2i.DOWN, true, [Vector2i(15, 5)])
	check(r == TG.StepResult.BLOCKED and g.drawing, "真後ろへの逆走はBLOCKED（死なない・盤面不変）")


func test_two_enemies_keep_both_sides() -> void:
	var g = TG.new(20, 15)
	var enemies := [Vector2i(5, 5), Vector2i(15, 5)]
	walk(g, "UUUUUUUUUUUUUU", enemies)
	check(g.last_gained == 13, "両側に敵がいれば線(13マス)しか増えない (got %d)" % g.last_gained)
	check(g.get_cell(Vector2i(5, 5)) == TG.Cell.EMPTY and g.get_cell(Vector2i(15, 5)) == TG.Cell.EMPTY, "両側とも残る")


func test_no_enemy_keeps_largest() -> void:
	var g = TG.new(20, 15)
	walk(g, "UUUUUUUUUUUUUU", [])
	check(g.get_cell(Vector2i(5, 7)) == TG.Cell.EMPTY and g.get_cell(Vector2i(15, 7)) == TG.Cell.CLAIMED, "敵ゼロなら大きい方(左117マス)を残し、小さい方(右104マス)を取る")


# ---------------------------------------------------------------- ランダム総当たり

func test_fuzz() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261119
	var dir_list := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	var closes := 0
	var crosses := 0
	var bad := ""
	for round in 60:
		var g = TG.new(30, 22, round % 2 == 0)
		var enemy := Vector2i(15, 11)
		for i in 3000:
			var r: int = g.step(dir_list[rng.randi() % 4], true, [enemy])
			if r == TG.StepResult.SELF_CROSS:
				crosses += 1
				g.cancel_trail()
			elif g.drawing and g.player == enemy:
				g.cancel_trail() # 敵に線を踏まれた扱い
			if r == TG.StepResult.CLOSED:
				closes += 1
			bad = invariants(g, enemy)
			if bad != "":
				break
		if bad != "":
			print("fuzz round %d: %s" % [round, bad])
			break
	check(bad == "", "ランダム操作%d回の確定・%d回の交差でも不変条件が崩れない" % [closes, crosses])
	check(closes > 200 and crosses > 200, "ファズが十分に回った（確定%d / 交差%d）" % [closes, crosses])


## 盤面の不変条件を調べる。問題なければ "" を返す。
func invariants(g, enemy: Vector2i) -> String:
	var trail_cells := 0
	var empty_cells := 0
	for v in g.cells:
		if v == TG.Cell.TRAIL:
			trail_cells += 1
		elif v == TG.Cell.EMPTY:
			empty_cells += 1
	if trail_cells != g.trail.size():
		return "TRAILセル数(%d)と trail 配列(%d)が不一致" % [trail_cells, g.trail.size()]
	if g.drawing:
		if g.get_cell(g.player) != TG.Cell.TRAIL:
			return "描画中なのにプレイヤーがTRAIL上に居ない"
	else:
		if g.get_cell(g.player) != TG.Cell.CLAIMED:
			return "非描画中なのにプレイヤーがCLAIMED上に居ない"
	for x in g.width:
		if g.get_cell(Vector2i(x, 0)) != TG.Cell.CLAIMED or g.get_cell(Vector2i(x, g.height - 1)) != TG.Cell.CLAIMED:
			return "外枠が壊れた"
	if g.get_cell(enemy) != TG.Cell.EMPTY:
		return "敵のセルが EMPTY でない"
	if g.count_claimed_playable() != roundi(g.get_claim_ratio() * (g.width - 2) * (g.height - 2)):
		return "占有率カウンタが数え直しと不一致"
	# 取りこぼし検査: 線を引いていない時、全 EMPTY が敵から4連結で到達できること
	if not g.drawing:
		var seen := {}
		var q: Array[Vector2i] = [enemy]
		seen[enemy] = true
		while not q.is_empty():
			var p: Vector2i = q.pop_back()
			for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				var n: Vector2i = p + d
				if g.get_cell(n) == TG.Cell.EMPTY and not seen.has(n):
					seen[n] = true
					q.append(n)
		if seen.size() != empty_cells:
			return "敵と隔離された EMPTY が残っている（取りこぼし）: %d vs %d" % [seen.size(), empty_cells]
	return ""
