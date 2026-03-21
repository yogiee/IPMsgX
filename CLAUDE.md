# IPMsgX — Claude Code Instructions

## Tools to Use

- **Swift LSP** — use LSP tools for Swift code navigation, symbol lookup, hover type info, and diagnostics when working on any Swift source file. Use before and after every edit.
- **Context7** — use the Context7 MCP plugin to look up up-to-date documentation for Swift, SwiftUI, AppKit, Foundation, and Apple frameworks before implementing features or fixing bugs. Especially required for any API with platform-version constraints or subtle overload behavior (e.g. `onKeyPress`, `sheet(item:)`, `AttributedString`, `AttributedString.MarkdownParsingOptions`).

## Git / GitHub Workflow

**Never commit, push, create PRs, or publish GitHub releases autonomously.**

Always stop and ask the user before:
- `git commit`
- `git push`
- `gh pr create` / `gh pr merge`
- `gh release create`
- Any version bump in `scripts/build-app.sh`

The expected flow for any change is:
1. Implement the change locally
2. Build (`swift build -c release`) to confirm it compiles
3. **Tell the user what's ready and wait for explicit approval** before touching git or GitHub

This ensures the user can test locally before anything is published.

## Build

Always use the build script for full app + DMG builds:

```bash
# Release build (produces build/IPMsgX.app + build/IPMsgX.dmg)
bash scripts/build-app.sh release

# Quick compile check (no app bundle)
swift build -c release
```

## Release Checklist (when explicitly asked)

1. Bump `VERSION` and `BUILD_NUMBER` in `scripts/build-app.sh`
2. Run `bash scripts/build-app.sh release` and confirm it succeeds
3. **Tell the user** — wait for them to test locally before proceeding
4. `git commit` → `git push` → `gh pr create` → `gh pr merge`
5. `gh release create vX.Y.Z build/IPMsgX.dmg`
6. Update memory with new version number

## GitHub Account

The repo (`yogiee/IPMsgX`) uses HTTPS with the `yogiee` credential helper account.
Before any `git push` or `gh` command, confirm the active account:
```bash
gh auth switch --user yogiee
```
