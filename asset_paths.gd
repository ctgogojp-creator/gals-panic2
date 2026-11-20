class_name AssetPaths
extends RefCounted
## 実行ファイル直下の data/ を優先してアセットを解決する。
##  - エクスポート後: <exeのあるフォルダ>/data/<相対パス> があればそれを、無ければ pck 内を使う。
##  - エディタ実行時: res:// をそのまま使う。
## autoload にせず static にしている理由: `godot --headless -s test_x.gd` では
## autoload が生成されず、AP のようなグローバル名が解決できないため。
## 画像・BGM・効果音・ボイスを exe 配下のフォルダで差し替えできるようにするため。

static var _base := ""
static var _tex := {}
static var _audio := {}


## 基準パスを強制的に設定する(検証・ツール用。data/ を指せばそこから読む)。
static func set_base(path: String) -> void:
	_base = path
	_tex.clear()
	_audio.clear()


## アセット探索の基準パス。
static func base() -> String:
	if _base == "":
		if OS.has_feature("editor"):
			_base = "res://"
		else:
			_base = OS.get_executable_path().get_base_dir().replace("\\", "/") + "/data/"
	return _base


## 実際の読み込みパスを返す(data/ 優先、無ければ res://)。
static func rel_path(rel: String) -> String:
	var p: String = base() + rel
	if not p.begins_with("res://") and FileAccess.file_exists(p):
		return p
	return "res://" + rel


static func has(rel: String) -> bool:
	var p := rel_path(rel)
	if FileAccess.file_exists(p):
		return true
	return ResourceLoader.exists(p)


static func image(rel: String) -> Image:
	var img: Image = Image.load_from_file(rel_path(rel))
	if img == null:
		return null
	if img.is_empty():
		return null
	return img


static func texture(rel: String) -> Texture2D:
	if _tex.has(rel):
		return _tex[rel]
	var t: Texture2D = null
	var img := image(rel)          # data/ 配下の生ファイル(エディタでは res:// の生ファイル)
	if img != null:
		t = ImageTexture.create_from_image(img)
	else:
		var p := "res://" + rel    # pck に同梱したインポート済み画像へフォールバック
		if ResourceLoader.exists(p):
			var res = load(p)
			if res is Texture2D:
				t = res
	_tex[rel] = t
	return t


## 音声を読む。pck 内はインポート済みリソース、data/ 配下の生ファイルは実行時にデコードする。
static func audio(rel: String) -> AudioStream:
	if _audio.has(rel):
		return _audio[rel]
	var s: AudioStream = null
	var p := rel_path(rel)
	if p.begins_with("res://"):
		if ResourceLoader.exists(p):
			s = load(p)
	else:
		var bytes := FileAccess.get_file_as_bytes(p)
		if bytes.size() > 0:
			var ext := rel.get_extension().to_lower()
			if ext == "mp3":
				var m = AudioStreamMP3.new()
				m.data = bytes
				s = m
			elif ext == "wav":
				s = _wav_to_stream(bytes)
	_audio[rel] = s
	return s


## 標準 PCM WAV を AudioStreamWAV に変換する(効果音は自作の 16bit PCM WAV)。
static func _wav_to_stream(bytes: PackedByteArray) -> AudioStream:
	if bytes.size() < 44:
		return null
	if bytes.slice(0, 4).get_string_from_ascii() != "RIFF":
		return null
	if bytes.slice(8, 12).get_string_from_ascii() != "WAVE":
		return null
	var pos := 12
	var channels := 1
	var rate := 44100
	var bits := 16
	var data := PackedByteArray()
	while pos + 8 <= bytes.size():
		var id := bytes.slice(pos, pos + 4).get_string_from_ascii()
		var sz := int(bytes.decode_u32(pos + 4))
		var body := pos + 8
		if body + sz > bytes.size():
			sz = bytes.size() - body
		if id == "fmt ":
			channels = int(bytes.decode_u16(body + 2))
			rate = int(bytes.decode_u32(body + 4))
			bits = int(bytes.decode_u16(body + 14))
		elif id == "data":
			data = bytes.slice(body, body + sz)
		pos = body + sz + (sz % 2)
	if data.is_empty():
		return null
	var w = AudioStreamWAV.new()
	w.data = data
	w.mix_rate = rate
	w.stereo = channels >= 2
	if bits == 8:
		w.format = AudioStreamWAV.FORMAT_8_BITS
	else:
		w.format = AudioStreamWAV.FORMAT_16_BITS
	return w
