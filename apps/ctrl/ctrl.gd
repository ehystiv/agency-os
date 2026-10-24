extends AppContent
## Control panel: wallpaper, screensaver, audio, effects and system information.
## Only writes the settings; their users update through Save.ui_changed or Sfx.

const SAVER_CHOICES: Array[int] = [1, 3, 5, 10, 0]
const DEFAULTS := {
	"wallpaper": "lattice",
	"screensaver_minutes": 3,
	"reduced_motion": false,
	"glitches_enabled": true,
	"crt_enabled": true,
	"show_boot": true,
}
const DEFAULT_VOLUME := 0.8

var _loading := false

@onready var _wallpapers: Array[CheckBox] = [%Lattice, %Vault, %Solid]
@onready var _saver: OptionButton = %Saver
@onready var _volume: HSlider = %Volume
@onready var _sounds: CheckBox = %Sounds
@onready var _full_motion: CheckBox = %FullMotion
@onready var _reduced_motion: CheckBox = %ReducedMotion
@onready var _glitches: CheckBox = %Glitches
@onready var _crt: CheckBox = %Crt
@onready var _fullscreen: CheckBox = %Fullscreen
@onready var _boot: CheckBox = %ShowBoot
@onready var _info: Label = %Info


func _ready() -> void:
	var wallpaper_group := ButtonGroup.new()
	for i in _wallpapers.size():
		_wallpapers[i].button_group = wallpaper_group
		_wallpapers[i].toggled.connect(_on_wallpaper_toggled.bind(Wallpaper.MODES[i]))
	var motion_group := ButtonGroup.new()
	_full_motion.button_group = motion_group
	_reduced_motion.button_group = motion_group
	_reduced_motion.toggled.connect(func(on: bool) -> void: _store_setting(&"reduced_motion", on))
	for minutes in SAVER_CHOICES:
		_saver.add_item("Mai" if minutes == 0 else "%d %s" % [minutes, "minuto" if minutes == 1 else "minuti"], minutes)
	_saver.item_selected.connect(func(index: int) -> void: _store_setting(&"screensaver_minutes", _saver.get_item_id(index)))
	_volume.value_changed.connect(func(value: float) -> void:
		if not _loading:
			Sfx.volume = value / 100.0)
	_volume.drag_ended.connect(func(_changed: bool) -> void: Sfx.play(&"ding"))
	_sounds.toggled.connect(func(on: bool) -> void:
		if not _loading:
			Sfx.enabled = on)
	_glitches.toggled.connect(func(on: bool) -> void: _store_setting(&"glitches_enabled", on))
	_crt.toggled.connect(func(on: bool) -> void: _store_setting(&"crt_enabled", on))
	_fullscreen.toggled.connect(func(on: bool) -> void: _store_setting(&"fullscreen", on))
	_boot.toggled.connect(func(on: bool) -> void: _store_setting(&"show_boot", on))
	%SaverPreview.pressed.connect(func() -> void: command_requested.emit(&"screensaver"))
	%ArrangeWindows.pressed.connect(func() -> void: command_requested.emit(&"arrange_windows"))
	%AlignIcons.pressed.connect(func() -> void: command_requested.emit(&"align_icons"))
	%Defaults.pressed.connect(_restore_defaults)
	Save.ui_changed.connect(func(_key: String) -> void: _load())
	Sfx.settings_changed.connect(_load)
	_load()


func on_opened(_args: Dictionary = {}) -> void:
	_load()


func _load() -> void:
	_loading = true
	var wallpaper := StringName(Save.get_ui("wallpaper", DEFAULTS.wallpaper))
	for i in _wallpapers.size():
		_wallpapers[i].set_pressed_no_signal(Wallpaper.MODES[i] == wallpaper)
	_saver.select(maxi(0, _saver.get_item_index(int(Save.get_ui("screensaver_minutes", DEFAULTS.screensaver_minutes)))))
	_volume.value = Sfx.volume * 100.0
	_sounds.set_pressed_no_signal(Sfx.enabled)
	var reduced := bool(Save.get_ui("reduced_motion", false))
	_full_motion.set_pressed_no_signal(not reduced)
	_reduced_motion.set_pressed_no_signal(reduced)
	_glitches.set_pressed_no_signal(bool(Save.get_ui("glitches_enabled", true)))
	_crt.set_pressed_no_signal(bool(Save.get_ui("crt_enabled", true)))
	_fullscreen.set_pressed_no_signal(bool(Save.get_ui("fullscreen", false)))
	_boot.set_pressed_no_signal(bool(Save.get_ui("show_boot", true)))
	_info.text = _system_info()
	_loading = false


func _store_setting(key: StringName, value: Variant) -> void:
	if not _loading:
		Save.set_ui(String(key), value)


func _on_wallpaper_toggled(on: bool, mode: StringName) -> void:
	if on:
		_store_setting(&"wallpaper", String(mode))


func _restore_defaults() -> void:
	for key: String in DEFAULTS:
		Save.set_ui(key, DEFAULTS[key])
	Sfx.volume = DEFAULT_VOLUME
	Sfx.enabled = true
	_load()


func _system_info() -> String:
	var mail := Campaign.correspondence
	return "\n".join([
		"AgencyOS 98 [Versione 4.98.0047] · Modalità Sicura",
		"Filiale: %s · livello di accesso %d/5" % [Save.campaign_id, Campaign.level()],
		"Colloqui: %d · memo: %d · file non registrati: %d" % [Campaign.interviews.size(), mail.delivered_mail().size(), mail.delivered_files().size()],
		"Linea: %s · %s" % [Brain.get_setting("model"), Brain.get_setting("url")],
		"Dati: %s" % ProjectSettings.globalize_path("user://"),
	])
