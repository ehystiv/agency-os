class_name ItalianDate
extends RefCounted
## Short Italian dates (the interface language) from the ISO strings used in saves.

const MONTHS: PackedStringArray = ["gen", "feb", "mar", "apr", "mag", "giu", "lug", "ago", "set", "ott", "nov", "dic"]
const MONTH_NAMES: PackedStringArray = ["gennaio", "febbraio", "marzo", "aprile", "maggio", "giugno", "luglio", "agosto", "settembre", "ottobre", "novembre", "dicembre"]
const WEEKDAYS: PackedStringArray = ["domenica", "lunedì", "martedì", "mercoledì", "giovedì", "venerdì", "sabato"]


## Today as "YYYY-MM-DD", in local time.
static func today() -> String:
	return Time.get_datetime_string_from_system().left(10)


## "2026-10-24" -> "YYYY-MM-DD" of the day moved by days.
static func add_days(day: String, days: int) -> String:
	var unix := Time.get_unix_time_from_datetime_string(day + "T12:00:00") + days * 86400
	return Time.get_datetime_string_from_unix_time(unix).left(10)


## 0 = Sunday … 6 = Saturday.
static func weekday_index(day: String) -> int:
	return int(Time.get_datetime_dict_from_unix_time(Time.get_unix_time_from_datetime_string(day + "T12:00:00")).weekday)


## "2026-10-24" -> "sab"
static func weekday_short(day: String) -> String:
	return WEEKDAYS[weekday_index(day)].left(3)


## "2026-10-24" -> "sabato 24 ottobre"
static func long_day(day: String) -> String:
	var parts := day.split("-")
	return "%s %d %s" % [WEEKDAYS[weekday_index(day)], int(parts[2]), MONTH_NAMES[int(parts[1]) - 1]]


## "2026-10-24T21:15:03" -> "24/10/26"
static func numeric(iso: String) -> String:
	var parts := iso.left(10).split("-")
	if parts.size() != 3:
		return ""
	return "%s/%s/%s" % [parts[2], parts[1], parts[0].right(2)]


## "2026-10-24T21:15:03" -> "21:15"
static func time(iso: String) -> String:
	return iso.substr(11, 5) if iso.length() >= 16 else ""


## "2026-10-24T21:15:03" -> "2026-10-24"
static func day(iso: String) -> String:
	return iso.left(10)


## "2026-10-24T21:15:03" -> "24 ott"; empty if the date can't be read.
static func short(iso: String) -> String:
	var parts := iso.left(10).split("-")
	if parts.size() != 3:
		return ""
	var month := int(parts[1])
	if month < 1 or month > 12:
		return ""
	return "%d %s" % [int(parts[2]), MONTHS[month - 1]]
