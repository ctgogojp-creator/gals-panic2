class_name TerritoryGrid
extends RefCounted
## ギャルズパニック（Qix型）陣取りの「ロジックだけ」を担当するクラス。
## 描画・入力・敵の動きは一切含まない。ゲーム側はこのクラスの step() を呼ぶだけ。
##
## 設計の肝（ここを変えると必ずバグる）:
##  1. 世界はすべて整数グリッド。座標は Vector2i のセル単位。float座標で線判定しない。
##  2. セルの状態は EMPTY / CLAIMED / TRAIL の3つだけ。外枠も自陣も同じ CLAIMED。
##     → 「外枠につなぐ」と「自陣につなぐ」は完全に同じ処理になる。
##  3. 線を引いている間、プレイヤーは4方向にしか動けない。TRAILは4連結の壁になる。
##  4. 線が自陣(CLAIMED)に着いた瞬間に確定。TRAILを壁(CLAIMED)にしてから、
##     敵のいる領域を flood fill で調べ、敵のいない EMPTY 領域をすべて CLAIMED にする。
##     「四角く囲んだか」は一切判定しない。どんな形でも閉じれば取れる。
##  5. 自分のTRAILに触れたら SELF_CROSS を返すだけで、盤面は一切変更しない。
##     ペナルティ（残機減・巻き戻し）は呼び出し側が cancel_trail() で行う。

enum Cell { EMPTY = 0, CLAIMED = 1, TRAIL = 2 }
enum StepResult { BLOCKED, MOVED, TRAIL_STARTED, DRAWING, CLOSED, SELF_CROSS }

const DIRS_8: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]

var width: int
var height: int
var cells := PackedByteArray()

## プレイヤー位置（セル座標）。線を引いていないときは必ず CLAIMED の上、引いている間は TRAIL の上。
var player := Vector2i.ZERO
var drawing := false
var trail: Array[Vector2i] = []
var trail_start := Vector2i.ZERO

## true: 原作どおり「陣の縁（EMPTYに接するCLAIMED）」の上しか歩けない。
## false: 自陣の中ならどこでも歩ける。どちらでも線の判定は同じ。
var edge_only := true

## 直近の CLOSED で増えたセル数（線 + 囲んだ面積）。スコア計算用。
var last_gained := 0

var _claimed_playable := 0
var _playable_total := 0
var _region := PackedInt32Array()
var _stack: Array[int] = []


func _init(p_width: int = 160, p_height: int = 120, p_edge_only: bool = true) -> void:
	width = p_width
	height = p_height
	edge_only = p_edge_only
	reset()


func reset() -> void:
	cells.resize(width * height)
	cells.fill(Cell.EMPTY)
	for x in width:
		cells[x] = Cell.CLAIMED
		cells[(height - 1) * width + x] = Cell.CLAIMED
	for y in height:
		cells[y * width] = Cell.CLAIMED
		cells[y * width + width - 1] = Cell.CLAIMED
	player = Vector2i(width / 2, height - 1)
	drawing = false
	trail.clear()
	trail_start = player
	last_gained = 0
	_claimed_playable = 0
	_playable_total = (width - 2) * (height - 2)


# ---------------------------------------------------------------- 問い合わせ

func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < width and p.y < height


## 範囲外は CLAIMED（壁）として返す。敵の反射判定が楽になる。
func get_cell(p: Vector2i) -> int:
	if not in_bounds(p):
		return Cell.CLAIMED
	return cells[p.y * width + p.x]


func is_trail(p: Vector2i) -> bool:
	return get_cell(p) == Cell.TRAIL


## 自陣のうち、EMPTY と（斜め含め）接しているセル = プレイヤーが歩ける「縁」。
func is_edge(p: Vector2i) -> bool:
	if get_cell(p) != Cell.CLAIMED or not in_bounds(p):
		return false
	for d in DIRS_8:
		var n := p + d
		if in_bounds(n) and cells[n.y * width + n.x] == Cell.EMPTY:
			return true
	return false


## 占有率 0.0〜1.0（外枠は含まない）。
func get_claim_ratio() -> float:
	return float(_claimed_playable) / float(_playable_total)


## 数え直し版（テスト用）。get_claim_ratio の内部カウンタと一致するはず。
func count_claimed_playable() -> int:
	var n := 0
	for y in range(1, height - 1):
		for x in range(1, width - 1):
			if cells[y * width + x] == Cell.CLAIMED:
				n += 1
	return n


# ---------------------------------------------------------------- 操作

## プレイヤーを1セル動かす。呼び出し側が移動速度（何秒に1回呼ぶか）を決める。
## dir: Vector2i.UP/DOWN/LEFT/RIGHT のどれか（斜めは BLOCKED）
## want_draw: 線を「引き始める」ボタンが押されているか（引いている最中は無視される）
## enemy_cells: 敵の現在セル座標の配列。囲み確定時に「敵のいる領域は取らない」ために使う。
func step(dir: Vector2i, want_draw: bool, enemy_cells: Array = []) -> StepResult:
	if absi(dir.x) + absi(dir.y) != 1:
		return StepResult.BLOCKED
	var target := player + dir
	if not in_bounds(target):
		return StepResult.BLOCKED
	var t := get_cell(target)

	if not drawing:
		if t == Cell.CLAIMED:
			# 縁の上しか歩けない設定。ただし縁から外れた位置に居る場合の脱出は許す。
			if edge_only and not is_edge(target) and is_edge(player):
				return StepResult.BLOCKED
			player = target
			return StepResult.MOVED
		if t == Cell.EMPTY and want_draw:
			drawing = true
			trail_start = player
			trail.clear()
			_put(target, Cell.TRAIL)
			trail.append(target)
			player = target
			return StepResult.TRAIL_STARTED
		return StepResult.BLOCKED

	# ---- 線を引いている最中
	var prev: Vector2i = trail[trail.size() - 2] if trail.size() >= 2 else trail_start
	if target == prev:
		return StepResult.BLOCKED # 真後ろへの逆走は不可（死なない）
	match t:
		Cell.TRAIL:
			return StepResult.SELF_CROSS # 盤面は変更しない
		Cell.EMPTY:
			_put(target, Cell.TRAIL)
			trail.append(target)
			player = target
			return StepResult.DRAWING
		_:
			player = target
			_close_trail(enemy_cells)
			return StepResult.CLOSED


## 線を引いている最中にやられた時などに呼ぶ。TRAILを消してスタート地点に戻す。
func cancel_trail() -> void:
	if not drawing:
		return
	for p in trail:
		_put(p, Cell.EMPTY)
	trail.clear()
	drawing = false
	player = trail_start


# ---------------------------------------------------------------- 内部

func _put(p: Vector2i, v: int) -> void:
	cells[p.y * width + p.x] = v


func _close_trail(enemy_cells: Array) -> void:
	# 1) 線を壁(CLAIMED)に変える。これで領域が確実に分断される。
	for p in trail:
		_put(p, Cell.CLAIMED)
	var gained := trail.size()
	_claimed_playable += trail.size()
	trail.clear()
	drawing = false
	# 2) 敵のいない EMPTY 領域を全部 CLAIMED にする。
	gained += _claim_unreachable(enemy_cells)
	last_gained = gained


## 敵のいる領域（敵から4連結で辿れる EMPTY）だけを残し、それ以外の EMPTY を CLAIMED にする。
## 敵が1匹も有効でなければ最大の領域を残す（敵ゼロでも全面取りにならない保険）。
@warning_ignore("integer_division")
func _claim_unreachable(enemy_cells: Array) -> int:
	var total := width * height
	_region.resize(total)
	_region.fill(-1)
	var seeded := false
	for e in enemy_cells:
		var ec: Vector2i = e
		if in_bounds(ec) and cells[ec.y * width + ec.x] == Cell.EMPTY:
			seeded = true
			if _region[ec.y * width + ec.x] == -1:
				_flood(ec.y * width + ec.x, 0)
	if not seeded:
		_keep_largest_region()
	var claimed := 0
	for i in total:
		if cells[i] == Cell.EMPTY and _region[i] == -1:
			cells[i] = Cell.CLAIMED
			claimed += 1
	_claimed_playable += claimed
	return claimed


## start から4連結で辿れる EMPTY に id を付ける。
func _flood(start: int, id: int) -> int:
	var count := 0
	_stack.clear()
	_stack.append(start)
	_region[start] = id
	var w := width
	var h := height
	while not _stack.is_empty():
		var i: int = _stack.pop_back()
		count += 1
		var x := i % w
		var y := i / w
		if x > 0 and cells[i - 1] == Cell.EMPTY and _region[i - 1] == -1:
			_region[i - 1] = id
			_stack.append(i - 1)
		if x < w - 1 and cells[i + 1] == Cell.EMPTY and _region[i + 1] == -1:
			_region[i + 1] = id
			_stack.append(i + 1)
		if y > 0 and cells[i - w] == Cell.EMPTY and _region[i - w] == -1:
			_region[i - w] = id
			_stack.append(i - w)
		if y < h - 1 and cells[i + w] == Cell.EMPTY and _region[i + w] == -1:
			_region[i + w] = id
			_stack.append(i + w)
	return count


## 敵がいない時の保険: 全 EMPTY 領域のうち最大のものを残す（_region に印を付ける）。
func _keep_largest_region() -> void:
	var best_start := -1
	var best_size := 0
	var scratch := PackedInt32Array()
	scratch.resize(width * height)
	scratch.fill(-1)
	for s in width * height:
		if cells[s] != Cell.EMPTY or _region[s] != -1 or scratch[s] != -1:
			continue
		# 一時的に別IDで塗って大きさを測る（_region を一旦使い、最後に最大だけ残す）
		var n := _flood(s, 1)
		if n > best_size:
			best_size = n
			best_start = s
	# 全領域に印が付いたので、最大領域以外の印を外して作り直す
	_region.fill(-1)
	if best_start >= 0:
		_flood(best_start, 0)
