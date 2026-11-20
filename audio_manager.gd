class_name AudioManager
extends Node
## 場面の BGM と効果音をまとめて扱うマネージャ。
## 素材は res://audio/ に置く（無くても無音で動く＝テスト実行できる）。
##  ・BGM   : bgm_title / bgm_stage / bgm_clear / bgm_roulette / bgm_over
##  ・効果音 : sfx_draw, sfx_step, sfx_capture, sfx_bonus, sfx_hit, sfx_life, sfx_time,
##            sfx_wheel, sfx_wheel_stop, sfx_clear, sfx_gameover, sfx_select, sfx_monster, sfx_asteroid
##  ・声     : voice_clear1..3, voice_monster, voice_gameover, voice_start
##  ・物音   : sfx_1up

const MUSIC_DIR := "res://audio/music/"
const SFX_DIR := "res://audio/sfx/"
const VOICE_DIR := "res://audio/voice/"

var _music: AudioStreamPlayer
var _voices: AudioStreamPlayer
var _sfx_pool: Array[AudioStreamPlayer] = []
var _cache := {}
var _current := ""
var muted := false


func _ready() -> void:
	_music = AudioStreamPlayer.new()
	_music.bus = "Master"
	_music.volume_db = -6.0
	add_child(_music)

	_voices = AudioStreamPlayer.new()
	_voices.bus = "Master"
	_voices.volume_db = -1.0
	add_child(_voices)

	for i in 10:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		p.volume_db = -3.0
		add_child(p)
		_sfx_pool.append(p)


func _load(path: String):
	if _cache.has(path):
		return _cache[path]
	var rel := path
	if rel.begins_with("res://"):
		rel = rel.substr(len("res://"))
	var s = AssetPaths.audio(rel)
	_cache[path] = s
	return s


## BGM を張り替える。同じ曲が再生中なら何もしない。
func play_music(name: String, fade: float = 0.0) -> void:
	if _current == name and _music.playing:
		return
	_current = name
	if muted:
		return
	var s = _load(MUSIC_DIR + name + ".mp3")
	if s == null:
		s = _load(MUSIC_DIR + name + ".ogg")
	if s == null:
		_music.stop()
		return
	if s is AudioStreamInteractive:
		pass
	_music.stream = s
	if s is AudioStreamMP3:
		s.loop = true
	_music.play()


func stop_music() -> void:
	_current = ""
	_music.stop()


func play_voice(name: String) -> void:
	if muted:
		return
	var s = _load(VOICE_DIR + name + ".mp3")
	if s == null:
		s = _load(VOICE_DIR + name + ".ogg")
	if s == null:
		return
	_voices.stream = s
	_voices.play()


## 効果音を1つ鳴らす（多重再生はプールで回す）。
func sfx(name: String, pitch: float = 1.0, vol_db: float = 0.0) -> void:
	if muted:
		return
	var s = _load(SFX_DIR + name + ".wav")
	if s == null:
		s = _load(SFX_DIR + name + ".ogg")
	if s == null:
		return
	for p in _sfx_pool:
		if not p.playing:
			p.stream = s
			p.pitch_scale = pitch
			p.volume_db = vol_db
			p.play()
			return
	_sfx_pool[0].stream = s
	_sfx_pool[0].pitch_scale = pitch
	_sfx_pool[0].volume_db = vol_db
	_sfx_pool[0].play()


func toggle_mute() -> bool:
	muted = not muted
	if muted:
		_music.stop()
		_voices.stop()
	return muted
