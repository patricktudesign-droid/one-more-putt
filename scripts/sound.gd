extends Node

## Six short placeholder sound effects, synthesised in code (no external
## audio assets needed yet — brief section 05 asset checklist / section 12
## notes the reference is a style target, not production assets).
## Never required to understand game state; purely reinforcing.

var _players: Array[AudioStreamPlayer] = []
var _next_player: int = 0
const POOL_SIZE := 4

var _putt_stream: AudioStreamWAV
var _chip_stream: AudioStreamWAV
var _wall_stream: AudioStreamWAV
var _sand_stream: AudioStreamWAV
var _cup_stream: AudioStreamWAV
var _hole_in_one_stream: AudioStreamWAV

func _ready() -> void:
	_putt_stream = _make_tone(520.0, 0.07, 0.9)
	_chip_stream = _make_tone(700.0, 0.09, 0.85, 950.0)
	_wall_stream = _make_tone(300.0, 0.05, 0.6)
	_sand_stream = _make_tone(180.0, 0.10, 0.4)
	_cup_stream = _make_tone(880.0, 0.18, 0.8, 1320.0)
	_hole_in_one_stream = _make_arpeggio([523.25, 659.25, 783.99, 1046.5], 0.11, 0.9)

	for i in range(POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)

func _make_tone(freq: float, duration: float, volume: float, freq_end: float = -1.0) -> AudioStreamWAV:
	var mix_rate := 22050
	var frame_count := int(duration * mix_rate)
	var data := PackedByteArray()
	data.resize(frame_count * 2)
	for i in range(frame_count):
		var t: float = float(i) / float(mix_rate)
		var progress: float = float(i) / float(max(1, frame_count - 1))
		var f: float = freq if freq_end < 0.0 else lerp(freq, freq_end, progress)
		var envelope: float = sin(PI * progress) # fades in and out, no clicks
		var sample: float = sin(TAU * f * t) * envelope * volume
		var v: int = clamp(int(sample * 32767.0), -32768, 32767)
		data.encode_s16(i * 2, v)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = data
	return stream

## Short ascending chime (a few notes back to back) for the hole-in-one
## celebration — distinct from the ordinary single-tone cup sound.
func _make_arpeggio(freqs: Array, note_duration: float, volume: float) -> AudioStreamWAV:
	var mix_rate := 22050
	var note_frames := int(note_duration * mix_rate)
	var data := PackedByteArray()
	data.resize(note_frames * freqs.size() * 2)
	for n in range(freqs.size()):
		var f: float = freqs[n]
		for i in range(note_frames):
			var t: float = float(i) / float(mix_rate)
			var progress: float = float(i) / float(max(1, note_frames - 1))
			var envelope: float = sin(PI * progress)
			var sample: float = sin(TAU * f * t) * envelope * volume
			var v: int = clamp(int(sample * 32767.0), -32768, 32767)
			data.encode_s16((n * note_frames + i) * 2, v)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = data
	return stream

func _play(stream: AudioStreamWAV) -> void:
	if not Save.sound_enabled:
		return
	var p := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	p.stream = stream
	p.play()

func play_putt() -> void:
	_play(_putt_stream)

func play_chip() -> void:
	_play(_chip_stream)

func play_wall() -> void:
	_play(_wall_stream)

func play_sand() -> void:
	_play(_sand_stream)

func play_cup() -> void:
	_play(_cup_stream)

func play_hole_in_one() -> void:
	_play(_hole_in_one_stream)
