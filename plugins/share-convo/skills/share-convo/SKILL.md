---
name: share-convo
description: Share the current Claude Code conversation as an ephemeral URL via `cass share create`. Sanitizes the session JSONL locally, uploads markdown to cassandra-share, returns a short-lived link, and copies a ready-to-paste message to the clipboard. Use whenever the user says "/share-convo", "share this convo", "teleport this session", "send this to <name>", or "turn this into a link I can paste into ChatGPT/another LLM".
argument-hint: "[--ttl 24h] [--once] [--title \"..\"] [--summary \"..\"]"
---

# Share the current Claude Code conversation

`cass share create` turns the current session into sanitized markdown, posts it to the `cassandra-share` service, and prints a clipboard-ready blurb containing:

```
Continue this Claude convo (expires in 24h):
curl -sSL 'https://share.cassandrasedge.com/s/<token>'

About: <2-3 line summary>
```

The link is URL-gated (128-bit random token) and expires by default in 24h. Anyone with the URL can `curl` it — no receiver-side auth required. On a Mac the blurb is auto-copied to the clipboard via `pbcopy`.

## When to use

Invoke via the Bash tool whenever the user says any of:

- `/share-convo`
- "share this convo" / "share the conversation"
- "teleport this session"
- "send this to <person>"
- "make a link I can paste into ChatGPT / Gemini / another LLM"
- "copy this chat"

## Basic usage

```bash
cass share create
```

Resolves the current session automatically via `$CLAUDE_SESSION_ID` (or the newest `.jsonl` under `~/.claude/projects/<cwd-hash>/` if the env var isn't set), sanitizes it, posts to `cassandra-share`, prints + copies the clipboard blurb.

## Flags

| Flag | Purpose |
|---|---|
| `--ttl 24h` | Expiry. Use `6h`, `24h`, `7d`, etc. Default 24h, max 7d. |
| `--once` | Self-destruct after first fetch. Good for one-time handoff. |
| `--title "…"` | Optional human title, shown in `cass share list`. |
| `--summary "…"` | Override the auto-generated "About:" blurb. 2-3 sentences. |
| `--no-copy` | Don't copy to clipboard (just print). |

## Recommended defaults

- For casual handoff: no flags. 24h TTL, no single-use, auto summary.
- For stock analysis / "send to a friend on DMs": add `--once` so the link dies after they open it.
- For time-sensitive handoffs: `--ttl 6h`.
- When the sender already knows what they want the summary to say: pass `--summary "…"` to skip the auto-generated one.

## Related commands

- `cass share list` — list the current user's active shares.
- `cass share revoke <token>` — kill a share early.

## What gets sanitized

`cass share create` runs a regex pass before upload that replaces:

- OpenAI (`sk-…`), GitHub (`ghp_…`), AWS (`AKIA…`), Google (`AIza…`), Stripe (`sk_live_…`) keys
- PEM private-key blocks (`-----BEGIN …PRIVATE KEY-----`)
- JWTs
- Absolute home paths (`/Users/<name>/…` → `<HOME>`)
- Private IPs (`10.x.x.x`, `172.x.x.x`, `192.168.x.x` patterns → `<INTERNAL_IP>`)

This is a safety net, not a guarantee. If the user mentions a secret in free text ("my password is hunter2") a regex won't catch it — flag this to the user if their session contains sensitive prose and suggest they review the generated markdown before relying on it.

## Receiver side

The receiver pastes the clipboard blurb into their Claude Code session. Their Claude sees the `curl` instruction, runs it via Bash, and gets back the full sanitized markdown transcript to ingest. **No `cass` install needed on the receiver side** — just `curl` and their own Claude Code.

The markdown is also directly pasteable into ChatGPT, Gemini, Perplexity, etc. — any LLM chat UI — for analysis or continuation outside Claude.

## Failure modes

- **"Could not locate the current session .jsonl"** — Claude Code isn't set up on this machine, or the session hash dir doesn't match `$CWD`. Pass the path explicitly: `cass share create ~/.claude/projects/<dir>/<session>.jsonl`.
- **HTTP 401 from share service** — user needs `cass login`. Run it and retry.
- **HTTP 413** — session is too large (>5 MiB of markdown). Use `--title` to note the context, and suggest the user summarize or split before sharing.
- **`pbcopy` unavailable** — non-Mac platform. The blurb is still printed to stdout.

## What not to do

- Do NOT paste raw session JSONL content into Bash — always go through `cass share create`, which handles sanitization + upload.
- Do NOT use `cass share` for content containing real secrets the user doesn't want on Cassandra's infra — the service stores the markdown on a shared SQLite DB. The sanitizer is best-effort.
- Do NOT generate the clipboard message yourself — always shell out to `cass share create` so you inherit the auth/sanitize/upload flow correctly.
