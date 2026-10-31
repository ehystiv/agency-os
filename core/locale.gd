class_name Locale
## Interface language. Italian is the source language: the msgids of the
## translations are the Italian texts, so "it" needs no translation file.
## The language is applied once at startup (Save._ready); changing it in the
## Control panel takes effect at the next restart.

const PREF := "language"
const SOURCE := "it"
## Language code → name shown in the Control panel, in display order.
const LANGUAGES := {"it": "Italiano", "en": "English"}
const TRANSLATIONS_DIR := "res://locale"
const DATA_DIR := "res://data/"


## Reads the saved language (on first start, the system's) and loads its translation.
static func setup() -> void:
	if not Save.has_ui(PREF):
		Save.set_ui(PREF, detect())
	var language := current()
	var path := "%s/%s.po" % [TRANSLATIONS_DIR, language]
	if language != SOURCE and ResourceLoader.exists(path):
		var translation: Translation = load(path)
		if translation != null:
			TranslationServer.add_translation(translation)
	TranslationServer.set_locale(language)


## The system language if supported, otherwise English.
static func detect() -> String:
	var language := OS.get_locale_language()
	return language if LANGUAGES.has(language) else "en"


## The language chosen at startup (the saved one may differ until restart).
static func current() -> String:
	var language := str(Save.get_ui(PREF, SOURCE))
	return language if LANGUAGES.has(language) else SOURCE


static func active() -> String:
	var language := TranslationServer.get_locale().get_slice("_", 0)
	return language if LANGUAGES.has(language) else SOURCE


## Localized version of a game data file: "res://data/canon.json" becomes
## "res://data/en/canon.json" when it exists for the active language.
static func data_path(path: String) -> String:
	var language := active()
	if language == SOURCE or not path.begins_with(DATA_DIR):
		return path
	var localized := DATA_DIR + language + "/" + path.trim_prefix(DATA_DIR)
	return localized if FileAccess.file_exists(localized) else path
