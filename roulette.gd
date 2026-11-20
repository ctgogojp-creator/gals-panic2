class_name BonusRoulette
extends Node2D
## ボーナスルーレット（ステージ後に1回まわすおまけ）。
## 演出専用で、陣取りの判定には一切関与しない。
##
## 使い方:
##   roulette.open_round()            # 回す準備
##   roulette.press()                 # プレイヤーのボタン（回す／止める）
##   roulette.finished.connect(...)   # 当たったスロット確定
##   roulette.visible を main 側で切り替える

signal finished(index: int)

const SLOT_COUNT := 12
const RADIUS := 300.0

var slots: Array = []          # [{ "label": String, "color": Color }]
var angle := 0.0               # 回転角（ラジアン）
var spin_speed := 0.0
var state := "idle"            # idle / ready / spinning / braking / result
var result_index := -1
var result_timer := 0.0
var glow := 0.0
var center := Vector2(960.0, 540.0)


func _ready() -> void:
	if slots.is_empty():
		slots = [
			{"label": "+5000", "color": Color(0.20, 0.45, 0.95)},
			{"label": "1UP", "color": Color(0.95, 0.35, 0.55)},
			{"label": "+15000", "color": Color(0.25, 0.75, 0.45)},
			{"label": "TIME +20", "color": Color(0.30, 0.80, 0.85)},
			{"label": "ENEMY FAST", "color": Color(0.85, 0.30, 0.25)},
			{"label": "+2000", "color": Color(0.45, 0.45, 0.85)},
			{"label": "MONSTER", "color": Color(0.45, 0.25, 0.55)},
			{"label": "x2 SCORE", "color": Color(0.95, 0.75, 0.20)},
			{"label": "+8000", "color": Color(0.20, 0.55, 0.90)},
			{"label": "TIME -10", "color": Color(0.75, 0.40, 0.20)},
			{"label": "STORM", "color": Color(0.35, 0.90, 0.55)},
			{"label": "+3000", "color": Color(0.55, 0.55, 0.80)},
		]


func open_round() -> void:
	state = "ready"
	result_index = -1
	angle = 0.0
	spin_speed = 0.0
	glow = 0.0
	visible = true


func press() -> void:
	if state == "ready":
		state = "spinning"
		spin_speed = 12.0
	elif state == "spinning":
		state = "braking"
		queue_redraw()


func _process(delta: float) -> void:
	if not visible:
		return
	glow += delta
	match state:
		"spinning":
			spin_speed = maxf(spin_speed - delta * 1.15, 3.2)
			angle += spin_speed * delta
		"braking":
			spin_speed = maxf(spin_speed - delta * 7.5, 0.0)
			angle += spin_speed * delta
			if spin_speed <= 0.01:
				_lock_result()
		"result":
			result_timer -= delta
			if result_timer <= 0.0:
				visible = false
				state = "idle"
		_:
			pass
	if state == "spinning" or state == "braking":
		queue_redraw()


func _lock_result() -> void:
	# 矢印（上）が指しているスロットにぴたりと止める
	var seg := TAU / float(SLOT_COUNT)
	var idx := int(round(-angle / seg)) % SLOT_COUNT
	if idx < 0:
		idx += SLOT_COUNT
	angle = -float(idx) * seg
	result_index = idx
	result_timer = 2.4
	state = "result"
	queue_redraw()
	finished.emit(idx)


func slot_label(i: int) -> String:
	return slots[i]["label"] if i >= 0 and i < slots.size() else ""


func _draw() -> void:
	var seg := TAU / float(SLOT_COUNT)
	for i in SLOT_COUNT:
		var a0 := angle + float(i) * seg
		var a1 := a0 + seg
		var col: Color = slots[i]["color"]
		if i == result_index:
			col = col.lightened(0.45 + 0.25 * sin(glow * 12.0))
		var pts := PackedVector2Array()
		pts.append(center)
		var steps := 8
		for s in steps + 1:
			var a := lerpf(a0, a1, float(s) / float(steps))
			pts.append(center + Vector2(cos(a), sin(a)) * RADIUS)
		draw_colored_polygon(pts, col.darkened(0.25))
		# 区切り線
		draw_line(center, center + Vector2(cos(a0), sin(a0)) * RADIUS, Color(0.05, 0.05, 0.08), 3.0)
		# ラベル
		var mid := a0 + seg * 0.5
		var p := center + Vector2(cos(mid), sin(mid)) * (RADIUS * 0.62)
		var f := ThemeDB.fallback_font
		draw_set_transform(p, mid + PI * 0.5, Vector2.ONE)
		draw_string(f, Vector2(-70, 12), slot_label(i), HORIZONTAL_ALIGNMENT_CENTER, 140, 26, Color.BLACK)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 外周
	draw_arc(center, RADIUS, 0, TAU, 96, Color(1, 0.9, 0.35), 6.0)
	draw_arc(center, RADIUS + 12, 0, TAU, 96, Color(0.6, 0.5, 0.2), 3.0)
	# 中心
	draw_circle(center, 46.0, Color(0.12, 0.12, 0.18))
	draw_circle(center, 34.0, Color(1, 0.85, 0.3))
	# 矢印（上から下向き）
	var tip := center + Vector2(0, -RADIUS - 26)
	var pts := PackedVector2Array([tip + Vector2(-18, -26), tip + Vector2(18, -26), tip])
	draw_colored_polygon(pts, Color(1, 0.25, 0.30))
	# 見出し
	var f2 := ThemeDB.fallback_font
	draw_string(f2, Vector2(center.x - 300, center.y - RADIUS - 90), "BONUS ROULETTE",
			HORIZONTAL_ALIGNMENT_CENTER, 600, 44, Color(1, 0.95, 0.6))
	if state == "ready":
		draw_string(f2, Vector2(center.x - 300, center.y + RADIUS + 60), "PRESS DRAW (SPACE) TO SPIN",
				HORIZONTAL_ALIGNMENT_CENTER, 600, 30, Color(0.8, 0.85, 1.0))
	elif state == "result" and result_index >= 0:
		draw_string(f2, Vector2(center.x - 300, center.y + RADIUS + 60),
				"WINNER: " + slot_label(result_index),
				HORIZONTAL_ALIGNMENT_CENTER, 600, 38, Color(1, 1, 0.55))
