# Contributing to Atelier

Atelier is a personal macOS workspace with a focused design. Bug reports,
clearer documentation, accessibility improvements, and small, well-explained
fixes are welcome. Larger features should start with a discussion of the
problem and how they fit the existing workflow.

Read [the vision](VISION.md) for the project's scope. The fixed workspace,
keyboard-first interactions, and native macOS behavior are deliberate choices.

## Report a problem

Include the Atelier version or commit, macOS version, Mac architecture, and
whether you built a debug or release bundle. Describe the steps to reproduce,
what you expected, and what happened. For agent issues, include the Claude Code
version; for remote issues, include the relevant host tools and versions.

A small sample file or a screenshot often helps. Remove credentials, private
paths, hostnames, and conversation content from anything you attach. Please
keep discussion specific and respectful.

## Work on a change

Follow [the setup guide](docs/SETUP.md), create a branch, and keep the change
focused on one problem. Describe the resulting behavior and why it helps.
For visual changes, include before/after screenshots and check narrow windows,
long labels, empty states, and keyboard interaction where relevant.

Run `swift build` and `git diff --check`, then exercise the affected behavior
in the bundled app. The root package currently has no test target; a successful
build is not a substitute for checking the interaction. Explain what you
verified and what you could not exercise. Documentation-only changes need
link, command, and example checks rather than an app rebuild.

Highlight-query changes have a dedicated
[verification harness](Scripts/hlcheck/README.md). Run it against representative
fixtures for the languages you change.

## Where changes belong

| Path | Purpose |
| --- | --- |
| `Sources/Atelier` | AppKit application and workspace |
| `Sources/AtelierIPC` | Shared socket and message contract |
| `Sources/atelier-notify` | Claude notification-hook helper |
| `Sources/atelier-cli` | Workspace command-line tool |
| `Sources/atelier-hlcheck` | Syntax-query verification tool |
| `Vendor` | Patched terminal and editor dependencies |

Terminal behavior belongs in the vendored SwiftTerm package; editor-library
behavior belongs in the relevant CodeEdit package. Record dependency patches
in that package's `ATELIER.md` and preserve its license notices. Use the
existing [design rules](docs/POLISH_PLAN.md) for interface changes.

Maintainer time is limited. A proposal may be outside the project's scope even
when the implementation is good; discussing larger changes early helps.
