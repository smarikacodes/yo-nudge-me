# yo-nudge-me

**Claude Code notifies you when it needs you when you're busy with other tasks.**

You ask Claude to do something, switch to your browser and five minutes later discover it's been sitting there waiting for you to approve a command or has already finished the task. yo-nudge-me fixes that with a notification sound the instant Claude Code needs approval and when it finishes a task and is waiting for your next message.


## Install

Inside Claude Code:

```
/plugin marketplace add smarikacodes/yo-nudge-me
/plugin install yo-nudge-me@yo-nudge-me
```

Start a new session. You'll hear one "Yahoo!" and a one-line hello. That's it.

## Commands

```
/yo list                       show sounds and what each event plays
/yo set approval <sound>       sound for "Claude needs your approval"
/yo set task_complete <sound>  sound for "Claude finished"
/yo preview <sound>            play a sound now
/yo test                       real test: run it, switch windows within 5 seconds
/yo on | off                   unmute / mute
/yo volume <0-100>             set volume (default 50)
```

Built-in sounds: mario's `letsgo`, `yahoo`, `pipe`, `powerup`.

## Add your own sounds

Drop a short `.wav` file into the folder shown by `/yo list` (it lives under `~/.claude/plugins/data/yo-nudge-me/sounds/`).

Tips: keep clips under 2 seconds, mono, 16-bit WAV. Filenames may use letters, digits, `-` and `_`.

## How it works

yo-nudge-me hooks into two moments: Claude asking for approval, and Claude finishing a task. Before playing a sound, it checks if you're already looking at that terminal or editor window — if you are, it stays quiet. If you're elsewhere (or it can't tell), it plays.

It also knows the difference between "waiting on you" and "just running in the background" — subagents, background tasks, and headless sessions (like summarizer tools) don't trigger sounds.

## Requirements

| OS | Focus detection | Sound | Notes |
|---|---|---|---|
| macOS | built-in (`osascript`) | built-in (`afplay`) | Nothing to install. |
| Windows | built-in (PowerShell) | built-in (PowerShell) | Needs **Git for Windows** (Git Bash), which Claude Code's hooks run through. Without it, yo-nudge-me stays silent and shows no errors. |
| Linux | `xdotool` (X11) | `paplay`, `pw-play`, `ffplay`, or `aplay` | Without `xdotool`, or on Wayland, sounds play every time. |