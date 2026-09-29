---
name: yo
description: Manage yo-nudge-me notification sounds. Use when the user runs /yo with list, set, preview, test, on, off, or volume.
argument-hint: "[list | set <approval|task_complete> <sound> | preview <sound> | test | on | off | volume <0-100>]"
disable-model-invocation: true
allowed-tools: Bash(bash *)
---

Run exactly this one command with the Bash tool, then show the user its complete output verbatim inside a code block. Do not add commentary, do not run any other command, and do not edit any file.

```
CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}" CLAUDE_PLUGIN_DATA="${CLAUDE_PLUGIN_DATA}" bash "${CLAUDE_PLUGIN_ROOT}/scripts/yo.sh" $ARGUMENTS
```

If the command exits non-zero, still show its output verbatim; it already contains the explanation.
