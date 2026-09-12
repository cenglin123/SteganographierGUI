# Repository Guidelines

## Project Structure & Module Organization

`Steganographier.py` is the main Python entry point for both the Tkinter GUI and CLI. Runtime images, the empty password-file placeholder, and related resources live in `modules/`; bundled helpers are in `tools/` (`tools/legacy/` preserves retired runtime scripts that old installs may still reference); default MP4 covers are in `cover_video/`. Right-click integration is maintained in `context-menu/`. Packaging is defined by `SteganographierGUI.spec` and `installer/SteganographierGUI.iss`. Release automation belongs in `scripts/` and `.github/workflows/`, while operational documentation belongs in `docs/`.

## Deployment Rules (hard constraints)

- The git repository is the single source of truth for all build inputs. Local packaging folders are mirrors of published assets, never build inputs (see `docs/RELEASING.md`).
- Never copy files into a Windows installation directory by hand. An install must come from the official installer (which registers an uninstall entry) or from the portable ZIP mirror created by `scripts/sync-latest-release.ps1`. The legacy WinRAR-SFX drop method is deprecated: it leaves no uninstaller and caused version drift.
- `modules/PW.txt` inside an installed program directory is user data (a real password book), unlike the empty placeholder tracked in this repository. Upgrades and reinstalls must migrate it, never overwrite it with the placeholder. The same applies to `config.json` and `logs/`.
- Historical tags are immutable: never delete, move, force-push, or retag existing release tags, even inconsistent ones such as v1.3.8/v1.3.9 pointing at one commit. Document known-dirty facts instead of repairing them.

## Build, Test, and Development Commands

Create a virtual environment, then install runtime dependencies:

```powershell
python -m venv .venv
.\.venv\Scripts\python -m pip install -r requirements.txt
```

Run `python Steganographier.py` for the GUI or `python Steganographier.py --help` for CLI options. Before submitting changes, run:

```powershell
.\scripts\validate-release.ps1
.\scripts\build-release.ps1
```

The first command validates source and bundled assets. The second builds and smoke-tests the portable package; add `-BuildInstaller` when Inno Setup 6 is installed.

## Coding Style & Naming Conventions

Use four-space indentation in Python and PowerShell. Keep Python functions and variables in `snake_case`, classes in `PascalCase`, and constants in `UPPER_SNAKE_CASE`. Prefer `pathlib` or `os.path` over manually joined paths. PowerShell scripts should use approved verbs, `$ErrorActionPreference = "Stop"`, and explicit parameter names. Preserve UTF-8 for Chinese text and filenames. No formatter is enforced, so keep edits focused and match surrounding style.

## Testing Guidelines

The project currently uses validation and smoke-test scripts rather than a unit-test framework. Run `python -m py_compile Steganographier.py`, the release validator, and a package build. Changes to packaging must verify the executable reports the expected `VERSION` and that required DLLs, tools, modules, and cover videos remain present.

## Commit & Pull Request Guidelines

Git history uses short, imperative summaries, for example `Remove duplicate extraction instructions in README`. Keep each commit scoped to one concern. Pull requests should explain the behavior change, list verification commands, and link related issues. Include screenshots for visible GUI changes. Never commit passwords, tokens, generated `build/`, `dist/`, or `artifacts/` contents.

## Release Process

Update `VERSION`, commit, and push a matching tag such as `v1.4.0`. GitHub Actions builds the portable ZIP and installer, verifies checksums, and publishes the Release after approval in the `release` environment. See `docs/RELEASING.md` for the full checklist.
