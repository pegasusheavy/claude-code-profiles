# Multi-agent Profiles — Design Spec

## Goal

Extend the existing cross-platform `claude-profile` project with profile
management for Antigravity CLI (`agy`), the Antigravity GUI, and Codex while
keeping existing Claude profiles and commands backward compatible.

## User-facing commands

The existing `claude-profile` command remains Claude-only. A new sourceable
`agent-profile` command provides the provider-neutral surface:

```text
agent-profile <provider> <command> [args]
agent-profile copy antigravity hafez
agent-profile copy antigravity default hafez
agent-profile default antigravity hafez
agent-profile use antigravity hafez
agent-profile list antigravity
agent-profile which antigravity hafez
agent-profile restart antigravity
```

`agy`, `antigravity`, `antigravity-ide`, and `codex` wrappers resolve the
active/default profile automatically. The target-specific manager aliases
`agy-profile`, `antigravity-profile`, and `codex-profile` are provided for
discoverability. `copy <provider> <name>` snapshots the current live profile
when no source is supplied; `copy <provider> default <name>` copies the
manager's persisted default profile. `restart antigravity` launches a fresh
GUI window with `--new-window` and the selected profile, without terminating
other GUI processes.

## Storage and provider adapters

Profiles are stored below `${AGENT_PROFILE_DATA_DIR}` (default
`${XDG_DATA_HOME:-$HOME/.local/share}/agent-profiles` on POSIX and
`%LOCALAPPDATA%\\agent-profiles` on Windows), partitioned by provider:

```text
agent-profiles/
├── antigravity/
│   ├── .default
│   └── <name>/
│       ├── home/.gemini/                 # agy CLI home-scoped data
│       └── gui-user-data/                # GUI --user-data-dir data
└── codex/
    ├── .default
    └── <name>/                           # CODEX_HOME contents
```

The Antigravity CLI has no documented home override, so the wrapper launches
`agy` with a profile-specific `HOME` (and `USERPROFILE` on Windows). The GUI
is launched with `--user-data-dir <profile>/gui-user-data`; an explicit
`--user-data-dir` supplied by the user is respected. GUI executable discovery
tries `antigravity-ide` and then `antigravity`, with
`AGENT_PROFILE_ANTIGRAVITY_GUI_COMMAND` as an override.

The Antigravity profile snapshot copies the current `$HOME/.gemini` tree and
the detected GUI user-data directory. OS keyring entries are not copied or
altered; the command reports that filesystem-backed credentials/settings were
copied and that keyring-backed authentication may remain shared.

Codex launches with `CODEX_HOME=<profile>` and snapshots the current
`$CODEX_HOME` (or `$HOME/.codex`) directory. `OPENAI_API_KEY` and other
explicit environment credentials are passed through unchanged.

## Safety and compatibility

- Profile names use the existing `[A-Za-z0-9_-]+` validation and reject
  traversal, dot-prefixed names, and empty values.
- Copy refuses to overwrite an existing destination unless `--force` is
  supplied; `--force` replaces only the destination profile after the source
  has been validated.
- Copy uses a temporary sibling directory followed by an atomic rename where
  possible, so an interrupted copy cannot leave a partially usable profile.
- Wrappers never mutate the caller's `HOME`, `USERPROFILE`, `CODEX_HOME`, or
  GUI data directory; overrides exist only in the launched child process.
- The existing Claude scripts and profile storage remain untouched.

## Cross-platform surface

`agent-profile.sh` is strict POSIX sh and is sourceable in bash, zsh, and
other supported POSIX shells. `agent-profile.fish` is a native Fish adapter
sourceable from `config.fish`. `agent-profile-init.ps1` is dot-sourceable in
PowerShell 5.1+ and PowerShell Core. `agent-profile.cmd` and target launcher
shims provide the same manager and launch behavior on cmd.exe, where caller
environment changes require `call` and transparent function wrappers are not
available.

## Testing

The POSIX implementation is covered by a dependency-free shell test harness
using temporary HOME/XDG directories and fake `agy`, GUI, and `codex`
executables. Tests cover name validation, copy-from-live, copy-from-default,
no-overwrite behavior, default/active resolution, environment isolation, and
GUI flag injection. The Fish adapter has a separate native smoke harness that
also covers Claude's wrapper, Codex, GUI launcher detection, and
directory-local switching. Static checks cover shell syntax and shellcheck
when available; PowerShell and cmd files receive parser/static checks when
their interpreters are available.
