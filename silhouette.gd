class_name Silhouette
extends RefCounted
## 盤面に描く「女の子のシルエット」マスクを作るだけの補助クラス。
## 陣取り・線・占有率の判定は一切行わない（territory_grid.gd だけがそれを持つ）。
##
## 使い方:
##   var sil := Silhouette.new(GRID_W, GRID_H)
##   var mask: PackedByteArray = sil.build_mask(stage_seed)   # 0=背景 / 255=シルエット
##   var img: Image = sil.procedural_image(GRID_W, GRID_H, gal, stage)  # 画像が無い時の代用背景
##
## シルエットは 1920x1080 の盤面比率に合わせた人物プロファイル（頭・体・脚）。
## ステージごとに体型・ポーズの比率を変えて、ステージ毎に違う女の子に見えるようにする。

const HEAD_R: float = 0.052
const SHOULDER_W: float = 0.115
const WAIST_W: float = 0.062
const HIP_W: float = 0.098


## stage_seed からマスク（幅*高さ の R8 バイト列）を作る。
func build_mask(seed_stage: int) -> PackedByteArray:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234 + seed_stage * 977
	var lean := rng.randf_range(-0.06, 0.06)
	var leg_spread := rng.randf_range(0.05, 0.11)
	var arm_out := rng.randf_range(0.02, 0.09)
	var scale := rng.randf_range(0.92, 1.02)
	var out := PackedByteArray()
	out.resize(w * h)
	out.fill(0)
	var cx := 0.5 + lean * 0.5
	# 縦の比率（頭→首→肩→胸→腰→腰→脚→膝→足）
	var y_head_top := 0.06
	var y_head_bot := y_head_top + HEAD_R * 2.0
	var y_shoulder := y_head_bot + 0.035
	var y_bust := y_shoulder + 0.11
	var y_waist := y_bust + 0.10
	var y_hip := y_waist + 0.08
	var y_knee := y_hip + 0.22
	var y_foot := 0.97
	for yy in h:
		var ny := float(yy) / float(h)
		var half := _half_width(ny, y_head_top, y_head_bot, y_shoulder, y_bust, y_waist, y_hip, y_knee, leg_spread, arm_out, scale)
		if half <= 0.0:
			continue
		var center := cx + lean * (ny - 0.5)
		var lo := int(floor((center - half) * float(w)))
		var hi := int(ceil((center + half) * float(w)))
		if ny < y_head_bot:
			center = cx
			lo = int(floor((center - half) * float(w)))
			hi = int(ceil((center + half) * float(w)))
		for xx in range(maxi(0, lo), mini(w, hi)):
			out[yy * w + xx] = 255
	# 首の細さ（頭と体の間を埋める）
	for yy in range(int(y_head_bot * h), int(y_shoulder * h)):
		var half := SHOULDER_W * 0.28 * scale
		var center := cx + lean * (float(yy) / float(h) - 0.5)
		for xx in range(maxi(0, int(center * w - half * w)), mini(w, int(center * w + half * w))):
			out[yy * w + xx] = 255
	return out


func _half_width(ny: float, y_head_top: float, y_head_bot: float, y_shoulder: float, y_bust: float,
		y_waist: float, y_hip: float, y_knee: float, leg_spread: float, arm_out: float, scale: float) -> float:
	if ny < y_head_top or ny > 0.97:
		return 0.0
	if ny < y_head_bot:
		var t := (ny - y_head_top) / (y_head_bot - y_head_top)
		return HEAD_R * scale * sqrt(maxf(0.0, 1.0 - t * t * 0.92))
	if ny < y_shoulder:
		return SHOULDER_W * 0.42 * scale
	if ny < y_bust:
		var t := (ny - y_shoulder) / (y_bust - y_shoulder)
		return (SHOULDER_W * 0.42 + t * (SHOULDER_W * 0.30)) * scale + arm_out * 0.35 * t
	if ny < y_waist:
		var t := (ny - y_bust) / (y_waist - y_bust)
		return lerpf(SHOULDER_W * 0.72, WAIST_W, t) * scale
	if ny < y_hip:
		var t := (ny - y_waist) / (y_hip - y_waist)
		return lerpf(WAIST_W, HIP_W, t) * scale
	if ny < y_knee:
		var t := (ny - y_hip) / (y_knee - y_hip)
		return lerpf(HIP_W, 0.052, t) * scale + leg_spread * 0.5
	if ny <= 0.97:
		var t := (ny - y_knee) / (0.97 - y_knee)
		return lerpf(0.052, 0.030, t) * scale + leg_spread * 0.5 * (1.0 - t * 0.4)
	return 0.0


## 画像が無いときのための「代用の女の子画像」（コード生成・4:3）。
## gal(0..5) / stage(1..3) で服の色と肌色を変え、stage が進むほど露出が増える演出にする。
func procedural_image(width: int, height: int, gal: int, stage: int) -> Image:
	var img := Image.create(width, height, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77 + gal * 31
	var skin := Color.from_hsv(rng.randf_range(0.06, 0.10), 0.32, 0.98)
	var hair := Color.from_hsv(rng.randf_range(0.02, 0.12), 0.65, rng.randf_range(0.25, 0.55))
	var cloth := Color.from_hsv(float(gal) / 6.0 + 0.02, 0.72, 0.92)
	var bg_top := Color.from_hsv(float(gal) / 6.0, 0.55, 0.22)
	var bg_bot := Color.from_hsv(float(gal) / 6.0 + 0.12, 0.65, 0.08)
	var cover_top := 0.30 if stage == 1 else (0.52 if stage == 2 else 0.72)
	for y in height:
		var ny := float(y) / float(height)
		var bgc := bg_top.lerp(bg_bot, ny)
		for x in width:
			img.set_pixel(x, y, bgc)
	var cx := 0.5
	# 髪
	_fill_ellipse(img, cx, 0.16, 0.10, 0.13, hair)
	# 頭
	_fill_ellipse(img, cx, 0.155, 0.055, 0.072, skin)
	# 首
	_fill_rect(img, cx - 0.012, 0.225, 0.024, 0.045, skin)
	# 体
	_fill_ellipse(img, cx, 0.34, 0.105, 0.10, skin)
	_fill_ellipse(img, cx, 0.47, 0.075, 0.08, skin)
	_fill_ellipse(img, cx, 0.56, 0.10, 0.07, skin)
	# 腕
	_fill_capsule(img, cx - 0.115, 0.28, cx - 0.155, 0.60, 0.026, skin)
	_fill_capsule(img, cx + 0.115, 0.28, cx + 0.155, 0.60, 0.026, skin)
	# 脚
	_fill_capsule(img, cx - 0.045, 0.62, cx - 0.075, 0.96, 0.036, skin)
	_fill_capsule(img, cx + 0.045, 0.62, cx + 0.075, 0.96, 0.036, skin)
	# 服（stage が進むほど短く・狭くなる）
	var top_y := 0.27
	var top_h := cover_top
	_fill_quad(img, cx, top_y, SHOULDER_W * 0.95, WAIST_W * 1.1, top_h, cloth)
	if stage <= 2:
		_fill_quad(img, cx, top_y + top_h - 0.02, HIP_W * 1.15, HIP_W * 0.75, 0.10, cloth.darkened(0.15))
	# 顔の目
	img.fill_rect(Rect2i(int((cx - 0.030) * width), int(0.150 * height), int(0.018 * width), int(0.012 * height)), Color(0.1, 0.1, 0.15))
	img.fill_rect(Rect2i(int((cx + 0.012) * width), int(0.150 * height), int(0.018 * width), int(0.012 * height)), Color(0.1, 0.1, 0.15))
	return img


func _fill_ellipse(img: Image, cx: float, cy: float, rx: float, ry: float, col: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var x0 := int((cx - rx) * w)
	var x1 := int((cx + rx) * w)
	var y0 := int((cy - ry) * h)
	var y1 := int((cy + ry) * h)
	for y in range(maxi(0, y0), mini(h, y1 + 1)):
		for x in range(maxi(0, x0), mini(w, x1 + 1)):
			var dx := (float(x) / w - cx) / rx
			var dy := (float(y) / h - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, col)


func _fill_rect(img: Image, x: float, y: float, w2: float, h2: float, col: Color) -> void:
	img.fill_rect(Rect2i(int(x * img.get_width()), int(y * img.get_height()),
			int(w2 * img.get_width()), int(h2 * img.get_height())), col)


func _fill_capsule(img: Image, x0: float, y0: float, x1: float, y1: float, r: float, col: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var steps := 48
	for i in steps:
		var t := float(i) / float(steps - 1)
		var px := lerpf(x0, x1, t)
		var py := lerpf(y0, y1, t)
		_fill_ellipse(img, px, py, r, r * float(w) / float(h), col)


func _fill_quad(img: Image, cx: float, y: float, w_top: float, w_bot: float, hgt: float, col: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var steps := maxi(1, int(hgt * h))
	for i in steps:
		var t := float(i) / float(steps)
		var ny := y + hgt * t
		var half := lerpf(w_top, w_bot, t) * 0.5
		img.fill_rect(Rect2i(int((cx - half) * w), int(ny * h), int(half * 2.0 * w), 1), col)


var w: int
var h: int


func _init(p_w: int, p_h: int) -> void:
	w = p_w
	h = p_h
