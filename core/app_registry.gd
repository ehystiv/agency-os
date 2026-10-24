class_name AppRegistry
extends Resource
## Ordered list of installed apps. The order applies to icons, Start menu and taskbar.

@export var apps: Array[AppInfo] = []


func find(id: StringName) -> AppInfo:
	for app in apps:
		if app.id == id:
			return app
	return null


func desktop_apps() -> Array[AppInfo]:
	var result: Array[AppInfo] = []
	for app in apps:
		if app.on_desktop:
			result.append(app)
	return result


func start_menu_apps() -> Array[AppInfo]:
	var result: Array[AppInfo] = []
	for app in apps:
		if app.on_start_menu:
			result.append(app)
	return result
