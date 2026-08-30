# Multi-agent Profiles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add shared Antigravity (`agy` + GUI) and Codex profile management without changing existing Claude behavior.

**Architecture:** A new provider-neutral sourceable layer owns provider namespaces, defaults, active session selections, copy snapshots, and launch adapters. Antigravity CLI and GUI share one namespace but use separate child data roots; Codex maps directly to `CODEX_HOME`. Existing Claude scripts remain the compatibility surface for Claude.

**Tech Stack:** POSIX `sh`, PowerShell 5.1+/Core, Windows cmd, shell test harness, shellcheck/checkbashisms when installed.

**Spec:** `docs/superpowers/specs/2026-08-30-multi-agent-profiles-design.md`

## Global Constraints

- Preserve the existing `claude-profile` command and Claude profile directory layout.
- Profile names must match `[A-Za-z0-9_-]+`; reject empty, dot-prefixed, slash, backslash, and `..` values.
- Never mutate the caller's `HOME`, `USERPROFILE`, `CODEX_HOME`, or GUI data directory.
- Copy must refuse an existing destination unless `--force` is supplied.
- Antigravity CLI and GUI must share the `antigravity` provider namespace.

---

### Task 1: POSIX provider core and test harness

**Files:**
- Create: `agent-profile.sh`
- Create: `tests/test-agent-profile.sh`

**Interfaces:**
- `agent-profile <provider> <command> [args]`
- `agy`, `antigravity`, `antigravity-ide`, and `codex` shell wrappers
- `agy-profile`, `antigravity-profile`, and `codex-profile` manager aliases

- [x] **Step 1: Write failing tests** for provider validation, live/default copy, no-overwrite, default/active resolution, and child environment/GUI flag behavior.
- [x] **Step 2: Run `bash tests/test-agent-profile.sh` and verify it fails because `agent-profile.sh` is missing.**
- [x] **Step 3: Implement the minimal POSIX provider adapter, safe copy helper, manager commands, and wrappers.**
- [x] **Step 4: Run the focused test harness and verify all cases pass.**
- [x] **Step 5: Run `sh -n agent-profile.sh tests/test-agent-profile.sh`, then run the harness in bash/zsh and refactor only while tests remain green.**

### Task 2: PowerShell provider layer

**Files:**
- Create: `agent-profile-init.ps1`
- Create: `tests/Test-AgentProfile.ps1`

**Interfaces:**
- Same provider and command names as Task 1.
- Child processes receive `HOME`/`USERPROFILE`, `CODEX_HOME`, and GUI
  `--user-data-dir` overrides only through `ProcessStartInfo` environment and
  argument construction.

- [x] **Step 1: Write failing Pester-free assertions in `tests/Test-AgentProfile.ps1`.**
- [x] **Step 2: Run the test script and verify it fails on missing functions.**
- [x] **Step 3: Implement the PowerShell provider core and wrappers.**
- [x] **Step 4: Run the test script under `pwsh`/Windows PowerShell when available and verify it passes.** (No PowerShell runtime is available in this environment; the test remains ready for Windows/PowerShell CI.)

### Task 3: Windows cmd manager and launcher shims

**Files:**
- Create: `agent-profile.cmd`
- Create: `agy.cmd`
- Create: `antigravity.cmd`
- Create: `antigravity-ide.cmd`
- Create: `codex.cmd`

- [x] **Step 1: Add command-dispatch and profile validation tests to the portable test notes.**
- [x] **Step 2: Implement `agent-profile.cmd` with `list`, `default`, `use`, `which`, `copy`, and `delete`.**
- [x] **Step 3: Implement launcher shims that locate the real executable, inject provider-specific profile overrides, and preserve explicit GUI data-dir flags.**
- [x] **Step 4: Run static checks and, on Windows, execute fake-executable smoke tests.** (Windows execution is unavailable here; static review is complete.)

### Task 4: Installers and documentation

**Files:**
- Modify: `install.sh`
- Modify: `install.ps1`
- Modify: `README.md`
- Modify: `CLAUDE.md`
- Modify: `docs/llms.txt`
- Modify: `docs/llms-full.txt`

- [x] **Step 1: Update POSIX and PowerShell installers to install/source the new provider layer idempotently.**
- [x] **Step 2: Document storage, commands, live/default copy, keyring limitation, GUI executable override, and Codex usage.**
- [x] **Step 3: Run documentation link/format checks available in the repository.** (`git diff --check`.)

### Task 5: Verification and final review

**Files:**
- Review: all changed files

- [x] **Step 1: Run the complete POSIX tests and static checks.**
- [x] **Step 2: Run PowerShell/cmd checks when interpreters are available.** (Neither interpreter is available in this environment.)
- [x] **Step 3: Re-read the spec and verify every requirement against tests or commands.**
- [x] **Step 4: Inspect `git diff --check`, `git status`, and the final diff for secrets, accidental Claude changes, or unsafe deletion.**

## Verification notes

- `bash tests/test-agent-profile.sh`: 6 passed, 0 failed.
- `zsh tests/test-agent-profile.sh`: 6 passed, 0 failed.
- `bash -n`, `zsh -n`, `sh -n`, and `git diff --check` pass for the available files.
- `pwsh`, Windows PowerShell, and `cmd.exe` are not available on the development host, so their runtime checks must be performed on Windows.

### Task 6: Native Fish adapters

**Files:**
- Create: `claude-profile.fish`
- Create: `agent-profile.fish`
- Create: `tests/test-fish-profile.fish`
- Modify: `install.sh`, `README.md`, `CLAUDE.md`, `docs/llms.txt`,
  `docs/llms-full.txt`, `docs/index.html`, `scripts/make-release-checksums.sh`

- [x] Add native Fish wrappers for Claude, Antigravity CLI/GUI, and Codex.
- [x] Preserve the shared on-disk layout and Fish session semantics, including
  directory-local Claude profiles and launcher environment isolation.
- [x] Install/source both Fish adapters and include them in release checksums.
- [x] Add a no-config Fish smoke harness covering wrappers, live snapshots,
  GUI launcher detection, Codex, and directory-local switching.
