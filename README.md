# AgencyOS 98

A fake late-90s operating system for the General Manager of a **Triangle Agency** campaign. It runs on the GM's computer at the table. Its main app is the *Linea riservata* (reserved line), an unregistered chat channel with **U0047BB**, the Entity held in the Agency's vault, voiced by a language model.

> **The user interface is in Italian only.** The app was made for the Italian edition of the game: every window, message and prompt the model receives is in Italian. The code and the documentation are in English.

Unofficial fan project, not affiliated with the publishers of Triangle Agency.

## What it does

The desktop looks and behaves like a '98-style OS: icons, draggable windows, a taskbar, a Start menu, notification balloons, a BIOS-style boot, a screensaver and an optional CRT effect. The apps:

| App | What it's for |
| --- | --- |
| **Linea riservata** | Chat with the Entity. Replies stream in as they're written. Closing an interview makes the Entity write its own memories of it, and those memories carry over to later sessions. |
| **Fascicolo** | The Manager's dossier: access level, campaign notes the Entity reads, the interview archive, and the Entity's cumulative memory (editable). |
| **Canone** | What the Entity knows. Sections above the current access level are redacted, but the GM can still read them. |
| **Taccuino** | Note pages linked to sessions, saved automatically and exportable to an **Obsidian** vault as Markdown. |
| **AMail** | Memos from the Agency, written by the model between sessions. |
| **Blocco note** | Opens the files the Entity leaves on the desktop. If the GM corrects a file, the corrected version becomes the truth for the Entity. |
| **Calcolatrice** | Rolls 6d4 with real physics, applies the roll rules (3s, Chaos, Triscendence) and tracks the branch's Chaos pool. |
| **Agenda** | Session calendar with a preparation checklist. The next session shows in the taskbar. |
| **Webcam** | Live low-res 3D feed of the Entity's cage. The Entity reacts to the conversation and to glitches. |
| **Prompt** | A DOS-like command prompt, with secret commands unlocked by access level. |
| **Registro eventi**, **Cestino**, **Contenimento**, **Lettore**, **Pannello di controllo** | Event viewer, trash (with the Entity's discarded drafts), an Anomaly-themed minesweeper, synthesized hold music, and the settings. |

The Entity's access level rises every three closed interviews and unlocks more of the canon, new files and new secret commands. During a conversation the model may trigger visual glitches. The Agency may also run "searches" on the channel, and the Entity has to hide from them.

## Requirements

- **Godot 4.7** to run or export the project. It has been developed and tested on macOS.
- **A language model**, which you configure in *Impostazioni della linea*. Each provider remembers its own settings:
  - **Local:** any OpenAI-compatible server: LM Studio (default, `http://localhost:1234/v1`), Ollama, or llama.cpp server. It has been tested with Gemma 3 12B and Qwen 3.5 9B. For "thinking" models such as Qwen, turn on *Saltalo* to skip reasoning and get much faster replies.
  - **Hugging Face:** Inference Providers router plus an access token.
  - **Claude:** Anthropic API key.

  API keys are stored in plain text in the settings file. Instead of the key you can enter the name of an environment variable prefixed with `$`, for example `$ANTHROPIC_API_KEY`.

The boot sequence checks whether the model server is reachable, and *Prova connessione* in the settings runs a full round trip.

## Running

Open the folder in Godot 4.7 and press Play. To run it from the command line:

```sh
godot --path .
```

Fullscreen: `F11`, `Cmd+Ctrl+F` or `Alt+Enter`, or toggle it from the Start menu or the Control panel.

## Building for macOS

1. In Godot, export with the **macOS** preset. *Import ETC2 ASTC* must be enabled in the project settings. With ad-hoc signing, keep the app sandbox **disabled**, otherwise macOS kills the app at launch.
2. Optionally, wrap the result in a drag-to-Applications installer:

   ```sh
   tools/make_dmg.sh AgencyOS.app            # or the .dmg exported by Godot
   tools/make_dmg.sh AgencyOS.app out.dmg --simple   # skip the Finder icon layout
   ```

## Data

All data lives in Godot's user folder. On macOS that's `~/Library/Application Support/Godot/app_userdata/AgencyOS/`:

- `config/ui.json`: window positions, wallpaper, audio and effect settings.
- `config/model.cfg`: model provider settings. You can edit it by hand.
- `campaigns/branch/`: the campaign (interviews, notes, memory, Notebook, mail, files, trash, agenda), as plain JSON.

Saves from version 0.1 are converted automatically at startup, and the originals are kept in `legacy_0.1/`.

*Azzera la Filiale…* in the Start menu resets the campaign. Settings, the agenda and, optionally, notes and the Notebook are kept.

## Project layout

```
autoload/   global services: saves, sounds, model access (Brain + providers), campaign logic, the Entity's state
core/       plain logic classes (interviews, dice rules, minesweeper, Markdown export, synth…)
apps/       one folder per app
desktop/    desktop, windows manager, icons, taskbar, Start menu
system/     boot screen, screensaver, CRT overlay
data/       app registry, canon, glitch table, secret commands, prompt templates (Italian)
ui/         theme, icons, fonts, wallpapers
reference/  the original brief and the HTML prototype
tools/      macOS installer script
```

See `CLAUDE.md` for a more detailed architecture overview.

## Credits

Fonts: IBM Plex Mono, VT323 and Shantell Sans, all under the SIL Open Font License (license files in `ui/fonts/`). Every sound and every piece of music is synthesized at runtime.
