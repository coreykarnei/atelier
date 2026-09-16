# Releasing Atelier

This is the maintainer checklist for a public source release and, separately,
a downloadable macOS app. A version tag records a source snapshot; it does not
by itself publish a GitHub release or produce an installable distribution.

## Repository readiness

- Confirm the root MIT license and copyright attribution. Preserve vendored license and attribution
  notices and review the notices needed for a binary distribution.
- Confirm the public repository URL and configure the Git remote. Update
  README installation links when the public destination is available.
- Add a current workspace screenshot using a sample project with no private data.
- Establish a private security-reporting route, such as GitHub private
  vulnerability reporting, before publishing a SECURITY.md that points to it.
- Review tracked files and history for credentials, personal configuration,
  and material that should not be published. This documentation pass is not
  a secrets or dependency-license audit.
- Verify setup from a clean checkout or separate macOS account. Check the
  notification example, Claude discovery, resource bundles, and optional CLI.
- Consider a macOS CI build once the supported toolchain is pinned. Do not add
  a passing-build badge until a workflow actually exists and passes.

## Release verification

Build an optimized bundle with `make bundle CONFIG=release`. Check launching,
opening a project, editing and saving, session creation, worktree creation and
removal, notification routing, and quit/relaunch restoration. Exercise remote
reconnection if remote sessions are included in the release claims.

Record the macOS versions and architectures actually tested, known limitations,
and any state migrations. Check the app's About version against
`Resources/Info.plist`. Keep the marketing version and build identifier deliberate.

## Distributing an app

The current bundle script provides local development signing. A public app
should have a separate distribution process that:

1. Builds the supported architectures and includes resources and helper binaries.
2. Signs all required code with Developer ID and the appropriate hardened
   runtime settings and entitlements.
3. Submits the artifact to Apple's notary service and checks the result.
4. Staples the ticket to the supported app or disk-image artifact, then packages
   the final download as a ZIP or DMG.
5. Tests the downloaded artifact through Gatekeeper on a separate Mac or account.
6. Publishes the artifact, its checksum, installation steps, and requirements.

See Apple's [Developer ID guidance](https://developer.apple.com/developer-id/).
A locally trusted self-signed certificate is not a replacement for this process.

## Tag and publish

The local `v1.0.0` tag already exists. Confirm which commit it identifies before
publishing: documentation changes made later on `main` are not in that snapshot.
Do not move an already published tag; use a follow-up version for changes.

Prepare release notes covering what the app does, requirements, installation,
known limitations, and where to report problems. Create a draft GitHub release
at the intended tag and attach any verified app artifacts. Review the draft,
then publish it. GitHub's automatically generated source archives are not app
installers.

After publication, download and test the published artifact, check README
links, and keep subsequent fixes in new versions. See
[GitHub's release documentation](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases).
