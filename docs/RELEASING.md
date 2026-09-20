# Release Process

GitHub Actions builds the Windows portable archive and installer from a version tag. Local packaging folders are mirrors of published assets, not build inputs.

## One-time repository setup

1. In **Settings → Environments**, create an environment named `release`.
2. Add the maintainer as a required reviewer and restrict deployment tags to `v*`.
3. Protect `.github/workflows/**`, `scripts/**`, `installer/**`, `VERSION`, and the spec file with `CODEOWNERS` review.

## Publish a version

1. Update `VERSION` using `x.y.z` format and merge the change into `main`.
2. Run `python Steganographier.py --version` and `pwsh scripts/validate-release.ps1`.
3. Create and push the matching annotated tag:

   ```powershell
   git tag -a v1.4.0 -m "Release v1.4.0"
   git push origin v1.4.0
   ```

4. Review the build job, then approve the waiting `release` environment job.

The workflow refuses mismatched tags and versions, verifies the packaged executable and required runtime files, and publishes a portable ZIP, an Inno Setup installer, and `SHA256SUMS.txt`. To retry a failed build for an existing unpublished tag, run the Release workflow manually and supply that tag.

Release notes are generated from the commit history, so anything the generated list cannot express — why a previous version must not be used, what a defect actually was — has to be written down. Put that text in `.github/release-notes/<tag>.md` and the publish job prepends it to the generated notes. The file is named after the version deliberately: one shared preamble would keep repeating the previous release's warning until somebody remembered to clear it, whereas a tag without such a file simply publishes the generated notes alone. The file is read from the tagged commit, so it must be committed before the tag is pushed.

## Mirror a release locally

Run the following from Task Scheduler or a trusted local shell:

```powershell
pwsh scripts/sync-latest-release.ps1 -DestinationRoot "<distribution-root>"
```

The sync script downloads the latest public Release into `releases\vX.Y.Z`, verifies every supplied SHA-256 checksum, and writes the active tag to `CURRENT`. It never builds from or overwrites arbitrary files in the distribution root.

Constraints of the mirror track: it only mirrors the *latest* public Release (the script pins `/releases/latest`), and it hard-fails when that Release lacks `SHA256SUMS.txt` — true for every release before v1.3.10. Do not hand-fill historical versions into the mirror tree; retrieve them from local archives instead and label them as unverified.

## Upgrading a machine installed by the legacy SFX method

Installs dropped by the old WinRAR-SFX flow have no uninstall entry and mix runtime user data into the program directory. Before replacing such an install:

1. Snapshot the whole program directory (copy + SHA-256 manifest) outside the drive the new install targets.
2. Preserve the three runtime-only items that must survive the upgrade: `modules\PW.txt` (real password book — the installer ships the empty placeholder and would overwrite it), `config.json`, and `logs\`.
3. Rename the old directory aside (do not delete it yet), run the official installer fresh, restore the preserved items into `{app}`, then verify context-menu entries and shortcuts point at the new executable name (`SteganographierGUI.exe`, capital I).
4. Remove the renamed old directory only after the new install passes a smoke check.

## Known historical inconsistencies (do not "fix")

- Tags `v1.3.8` and `v1.3.9` are lightweight tags on the same commit (`b307541`); their trees predate VERSION/scripts/CI, so re-publishing either tag cannot succeed. Leave them alone.
- The `v1.3.8` Release carries three manually uploaded variants (`.0`/`.1`/`.2`); the `v1.3.9` Release carries an asset named `..._v1.3.8_portable.zip`. Only v1.3.10+ has `SHA256SUMS.txt`.
- Never move, delete, or force-push existing release tags. New facts belong in `CHANGELOG.md`.

## Tag hygiene (enforced)

`scripts/validate-release.ps1 -Tag <tag>` asserts that a release tag is annotated (`git cat-file -t` must report `tag`) and that `VERSION` exists inside the tagged tree and matches the tag name. Lightweight tags — all those before v1.3.10 — are grandfathered legacy; every new tag must be created with `git tag -a`.
