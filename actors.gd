extends Node2D
## 取得領域より手前に、自機マーカー・敵・ボーナスシンボル・演出を描くだけのノード。
## 陣取りの判定には関与しない。座標は 1920x1080 基準（盤面は ORIGIN 起点）。

var game  # main.gd を入れる


func _f() -> Font:
	return ThemeDB.fallback_font


func _draw() -> void:
	if game == null:
		return
	var origin: Vector2 = game.ORIGIN
	var cell: float = float(game.CELL)

	# --- ボーナスシンボル
	for s in game.symbols:
		var c: Vector2i = s["cell"]
		var p := origin + (Vector2(c) + Vector2(0.5, 0.5)) * cell
		_draw_symbol(p, int(s["kind"]), float(s["phase"]) + float(Time.get_ticks_msec()) * 0.003)

	# --- 敵
	for f in game.enemies.foes:
		if not f.alive:
			continue
		var ep: Vector2 = origin + (f.pos + Vector2(0.5, 0.5)) * cell
		match f.kind:
			EnemyManager.Kind.BIG:
				_draw_big(ep, f.phase)
			EnemyManager.Kind.SPARX:
				_draw_sparx(ep, f.phase)
			EnemyManager.Kind.SAMSON:
				_draw_samson(ep, f.phase, atan2(f.vel.y, f.vel.x))
			EnemyManager.Kind.FROG:
				_draw_frog(ep, f.phase, f.radius * cell, f.state)
			_:
				_draw_octo(ep, f.phase, f.reach * cell)

	# --- 自機マーカー（Qix風のダイヤ）
	var pp: Vector2 = origin + (Vector2(game.grid.player) + Vector2(0.5, 0.5)) * cell
	var dying: bool = game.state == game.GState.DYING
	var blink := dying and int(game.freeze * 12.0) % 2 == 0
	if not blink:
		draw_circle(pp, 11.0, Color(1, 1, 1, 0.95))
		var pts := PackedVector2Array([
			pp + Vector2(0, -10), pp + Vector2(10, 0), pp + Vector2(0, 10), pp + Vector2(-10, 0),
		])
		draw_colored_polygon(pts, Color(1, 0.22, 0.3))
		draw_polyline(pts + PackedVector2Array([pp + Vector2(0, -10)]), Color(1, 1, 1), 2.0)
		if game.grid.drawing:
			draw_circle(pp, 15.0, Color(1, 0.9, 0.2, 0.25))

	# --- 死亡理由の吹き出し
	if dying:
		var f := _f()
		draw_string(f, Vector2(240, 940), game.death_cause, HORIZONTAL_ALIGNMENT_CENTER, 1440, 40,
				Color(1, 0.5, 0.5))


func _draw_big(p: Vector2, phase: float) -> void:
	var s := 1.0 + 0.12 * sin(phase * 2.0)
	var pts := PackedVector2Array()
	for i in 4:
		var a := phase * 0.6 + float(i) * PI * 0.5
		pts.append(p + Vector2(cos(a), sin(a)) * 17.0 * s)
	draw_colored_polygon(pts, Color(0.85, 0.25, 0.9, 0.95))
	var inner := PackedVector2Array()
	for i in 4:
		var a := -phase * 0.9 + float(i) * PI * 0.5
		inner.append(p + Vector2(cos(a), sin(a)) * 9.0 * s)
	draw_colored_polygon(inner, Color(1.0, 0.75, 1.0))
	draw_line(p + Vector2(-20, 0), p + Vector2(20, 0), Color(0.2, 0.0, 0.25), 2.0)
	draw_line(p + Vector2(0, -20), p + Vector2(0, 20), Color(0.2, 0.0, 0.25), 2.0)


func _draw_sparx(p: Vector2, phase: float) -> void:
	var flap := sin(phase * 6.0) * 5.0
	var pts := PackedVector2Array([p + Vector2(0, -9), p + Vector2(9, 4), p + Vector2(-9, 4)])
	draw_colored_polygon(pts, Color(0.3, 0.95, 0.6))
	draw_line(p + Vector2(-13, -2 - flap * 0.2), p + Vector2(-4, -10 - flap), Color(0.8, 1, 0.9, 0.85), 2.0)
	draw_line(p + Vector2(13, -2 - flap * 0.2), p + Vector2(4, -10 - flap), Color(0.8, 1, 0.9, 0.85), 2.0)
	draw_circle(p, 3.0, Color(0.05, 0.25, 0.15))


func _draw_samson(p: Vector2, phase: float, dir: float) -> void:
	# SAMSON: 線を食べる緑の敵。進行方向へ向いた矢印型の体に「口」。
	var fwd := Vector2(cos(dir), sin(dir))
	var side := Vector2(-fwd.y, fwd.x)
	var col := Color(0.35, 0.95, 0.45, 0.95)
	var pts := PackedVector2Array([
		p + fwd * 20.0,
		p - fwd * 12.0 + side * 13.0,
		p - fwd * 6.0,
		p - fwd * 12.0 - side * 13.0,
	])
	draw_colored_polygon(pts, col)
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.9, 1.0, 0.9), 2.0)
	var flap := sin(phase * 5.0) * 3.0
	draw_line(p - fwd * 6.0 + side * (6.0 + flap), p + fwd * 12.0 + side * 3.0,
			Color(0.05, 0.3, 0.1), 2.0)
	draw_line(p - fwd * 6.0 - side * (6.0 + flap), p + fwd * 12.0 - side * 3.0,
			Color(0.05, 0.3, 0.1), 2.0)
	draw_circle(p + fwd * 4.0, 3.5, Color(1, 1, 0.75))


func _draw_frog(p: Vector2, phase: float, rad: float, state: int) -> void:
	# FROG: 着地すると膨らみ、周囲の陣を食べる。膨らみ分だけ大きく描く。
	var r := 10.0 + maxf(rad, 0.0) * 3.0
	var pulse := 1.0 + 0.06 * sin(phase * 3.0)
	var col := Color(0.35, 0.85, 0.35, 0.95) if state == 0 else Color(0.65, 0.95, 0.45, 0.95)
	draw_circle(p, r * pulse, col)
	draw_arc(p, r * pulse, 0, TAU, 24, Color(0.05, 0.3, 0.1), 2.0)
	if rad > 1.0:
		draw_arc(p, r * pulse + 5.0, 0, TAU, 24, Color(1, 0.9, 0.3, 0.5 + 0.4 * sin(phase * 6.0)), 2.0)
	draw_circle(p + Vector2(-r * 0.45, -r * 0.5), r * 0.28, Color(0.95, 1.0, 0.95))
	draw_circle(p + Vector2(r * 0.45, -r * 0.5), r * 0.28, Color(0.95, 1.0, 0.95))
	draw_circle(p + Vector2(-r * 0.45, -r * 0.5), r * 0.13, Color(0.05, 0.15, 0.05))
	draw_circle(p + Vector2(r * 0.45, -r * 0.5), r * 0.13, Color(0.05, 0.15, 0.05))
	draw_arc(p, r * 0.55, 0.25, PI - 0.25, 12, Color(0.05, 0.25, 0.05), 2.0)


func _draw_octo(p: Vector2, phase: float, reach: float) -> void:
	# OCTOPUS: 4方向へ触手を伸ばし、触手上では線が通せない。
	var body := 11.0
	for i in 4:
		var a := float(i) * PI * 0.5
		var dir := Vector2(cos(a), sin(a))
		var tip := p + dir * (body + reach)
		var mid := p + dir * (body + reach * 0.5) + Vector2(-dir.y, dir.x) * sin(phase * 2.0 + a) * 7.0
		draw_polyline(PackedVector2Array([p + dir * body * 0.5, mid, tip]),
				Color(0.95, 0.5, 0.8, 0.9), 4.0)
		draw_circle(tip, 3.0, Color(1, 0.75, 0.9))
	draw_circle(p, body, Color(0.9, 0.35, 0.65, 0.95))
	draw_arc(p, body, 0, TAU, 20, Color(0.35, 0.05, 0.2), 2.0)
	draw_circle(p + Vector2(-4, -3), 2.6, Color(1, 1, 1))
	draw_circle(p + Vector2(4, -3), 2.6, Color(1, 1, 1))
	draw_circle(p + Vector2(-4, -3), 1.2, Color(0.1, 0.02, 0.08))
	draw_circle(p + Vector2(4, -3), 1.2, Color(0.1, 0.02, 0.08))


func _draw_symbol(p: Vector2, kind: int, phase: float) -> void:
	var bob := sin(phase) * 3.0
	var c := p + Vector2(0, bob)
	match kind:
		0:  # STAR
			_star(c, 14.0, Color(1, 0.95, 0.35))
		1:  # LIFE
			draw_circle(c, 12.0, Color(0.95, 0.3, 0.4))
			draw_rect(Rect2(c.x - 10, c.y - 3, 20, 6), Color.WHITE)
			draw_rect(Rect2(c.x - 3, c.y - 10, 6, 20), Color.WHITE)
		2:  # CLOCK
			draw_circle(c, 13.0, Color(0.35, 0.85, 0.95))
			draw_circle(c, 13.0, Color(0.05, 0.2, 0.25), false, 2.0)
			draw_line(c, c + Vector2(0, -9), Color(0.05, 0.2, 0.25), 2.0)
			draw_line(c, c + Vector2(6, 2), Color(0.05, 0.2, 0.25), 2.0)
		3:  # STORM
			for i in 6:
				var a := phase * 1.5 + float(i) * PI / 3.0
				draw_line(c + Vector2(cos(a), sin(a)) * 6.0, c + Vector2(cos(a), sin(a)) * 16.0,
						Color(0.6, 0.95, 1.0), 3.0)
			draw_circle(c, 6.0, Color(1, 1, 1))
		4:  # CURSE
			draw_circle(c, 13.0, Color(0.55, 0.25, 0.7))
			draw_circle(c + Vector2(-5, -2), 3.0, Color(0.05, 0.02, 0.08))
			draw_circle(c + Vector2(5, -2), 3.0, Color(0.05, 0.02, 0.08))
			draw_rect(Rect2(c.x - 6, c.y + 5, 12, 3), Color(0.05, 0.02, 0.08))
		5:  # FROG
			draw_circle(c, 13.0, Color(0.35, 0.85, 0.35))
			draw_circle(c + Vector2(-6, -7), 5.0, Color(0.9, 1.0, 0.9))
			draw_circle(c + Vector2(6, -7), 5.0, Color(0.9, 1.0, 0.9))
			draw_arc(c, 8.0, 0.2, PI - 0.2, 12, Color(0.05, 0.25, 0.05), 2.0)
		6:  # OCTOPUS
			draw_circle(c, 12.0, Color(0.95, 0.45, 0.75))
			for i in 5:
				var a := PI * 0.15 + float(i) * PI * 0.18
				var q := c + Vector2(cos(a), sin(a)) * 12.0
				draw_line(q, q + Vector2(sin(phase + float(i)) * 4.0, 12.0), Color(0.95, 0.55, 0.8), 3.0)
	# 光る輪郭
	draw_arc(c, 18.0, 0, TAU, 24, Color(1, 1, 0.7, 0.35 + 0.25 * sin(phase * 2.0)), 2.0)


func _star(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI * 0.5 + float(i) * PI / 5.0
		var rr := r if i % 2 == 0 else r * 0.45
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	draw_colored_polygon(pts, col)
