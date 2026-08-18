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

## Mirror a release locally

Run the following from Task Scheduler or a trusted local shell:

```powershell
pwsh scripts/sync-latest-release.ps1 -DestinationRoot "<distribution-root>"
```

The sync script downloads the latest public Release into `releases\vX.Y.Z`, verifies every supplied SHA-256 checksum, and writes the active tag to `CURRENT`. It never builds from or overwrites arbitrary files in the distribution root.
