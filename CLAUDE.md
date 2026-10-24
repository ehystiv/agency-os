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

**Desktop as mediator:** `desktop/desktop.gd` is the only script that knows all the pieces (icons, `WindowManager`, taskbar, Start menu, balloon, boot, screensaver). The other pieces only emit signals. Apps never reference each other: an `AppContent` (`core/app_content.gd`) emits `app_requested(id, args)`, `notification_requested`, `command_requested` or `title_changed`, and the target app receives `args` in `on_opened(args)`. A closed window is only hidden, so apps keep their state, and `on_opened` runs every time the window is shown.

**Adding an app:**
1. Create the scene under `apps/<name>/` with a root that extends `AppContent`.
2. Create an `AppInfo` resource in `data/apps/<name>.tres` (id, label, icon, scene, default size, desktop/Start-menu flags, `menu_strip`).
3. Add it to `data/apps/registry.tres`. The order there is the icon/Start-menu order.

**Data-driven content:**
- `data/canon.json`: canon sections, gated by level.
- `data/glitch.json`: glitch name → description, timing, the webcam reaction, and whether it counts as motion. The names are also the ids used in `glitch_layer.gd`, `crt.gd` and `desktop.gd`.
- `data/secret_commands.json`: command-prompt secrets unlocked by level.
- `data/voice_examples.json`.
- `data/prompt/*.txt`: prompt templates with `{placeholder}` keys.

**Look:**
- The global theme is `ui/theme/agency98.tres`, a large `Theme` that uses the custom `StyleBoxBevel` (`ui/theme/stylebox_bevel.gd`) for '98 bevels. Widgets pick their style by `theme_type_variation` (e.g. `ListRow`, `MsgEntity`, `PrimaryButton`). Check the theme before adding new variations.
- 3D views (dice tray, webcam cage) render in a SubViewport at low resolution that is redrawn on demand.

## Conventions (from the original brief)

- One feature at a time; the project must open and run after each change.
- For new features, propose the node tree and the look before writing code.
- Keep scripts small and typed. Use signals instead of cross-references, and lambdas instead of static callables. Comment only where it helps.
- `Packed*Array`s are copied by value, and lambdas capture locals by value. Both have caused bugs here before.
