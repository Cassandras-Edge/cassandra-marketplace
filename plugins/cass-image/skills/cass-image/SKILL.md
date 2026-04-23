---
name: cass-image
description: Generate or edit an image using the user's ChatGPT Plus/Pro subscription via `cass image`. Use whenever the user asks to generate, create, render, draw, or edit an image. Runs as a bash command — fast, no MCP round-trip, and the image auto-opens when finished.
---

# cass image

`cass image` produces PNGs by routing through the same undocumented endpoint Codex's built-in `image_gen` tool hits (`chatgpt.com/backend-api/codex/responses`). It reuses the Codex OAuth credentials at `~/.codex/auth.json`, so no `OPENAI_API_KEY` is required — just a valid ChatGPT Plus/Pro subscription and `codex login` already done.

Invoke it via the Bash tool. Do **not** look for an image-gen MCP tool — there isn't one. Bash is the blessed path.

## When to use

Any time the user asks to:

- "Generate an image of …" / "make a picture of …" / "draw me …"
- "Edit this image to …" / "turn this photo into …" (with a file path)
- "Give me a quick mockup / sketch / thumbnail of …"

## Basic usage

```bash
cass image "a cyberpunk cat holding a lightsaber"
```

This writes the PNG to `~/Downloads/cass-img-<timestamp>.png`, auto-opens it in the default image viewer, and prints the path.

## Flags you'll actually use

| Flag | What it does |
|---|---|
| `-f, --fast` | Render at `quality: low`. Much faster — default for quick iterations and mockups. |
| `-q, --quality {low,medium,high,auto}` | Explicit quality. Overrides `--fast`. Use `high` when the user cares about fidelity. |
| `-e, --edit PATH` | Edit an existing image (PNG/JPG/WEBP/GIF). The prompt becomes the edit instruction. |
| `-o, --out PATH` | Output path. Default is `~/Downloads/cass-img-<ts>.png`. |
| `-a, --aspect RATIO` | Aspect hint injected into the prompt (e.g. `16:9`, `1:1`, `3:4`). |
| `-s, --size {1K,2K,4K}` | Resolution hint injected into the prompt. |
| `--no-open` | Skip auto-opening (rarely needed; default is to open). |

## Recommended defaults for agents

Use `--fast` by default unless the user signals they want quality. It's several times faster and plenty good for mockups.

```bash
cass image --fast "product hero shot, matte black headphones on concrete"
cass image --fast --aspect 16:9 "desktop wallpaper, aurora over a quiet fjord"
cass image --quality high "marketing cover art: launch banner for Cassandra Routines"
```

## Editing

```bash
cass image --edit ~/Downloads/photo.jpg "remove the background, keep only the subject"
cass image -e ./logo.png -q high "redraw this in a flat vector style with warmer colors"
```

Edited output lands next to the source as `<name>-edited-<ts>.png` unless `--out` is given.

## Prerequisites

`cass` must be on PATH and the user must have run `codex login` with a ChatGPT Plus/Pro account (not an API key). The `cass-cli` plugin in this same marketplace installs the binary.

## Failure modes

- **"No Codex login found"** — the user hasn't run `codex login` yet. Tell them to run it and re-try.
- **"auth_mode is 'apikey'; need 'chatgpt'"** — they're logged in with an API key; ChatGPT subscription mode is required. Advise `codex logout && codex login`.
- **"Responses API HTTP 4xx"** — usually the ChatGPT session is stale; a fresh `codex login` fixes it.

## What not to do

- Do **not** suggest installing an MCP plugin — the image-gen MCP variant was removed in cass v0.6.28. `cass image` via Bash is the only supported surface.
- Do **not** call `codex` directly for image generation; `cass image` handles auth refresh, prompt hints, and defaults.
- Do **not** pass `--no-open` unless the user explicitly asks you to suppress the preview.
