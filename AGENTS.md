# Agent Notes

## Product Scope

Close Your Laptop is a battery-first macOS menu-bar helper. Its job is to let Claude or Codex continue active project work while the laptop lid is closed, then release sleep assertions as soon as that work is done so the computer can sleep and preserve battery.

Do not steer the product toward an AC-power-only clamshell workflow. Being plugged in may make macOS sleep prevention easier, but it is not the point of this app.

## Detection Rules

- Treat Claude/Codex CLI sessions as active while their agent process exists.
- Treat Claude Desktop and Codex Desktop GUI sessions as active only when their app process tree shows recent measurable CPU activity.
- For GUI CPU checks, ignore Electron infrastructure and housekeeping such as renderers, GPU helpers, utility helpers, crashpad, `codex_chronicle`, idle `node_repl` processes, and MCP server commands ending in ` mcp`.
- Once GUI work has been positively detected, allow a bounded quiet window for wake revalidation, network waits, and tool handoffs. Do not use that quiet window to resurrect a GUI app that was never observed doing work.
- Do not treat a parked GUI session, renderer, app server, local agent, updater, or helper process as active just because it exists.
- Prefer false negatives over false positives for GUI idleness; battery drain from holding sleep too long is the primary failure mode.

## Power Behavior

- Hold native IOKit sleep assertions only while active Claude/Codex work is detected, plus the short release grace period.
- Ordinary IOKit assertions do not reliably prevent battery clamshell sleep. After one administrator approval, keep a tiny privileged watchdog alive for the app run; it should arm the temporary `pmset disablesleep` closed-lid override only during active work and disarm it when work stops. Keep the root watchdog/heartbeat safety path intact so a crash restores normal sleep.
- Release assertions promptly when work stops.
- After wake, reset CPU measurement history and keep any pre-sleep assertion alive briefly while revalidating activity. Sleep time must not consume the release grace window or cause a false `Sleep OK`.
- Keep the app small, quiet, and low-overhead: native process APIs, sparse polling, no Accessibility permission for normal detection, no shelling out in the monitor loop. Privileged `pmset` work belongs in the already-approved watchdog, not repeated AppleScript authorization prompts.
- Keep diagnostics sparse and useful. Unified-log events should cover activity transitions, assertion acquire/release, and sleep/wake notifications so closed-lid battery tests can be audited after wake.

## Update Behavior

- Sparkle is the app's update mechanism. Use a GitHub-hosted appcast and signed release archive; do not replace it with manual download links.
- Do not add a visible "Check for Updates" menu item or settings control. Updates should be automatic background checks with Sparkle's prompt when a newer version is found.
- Keep `CFBundleVersion` monotonic and set `CFBundleShortVersionString` for the user-facing version. Sparkle compares appcast `sparkle:version` against `CFBundleVersion`.
- The hidden CLI/debug surface may expose update diagnostics, signing-tool paths, appcast checks, and appcast template generation. Keep that surface out of user-facing menu/UI copy.
- Publish brief release summaries in the appcast item description or release notes link so Sparkle's prompt explains the change.
