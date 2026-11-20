class_name EnemyManager
extends RefCounted
## ギャルズパニック風の敵群。ステージごとに「構成・形状・動き」を変える。
## 陣のセル参照/書き換えは territory_grid.gd の公開データ(cells/get_cell/is_trail/trail)
## とセッター _put だけを使う。囲み判定・占有率の計算は territory_grid.gd のまま。
##
## 敵の役割(実機の系譜に沿った5種):
##  BIG     : Qix そのもの。斜めに跳ね返りながら大きく弧を描いて跳ね回る。
##            描きかけの線に触れると即死。ステージが上がると数と速度が増える。
##  SPARX   : 小型の群。盤の外周から出現し、線を描いている間だけ線へ突っ込む。
##  SAMSON  : 緑の線消し。描きかけの線を追跡して触れると線を消す(=即死)。
##            ステージ3以降。線へ一直線に寄っていく変則的な動き。
##  FROG    : 着地→膨らみ、周囲の確保済み陣を食べて EMPTY にする(占有率が下がる)。
##            ステージ4以降。膨らんだ体に触れると即死。
##  OCTOPUS : 4方向へ触手を伸ばす。触手上では線が通せない(線が消される)。
##            ステージ5以降。本体はゆっくり漂う。
##
## 移動の約束:
##  ・1サブステップ 0.5 セル以下(線を抜けない)
##  ・敵は EMPTY のセルにしか入らない(CLAIMED / TRAIL には入らない)
##  ・BIG / SAMSON / FROG / OCTOPUS は常に接触で即死、SPARX は線描画中に接触で即死

enum Kind { BIG, SPARX, SAMSON, FROG, OCTOPUS }

const KIND_NAME := ["QIX", "SPARX", "SAMSON", "FROG", "OCTOPUS"]


class Foe:
	var pos := Vector2.ZERO     # センター座標 (float セル)
	var vel := Vector2.ZERO     # セル/秒
	var target := Vector2.ZERO  # 追跡目標(キャッシュ)
	var kind: int = Kind.BIG
	var alive := true
	var respawn := 0.0
	var phase := 0.0
	var state := 0
	var timer := 0.0
	var radius := 0.0
	var reach := 0.0


var foes: Array[Foe] = []
var speed_scale := 1.0
var big_speed := 42.0
var sparx_speed := 58.0
var samson_speed := 30.0
var frog_speed := 18.0
var octo_speed := 10.0
var eroded := 0            # このステージで FROG に食べられたセル数
var last_hit: int = -1     # 直近のヒットを引き起こした敵
var _rng := RandomNumberGenerator.new()


func setup(seed_stage: int, big_count: int, sparx_count: int, samson_count: int,
		frog_count: int, octo_count: int, grid) -> void:
	_rng.seed = seed_stage * 4211 + 17
	foes.clear()
	eroded = 0
	last_hit = -1
	for i in big_count:
		foes.append(_spawn(Kind.BIG, grid))
	for i in sparx_count:
		foes.append(_spawn(Kind.SPARX, grid))
	for i in samson_count:
		foes.append(_spawn(Kind.SAMSON, grid))
	for i in frog_count:
		foes.append(_spawn(Kind.FROG, grid))
	for i in octo_count:
		foes.append(_spawn(Kind.OCTOPUS, grid))


func _spawn(kind: int, grid) -> Foe:
	var f := Foe.new()
	f.kind = kind
	f.phase = _rng.randf_range(0.0, TAU)
	f.alive = true
	f.target = Vector2(_random_empty(grid))
	match kind:
		Kind.SPARX:
			f.pos = Vector2(_edge_point(grid))
			var a := _rng.randf_range(0.0, TAU)
			f.vel = Vector2(cos(a), sin(a)) * sparx_speed
		Kind.SAMSON:
			f.pos = Vector2(_random_empty(grid))
			f.vel = Vector2(cos(f.phase), sin(f.phase)) * samson_speed
			f.timer = 0.0
		Kind.FROG:
			f.pos = Vector2(_random_empty(grid))
			f.state = 0
			f.timer = _rng.randf_range(0.9, 2.0)
			f.radius = 0.0
			f.vel = Vector2(cos(f.phase), sin(f.phase)) * frog_speed
		Kind.OCTOPUS:
			f.pos = Vector2(_random_empty(grid))
			f.reach = 4.0
			f.vel = Vector2(cos(f.phase), sin(f.phase)) * octo_speed
		_:
			var b := _rng.randf_range(0.0, TAU)
			f.vel = Vector2(cos(b), sin(b)) * big_speed
	return f


## 盤の外周(内側1セル目)の EMPTY 座標。SPARX の出現位置。
func _edge_point(grid) -> Vector2i:
	for tries in 240:
		var side := _rng.randi_range(0, 3)
		var x := 1
		var y := 1
		if side == 0:
			x = _rng.randi_range(2, grid.width - 3)
			y = 1
		elif side == 1:
			x = _rng.randi_range(2, grid.width - 3)
			y = grid.height - 2
		elif side == 2:
			x = 1
			y = _rng.randi_range(2, grid.height - 3)
		else:
			x = grid.width - 2
			y = _rng.randi_range(2, grid.height - 3)
		if grid.get_cell(Vector2i(x, y)) == TerritoryGrid.Cell.EMPTY:
			return Vector2i(x, y)
	return Vector2i(grid.width / 2, grid.height / 2)


## EMPTY のセルをランダムに (grid.get_cell を読むだけ)。
func _random_empty(grid) -> Vector2i:
	for tries in 400:
		var x := _rng.randi_range(2, grid.width - 3)
		var y := _rng.randi_range(2, grid.height - 3)
		if grid.get_cell(Vector2i(x, y)) == TerritoryGrid.Cell.EMPTY:
			return Vector2i(x, y)
	return Vector2i(grid.width / 2, grid.height / 2)


func alive_count() -> int:
	var n := 0
	for f in foes:
		if f.alive:
			n += 1
	return n


func roster_text() -> String:
	var counts := [0, 0, 0, 0, 0]
	for f in foes:
		counts[f.kind] += 1
	var parts: Array[String] = []
	for k in 5:
		if counts[k] > 0:
			parts.append("%s x%d" % [KIND_NAME[k], counts[k]])
	return "  ".join(parts)


## 盤面に置いてはいけない敵のセル(線が通せない場所)。OCTOPUS は触手も含む。
func cell_list() -> Array:
	var out: Array = []
	for f in foes:
		if not f.alive:
			continue
		out.append(Vector2i(f.pos))
		if f.kind == Kind.OCTOPUS:
			var c := Vector2i(f.pos)
			var l := int(clampf(f.reach, 2.0, 9.0))
			for k in range(1, l + 1):
				out.append(c + Vector2i(k, 0))
				out.append(c + Vector2i(-k, 0))
				out.append(c + Vector2i(0, k))
				out.append(c + Vector2i(0, -k))
	return out


## 全滅 (パンikhバー全開 / 隕石ストーム)。
func kill_all() -> int:
	var n := 0
	for f in foes:
		if f.alive:
			f.alive = false
			f.respawn = 2.2
			n += 1
	return n


func speed_up(mult: float) -> void:
	speed_scale = minf(speed_scale * mult, 2.2)


func hit_name() -> String:
	if last_hit < 0 or last_hit >= KIND_NAME.size():
		return "CAUGHT BY FOE"
	match last_hit:
		Kind.SAMSON:
			return "SAMSON ERASED YOUR LINE"
		Kind.FROG:
			return "EATEN BY FROG"
		Kind.OCTOPUS:
			return "OCTOPUS CRUSHED YOUR LINE"
		Kind.SPARX:
			return "SPARX HIT YOU"
		_:
			return "CAUGHT BY QIX"


func update(delta: float, grid, player: Vector2i, drawing: bool) -> int:
	## 戻り値: 0=なし / 1=線に触れた(線が消える) / 2=本体に接触
	var fastest := 0.0
	for f in foes:
		fastest = maxf(fastest, f.vel.length())
	var dist := fastest * delta * speed_scale
	var n := maxi(1, ceili(dist / 0.5))  # 1サブステップ 0.5 セル以下
	var dt := delta / float(n)
	for k in n:
		var hit := _substep(dt, grid, player, drawing)
		if hit != 0:
			return hit
	for f in foes:
		if not f.alive:
			f.respawn -= delta
			if f.respawn <= 0.0:
				f.pos = Vector2(_random_empty(grid))
				f.target = f.pos
				f.alive = true
	return 0


func _substep(dt: float, grid, player: Vector2i, drawing: bool) -> int:
	for f in foes:
		if not f.alive:
			continue
		match f.kind:
			Kind.BIG:
				_steer_big(f, dt)
			Kind.SPARX:
				_steer_sparx(f, dt, grid, player, drawing)
			Kind.SAMSON:
				_steer_samson(f, dt, grid)
			Kind.FROG:
				_steer_frog(f, dt, grid)
			Kind.OCTOPUS:
				_steer_octo(f, dt)
		var mv := f.vel * dt * speed_scale
		var nx := f.pos + Vector2(mv.x, 0.0)
		if grid.get_cell(Vector2i(nx)) != TerritoryGrid.Cell.EMPTY:
			f.vel.x = -f.vel.x
			if f.kind == Kind.SAMSON:
				f.timer = 0.0
		else:
			f.pos.x = nx.x
		var ny := f.pos + Vector2(0.0, mv.y)
		if grid.get_cell(Vector2i(ny)) != TerritoryGrid.Cell.EMPTY:
			f.vel.y = -f.vel.y
			if f.kind == Kind.SAMSON:
				f.timer = 0.0
		else:
			f.pos.y = ny.y
		# 接触判定
		if drawing and _touches_trail(f, grid):
			last_hit = f.kind
			return 1
		var kill := 1.1
		match f.kind:
			Kind.SPARX:
				kill = 1.0
			Kind.FROG:
				kill = 1.2 + f.radius * 0.6
			Kind.OCTOPUS:
				kill = 1.4
		if f.pos.distance_to(Vector2(player)) <= kill:
			last_hit = f.kind
			return 2
	return 0


# ---------------------------------------------------------------- 動きのパターン

func _steer_big(f: Foe, dt: float) -> void:
	# Qix: 大きな弧を描きながら跳ね回る
	f.phase += dt * 1.7
	var sp := f.vel.length()
	var ang := atan2(f.vel.y, f.vel.x) + sin(f.phase) * dt * 2.2
	f.vel = Vector2(cos(ang), sin(ang)) * sp


func _steer_sparx(f: Foe, dt: float, grid, player: Vector2i, drawing: bool) -> void:
	# SPARX: 線描画中だけ線へ突進、それ以外は蛇行
	f.phase += dt * 3.0
	var sp := sparx_speed
	if drawing:
		var to := _nearest_trail(f.pos, grid) - f.pos
		if to.length() > 0.001:
			var want := to.normalized() * sp
			f.vel = f.vel.lerp(want, clampf(dt * 2.6, 0.0, 0.6))
		f.vel = f.vel.limit_length(sp * 1.25)
	else:
		var ang := atan2(f.vel.y, f.vel.x) + sin(f.phase) * dt * 3.4
		f.vel = Vector2(cos(ang), sin(ang)) * sp


func _steer_samson(f: Foe, dt: float, grid) -> void:
	# SAMSON: 描きかけの線を追跡して消しに来る。線が無いときは巡回。
	f.timer -= dt
	if f.timer <= 0.0:
		f.timer = 0.14
		f.target = _nearest_trail(f.pos, grid)
	var sp := samson_speed
	if grid.trail.is_empty():
		f.phase += dt * 2.0
		var ang := atan2(f.vel.y, f.vel.x) + sin(f.phase) * dt * 2.6
		f.vel = Vector2(cos(ang), sin(ang)) * sp * 0.8
		return
	var to := f.target - f.pos
	if to.length() > 0.001:
		var want := to.normalized() * sp
		f.vel = f.vel.lerp(want, clampf(dt * 3.2, 0.0, 0.75))
	f.vel = f.vel.limit_length(sp * 1.2)


func _steer_frog(f: Foe, dt: float, grid) -> void:
	# FROG: hop → 膨らんで陣を食べる を繰り返す
	f.timer -= dt
	if f.state == 0:
		var to := f.target - f.pos
		if to.length() < 1.2:
			f.vel = f.vel.lerp(Vector2.ZERO, clampf(dt * 6.0, 0.0, 1.0))
		else:
			f.vel = f.vel.lerp(to.normalized() * frog_speed, clampf(dt * 2.4, 0.0, 0.6))
		if f.timer <= 0.0:
			f.state = 1
			f.timer = 1.6
			f.radius = 1.0
	else:
		f.vel = f.vel.lerp(Vector2.ZERO, clampf(dt * 8.0, 0.0, 1.0))
		f.radius += dt * 5.5
		_frog_eat(f, grid)
		if f.timer <= 0.0:
			f.state = 0
			f.radius = 0.0
			f.timer = _rng.randf_range(1.1, 2.4)
			f.target = Vector2(_random_empty(grid))


func _steer_octo(f: Foe, dt: float) -> void:
	# OCTOPUS: ゆっくり漂い、触手を伸縮させる
	f.phase += dt * 2.2
	f.reach = 5.0 + sin(f.phase) * 3.5
	var ang := atan2(f.vel.y, f.vel.x) + sin(f.phase * 0.7) * dt * 2.0
	f.vel = Vector2(cos(ang), sin(ang)) * octo_speed


## FROG が周囲の CLAIMED を EMPTY に戻す (占有率のカウンタは grid 側で維持)。
func _frog_eat(f: Foe, grid) -> void:
	var r := int(f.radius)
	if r < 1:
		return
	var c := Vector2i(f.pos)
	var rr := r * r
	var n := 0
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy > rr:
				continue
			var p := c + Vector2i(dx, dy)
			if not grid.in_bounds(p):
				continue
			if grid.get_cell(p) == TerritoryGrid.Cell.CLAIMED:
				grid._put(p, TerritoryGrid.Cell.EMPTY)
				n += 1
	if n > 0:
		grid._claimed_playable -= n
		eroded += n


func _nearest_trail(from: Vector2, grid) -> Vector2:
	var tr: Array = grid.trail
	if tr.is_empty():
		return from
	var best := 1e18
	var bp := Vector2(tr[tr.size() - 1])
	var i := 0
	while i < tr.size():
		var p: Vector2i = tr[i]
		var d := from.distance_squared_to(Vector2(p))
		if d < best:
			best = d
			bp = Vector2(p)
		i += 3
	return bp


func _touches_trail(f: Foe, grid) -> bool:
	var c := Vector2i(f.pos)
	var r := 2
	match f.kind:
		Kind.SPARX:
			r = 1
		Kind.SAMSON:
			r = 1
		Kind.FROG:
			r = 2
		Kind.OCTOPUS:
			r = 1
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if grid.is_trail(c + Vector2i(dx, dy)):
				return true
	return false
