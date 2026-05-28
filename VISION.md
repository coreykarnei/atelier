# Atelier

## What it is

A single-window, native macOS workspace for agent-assisted coding. An editor, a shell, and Claude Code live side-by-side in one app that owns its chrome, keyboard, clipboard, and notifications — instead of four layers (terminal + multiplexer + editor + agent) negotiating through escape sequences.

The shape — editor top-left, shell bottom-left, agent on the right — is preserved from the current `ide` setup. The composition is the same; the substrate is native.

## Why it exists

The current setup (Ghostty + tmux + Helix + Claude Code) works because terminals compose. It also breaks in small ways constantly, all for the same reason: too many processes are pretending to be each other.

- Selecting a paragraph in the agent pane returns soft-wrapped fragments with the agent's gutter indent on every line, because the multiplexer stores a grid and not wrap intent.
- Cmd-arrow is translated into escape sequences in the terminal config so the editor sees what it expects, because the editor doesn't know it's inside a GUI.
- "The agent finished" is plumbed through `afplay`, a terminal bell, a multiplexer status flag, and a window-attention indicator, because the agent can't talk to the OS directly.
- The editor itself — Helix — is fast and modal-pure, but is the wrong editor. The muscle memory I actually want is VSCode-shaped: select-and-type, multi-cursor, repo-wide search, a fuzzy file picker on a single chord.

Each quirk is small. Together they form a tax on every session. Atelier exists to pay it once, in code, instead of forever, in friction.

## Who it's for

Me, first. The shape of the tool is derived from how I work, not from a hypothetical user.

It is also a portfolio artifact. The job search targets agentic-systems and developer-tools roles — Anthropic's Agent Platform, Claude Code, agent skills, or a comparable startup. A polished, native client for agent-assisted coding is *the* on-target demonstration of that work. Atelier should look the part: a public repo, a real README, a screenshot that sells it.

These two audiences don't conflict as long as Atelier stays opinionated. A daily driver another engineer can read is worth more than a generic tool nobody uses.

## Principles

What the current setup gets right and Atelier must preserve:

- **One window, fixed shape.** The layout is the IDE. Editor, shell, agent — visible at once, no tab-shuffling.
- **Keyboard-first.** A pointer is an option, not a requirement. Pane focus, file picker, search, command palette — all reachable from the home row.
- **Worktree as a first-class concept.** Spawning an isolated workspace for a branch is one action. Listing them, returning to them, tearing them down — visible and one click each.
- **Catppuccin Mocha, transparent, native blur.** The aesthetic is a real constraint, not decoration. It signals "terminal-native, deliberately built," and I want it back exactly.
- **Notifications go to the OS.** When the agent needs me, a real notification. When it finishes, a real signal. The work the bell hack does today, the app does natively.

What it adds that the current setup can't:

- **A VSCode-shaped editor.** Insert-mode default, drag-select, multi-cursor, repo-wide search with a results panel, fuzzy file picker on a single chord. Not a VSCode clone — an editor that doesn't fight common editing instincts.
- **Truthful copy.** Selecting from any pane returns the text that's there. Paragraphs are paragraphs; tables are tables; the agent's gutter indent is not silently included.
- **One clipboard, one selection model.** No copy-mode-vs-mouse-vs-system layering.
- **A session that survives a restart.** Reopen the workspace and the repo, worktrees, and panes are where I left them.

## What it is not

- **Not a Claude Code replacement.** Claude Code runs inside Atelier as a process. The agent loop, its tools, its skills are unchanged. Atelier is its host, not its substitute.
- **Not a general multiplexer.** It manages exactly the panes the IDE shape requires. No arbitrary splits, no window manager.
- **Not a general-purpose IDE.** No language-specific build runners, no plugin marketplace, no settings UI for every preference. Scope is: code, shell, agent, side by side, gracefully.
- **Not cross-platform on day one.** macOS-first because that's what I run. Linux is plausible later; Windows is not the point.

## What success looks like

A morning where I open Atelier on a fresh worktree, work for four hours, and never think about the tool. No escape-sequence hack, no double-copy to clean up an agent response, no shell-script branch dance, no "wait, which pane has focus." The friction tax is gone.

And a public repo where another engineer can open the README, see the screenshot, read the why, and want to either use it or talk to me about how it was built.
