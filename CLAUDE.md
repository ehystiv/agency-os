# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

AgencyOS 98: a fake late-90s desktop OS, written in Godot 4.7 (GDScript), that the General Manager uses at the table when running Triangle Agency (Italian edition). Its core is the "reserved line", a chat with the Entity U0047BB played by an LLM (local through LM Studio/Ollama/llama.cpp, or remote through Hugging Face or Claude). The original brief and the HTML prototype it was ported from are in `reference/`.

**Language rule:** code, identifiers, comments, file names, save-file keys and JSON keys are in English. Everything shown on screen, plus the prompts and game data the model reads (`data/prompt/*.txt`, the content of `data/*.json`), stays in Italian.

## Running and verifying

There is no build step, linter or test suite in the repo. Godot is not on PATH: it's at `~/Downloads/Godot.app/Contents/MacOS/Godot`.

The user usually has the editor open on this project. Don't run Godot on the project folder itself: that would touch the user's real `user://` data and collide with the editor. Verify on a copy instead:

```sh
COPY=<scratchpad>/copy
rsync -a --delete --exclude .godot --exclude .git --exclude '*.import' ./ $COPY/
sed -i '' 's/^config\/name=.*/config\/name="AgencyOS-verifica"/' $COPY/project.godot   # separate user:// dir
G=~/Downloads/Godot.app/Contents/MacOS/Godot
$G --headless --path $COPY --import    # run twice when new SVGs were added
$G --headless --path $COPY             # or windowed, for screenshots
rm -rf ~/Library/Application\ Support/Godot/app_userdata/AgencyOS-verifica   # clean up afterwards
```

To test something, add a temporary autoload to the copy's `project.godot` (after `Entity=`). The autoload drives the UI through the `Windows` node (`WindowManager.open(id, args)`), prints its checks and saves screenshots with `get_viewport().get_texture().get_image().save_png(...)`. `godot --script` won't work for this, because the autoloads (`Campaign`, `Brain`…) don't exist in that mode.

Other things to know:
- Godot's SVG rasterizer ignores `rgba()`: use `fill-opacity` / `stroke-opacity`.
- **Real LLM tests:** use LM Studio (`~/.lmstudio/bin/lms`, models `gemma-3-12b-it-qat` and `qwen3.5-9b-mlx`). Leave the server and the loaded model as you found them.
- **macOS installer:** `tools/make_dmg.sh <AgencyOS.app|exported.dmg> [out.dmg] [--simple]` builds the installer DMG. Godot's export needs "Import ETC2 ASTC" enabled. With ad-hoc signing the app sandbox must stay off, or the app is killed at launch.

## Architecture

**Autoloads** (`autoload/`), in load order:
- `BootPatch`: loads the downloaded update `.pck` in its `_init()`, before anything else (see "Updates" below). It can't be patched itself, so keep it tiny.
- `Save`: all persistence. It holds the UI prefs (`user://config/ui.json`, `get_ui`/`set_ui`, emits `ui_changed`, debounced writes) and the per-campaign files under `user://campaigns/<id>/`. Before reading anything it runs `SaveMigration.run()`, which converts 0.1 saves (Italian names) and moves the originals to `user://legacy_0.1/`. If you change a save format, keep this migration path working.
- `Sfx`: system sounds synthesized at startup by `core/synth.gd` (no audio files), plus the master volume.
- `Brain`: the single gateway to the model. `chat(messages, options)` returns a `BrainRequest`, which has its own signals (`chunk_received`, `completed`/`failed`, `finished`). The providers in `autoload/providers/` share one OpenAI-compatible HTTP job (`OpenAIJob`, polled every frame, no threads). Claude is handled as a dialect of that job. `ThinkFilter` strips `<think>` blocks, and with `skip_reasoning` an empty-think prefill is added. Settings live in `user://config/model.cfg`: `[line] provider=…` plus one section per provider. An `api_key` starting with `$` names an environment variable.
- `Campaign`: pure game logic, no UI. It covers:
  - interviews (`core/interview.gd`, one JSON file per interview);
  - the access level (it goes up every 3 closed interviews);
  - building the Entity's prompt (`build_messages`/`entity_prompt` fill the `{placeholders}` of `data/prompt/entity.txt` with canon, notes, memory, memos and files, all fitted into a token budget);
  - summaries and cumulative memory written when an interview closes;
  - the glitch and AgencyOS-search rules;
  - the Notebook pages, the trash and the agenda.

  Its child node `Correspondence` produces AgencyOS mail memos, desktop files and drafts in the background through `LlmJson` (JSON-schema output, with a free-text fallback). Its model requests run one at a time in a queue, and their results are delivered when the next session opens.
- `Entity`: the subject's shared mood (agitation, tint, shrink, signal). The Line and the glitches stir it, and the webcam, CRT and desktop react through `glitch_started`.
- `Updater`: checks GitHub for a newer patch, downloads and verifies it, and writes it to `user://updates/` for `BootPatch` to load at the next start.

**Desktop as mediator:** `desktop/desktop.gd` is the only script that knows all the pieces (icons, `WindowManager`, taskbar, Start menu, balloon, boot, screensaver). The other pieces only emit signals. Apps never reference each other: an `AppContent` (`core/app_content.gd`) emits `app_requested(id, args)`, `notification_requested`, `command_requested` or `title_changed`, and the target app receives `args` in `on_opened(args)`. A closed window is only hidden, so apps keep their state, and `on_opened` runs every time the window is shown.

**Adding an app:**
1. Create the scene under `apps/<name>/` with a root that extends `AppContent`.
2. Create an `AppInfo` resource in `data/apps/<name>.tres` (id, label, icon, scene, default size, desktop/Start-menu flags, `menu_strip`). With `resizable = true` the window gets draggable edges/corners and a maximize button, and `default_size` becomes its first size: the scene must then grow (scroll areas with `size_flags_vertical = 3`) and shrink to `min_size` (keep its own `custom_minimum_size` small). Fixed windows follow their content.
3. Add it to `data/apps/registry.tres`. The order there is the icon/Start-menu order.

**Data-driven content:**
- `data/canon.json`: canon sections, gated by level.
- `data/glitch.json`: glitch name → description, timing, the webcam reaction, and whether it counts as motion. The names are also the ids used in `glitch_layer.gd`, `crt.gd` and `desktop.gd`.
- `data/secret_commands.json`: command-prompt secrets unlocked by level.
- `data/voice_examples.json`.
- `data/prompt/*.txt`: prompt templates with `{placeholder}` keys.

**Look:**
- The global theme is `ui/theme/agency98.tres`, a large `Theme` that uses the custom `StyleBoxBevel` (`ui/theme/stylebox_bevel.gd`) for '98 bevels. Widgets pick their style by `theme_type_variation` (e.g. `ListRow`, `MsgEntity`, `PrimaryButton`). Check the theme before adding new variations.
- The desktop's logical resolution is the "Area dello schermo" (`core/screen_area.gd`, UI pref `screen_area`, Control panel › Schermo): it sets `content_scale_size` at runtime, so `project.godot`'s 1280×720 is only the default.
- 3D views (dice tray, webcam cage) render in a SubViewport at low resolution that is redrawn on demand.

## Updates (.pck patches)

The app updates itself by loading a Godot patch `.pck` on top of the files of the installed app (the **base**, i.e. the DMG). Tested on an exported 4.7.2 build: a pack loaded from the first autoload's `_init()` applies to the later autoloads, the main scene, `data/` and new `class_name`s, with no restart trick.

**Versions.** `application/config/version` in `project.godot` is the project version. The installed app's base version is the one its binary was exported with: `project.godot` inside a pack is never applied, so at runtime that setting always reads the base version. `BootPatch.version()` gives the version actually running.

**What a patch can't change**, so it needs a new DMG (a new base): `project.godot` (autoloads, settings, the main scene path), the engine version, `autoload/boot_patch.gd`, and the export preset. Everything else (scripts, scenes, `data/`, prompts, icons, the `Updater` itself) can ship as a patch.

**Releasing a patch:**
1. Bump `application/config/version` in `project.godot` (e.g. `0.1.1` → `0.1.2`).
2. `tools/make_patch.sh <base AgencyOS.app | installer .dmg> [out_dir] [--notes "…"]`. It exports with `--export-patch` against the base's `.pck` (on a temp copy, not the project folder), and writes `agencyos-<version>.pck` plus `update.json` (`version`, `base`, `file`, `url`, `sha256`, `size`, `notes`, `page`).
3. Create a GitHub release tagged `v<version>` with both files attached (the script prints the `gh release create` command). The app reads `https://github.com/ehystiv/agency-os/releases/latest/download/update.json`, so the newest release must always carry an `update.json`.

Patches are **cumulative against the base**: always build against the DMG's `.pck`, never against a previous patch, so a user who skipped versions downloads only the latest one.

**Releasing a new base:** export the DMG with the new version, run `tools/make_dmg.sh`, and attach the installer to the release together with an `update.json` whose `base` equals its own `version` (`make_patch.sh` with the new app as base produces a near-empty patch that does this). Apps on the old base see a different `base` and point the user to the release page instead of downloading.

**At runtime** (`user://updates/`):
- `current.json` describes the installed patch. The `Updater` writes it last, only after the download's size and sha256 match.
- `BootPatch` loads the pack only when `current.json`'s `base` equals the running base version. If it doesn't match, a new DMG was installed, and the patch files are deleted.
- **Rollback:** before loading, `BootPatch` writes a `booting` flag, and the desktop removes it (`BootPatch.confirm()`) once its `_ready` has finished. If the flag is still there at the next start, the patch is marked `failed`, isn't loaded, and the `Updater` won't offer that version again.
- **UI:** the *Aggiornamento* tab of the Control panel (`ctrl`, opened on it with `{"tab": "update"}`) checks, downloads and restarts. The desktop runs `Updater.check_daily()` a few seconds after boot when the `update_auto` UI pref is on. It shows a balloon when an automatic check finds something, when a download finishes, and once after a patch is installed or rolled back (`update_seen` / `update_failed_seen`).
- In the editor, patches are ignored, so they don't shadow the files you're editing. To test the loader from a source run, pass `-- --with-patch`. A real end-to-end test needs an exported app (export templates for 4.7.2 are installed).

If a patch changes a save format, `SaveMigration` must also cope with a rollback to the base: an older base must still read, or at least not destroy, the newer saves.

## Conventions (from the original brief)

- One feature at a time; the project must open and run after each change.
- For new features, propose the node tree and the look before writing code.
- Keep scripts small and typed. Use signals instead of cross-references, and lambdas instead of static callables. Comment only where it helps.
- `Packed*Array`s are copied by value, and lambdas capture locals by value. Both have caused bugs here before.
