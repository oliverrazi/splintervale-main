extends Node

## Settings Autoload — speichert/lädt Spiel-Einstellungen via ConfigFile.
##
## Registrierung als Autoload:
##   Project Settings → Autoload → Pfad: res://path/to/settings.gd, Name: Settings
##
## Verwendung:
##   Settings.master_volume = 0.8       # setzt + speichert automatisch
##   var v: float = Settings.master_volume   # liest
##   Settings.apply_all()                # alle Werte aufs Spiel anwenden (Audio, Display, DoF)

const CONFIG_PATH: String = "user://settings.cfg"



# ── Audio (0.0 – 1.0) ──────────────────────────────────────────
var master_volume: float = 0.8 : set = _set_master_volume
var music_volume: float  = 0.7 : set = _set_music_volume
var sfx_volume: float    = 0.8 : set = _set_sfx_volume

# ── Display ────────────────────────────────────────────────────
var fullscreen: bool = false : set = _set_fullscreen
var vsync_enabled: bool = true : set = _set_vsync_enabled

# ── Graphics: Depth of Field ───────────────────────────────────
# bokeh_shape: 0 = Box, 1 = Hexagon, 2 = Circle
var dof_bokeh_shape: int = 1 : set = _set_dof_bokeh_shape
# bokeh_quality: 0 = Very Low, 1 = Low, 2 = Medium, 3 = High
var dof_bokeh_quality: int = 2 : set = _set_dof_bokeh_quality
var dof_use_jitter: bool = false : set = _set_dof_use_jitter

# Internes Flag um beim Laden nicht zurückzuspeichern
var _loading: bool = false


# ══════════════════════════════════════════════════════════════
#  LIFECYCLE
# ══════════════════════════════════════════════════════════════

func _ready() -> void:
	load_settings()
	apply_all()


# ══════════════════════════════════════════════════════════════
#  LOAD / SAVE
# ══════════════════════════════════════════════════════════════

func load_settings() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(CONFIG_PATH)
	if err != OK:
		# Datei existiert noch nicht — Defaults bleiben
		return
	
	_loading = true
	fullscreen        = cfg.get_value("display", "fullscreen",    fullscreen)
	vsync_enabled     = cfg.get_value("display", "vsync_enabled", vsync_enabled)
	master_volume     = cfg.get_value("audio",    "master_volume",     master_volume)
	music_volume      = cfg.get_value("audio",    "music_volume",      music_volume)
	sfx_volume        = cfg.get_value("audio",    "sfx_volume",        sfx_volume)
	fullscreen        = cfg.get_value("display",  "fullscreen",        fullscreen)
	dof_bokeh_shape   = cfg.get_value("graphics", "dof_bokeh_shape",   dof_bokeh_shape)
	dof_bokeh_quality = cfg.get_value("graphics", "dof_bokeh_quality", dof_bokeh_quality)
	dof_use_jitter    = cfg.get_value("graphics", "dof_use_jitter",    dof_use_jitter)
	_loading = false


func save_settings() -> void:
	if _loading:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("display", "fullscreen",    fullscreen)
	cfg.set_value("display", "vsync_enabled", vsync_enabled)
	cfg.set_value("audio",    "master_volume",     master_volume)
	cfg.set_value("audio",    "music_volume",      music_volume)
	cfg.set_value("audio",    "sfx_volume",        sfx_volume)
	cfg.set_value("display",  "fullscreen",        fullscreen)
	cfg.set_value("graphics", "dof_bokeh_shape",   dof_bokeh_shape)
	cfg.set_value("graphics", "dof_bokeh_quality", dof_bokeh_quality)
	cfg.set_value("graphics", "dof_use_jitter",    dof_use_jitter)
	cfg.save(CONFIG_PATH)


# ══════════════════════════════════════════════════════════════
#  APPLY (auf Engine anwenden)
# ══════════════════════════════════════════════════════════════

func apply_all() -> void:
	apply_audio()
	apply_display()
	apply_graphics()


func apply_audio() -> void:
	_apply_bus("Master", master_volume)
	_apply_bus("Music",  music_volume)
	_apply_bus("Sfx",    sfx_volume)


func _apply_bus(bus_name: String, value: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		# Versuch Master als Fallback bei Index 0
		if bus_name == "Master":
			idx = 0
		else:
			return
	if value <= 0.001:
		AudioServer.set_bus_mute(idx, true)
	else:
		AudioServer.set_bus_mute(idx, false)
		AudioServer.set_bus_volume_db(idx, linear_to_db(value))


func apply_display() -> void:
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		
	if vsync_enabled:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	


func apply_graphics() -> void:
	# Depth of Field: globale Project Settings, wirkt auf alle Camera3D
	# mit aktiviertem DoF in ihren CameraAttributes-Resourcen.
	ProjectSettings.set_setting(
		"rendering/camera/depth_of_field/depth_of_field_bokeh_shape",
		dof_bokeh_shape
	)
	ProjectSettings.set_setting(
		"rendering/camera/depth_of_field/depth_of_field_bokeh_quality",
		dof_bokeh_quality
	)
	ProjectSettings.set_setting(
		"rendering/camera/depth_of_field/depth_of_field_use_jitter",
		dof_use_jitter
	)


# ══════════════════════════════════════════════════════════════
#  SETTERS (auto-save + auto-apply)
# ══════════════════════════════════════════════════════════════

func _set_master_volume(v: float) -> void:
	master_volume = clamp(v, 0.0, 1.0)
	if not _loading:
		_apply_bus("Master", master_volume)
		save_settings()

func _set_vsync_enabled(v: bool) -> void:
	vsync_enabled = v
	if not _loading:
		apply_display()
		save_settings()

func _set_music_volume(v: float) -> void:
	music_volume = clamp(v, 0.0, 1.0)
	if not _loading:
		_apply_bus("Music", music_volume)
		save_settings()


func _set_sfx_volume(v: float) -> void:
	sfx_volume = clamp(v, 0.0, 1.0)
	if not _loading:
		_apply_bus("Sfx", sfx_volume)
		save_settings()


func _set_fullscreen(v: bool) -> void:
	fullscreen = v
	if not _loading:
		apply_display()
		save_settings()


func _set_dof_bokeh_shape(v: int) -> void:
	dof_bokeh_shape = clamp(v, 0, 2)
	if not _loading:
		apply_graphics()
		save_settings()


func _set_dof_bokeh_quality(v: int) -> void:
	dof_bokeh_quality = clamp(v, 0, 3)
	if not _loading:
		apply_graphics()
		save_settings()


func _set_dof_use_jitter(v: bool) -> void:
	dof_use_jitter = v
	if not _loading:
		apply_graphics()
		save_settings()
