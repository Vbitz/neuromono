# Native ARM64 Neurodesktop candidate

`.github/workflows/neurodesktop-arm64-candidate.yml` is a manual-only Neuromono
workflow. It builds the standard `neurodesktop/Dockerfile` at the gitlink pinned
by the selected Neuromono commit. It never follows upstream main during the job,
uses a derived Glass image, or substitutes a published Neurodesktop image.
Neuromono tracks `Vbitz/neurodesktop`, branch `main`. To adopt newer upstream
source, first synchronize the fork's `main` with `neurodesk/neurodesktop/main`
using a fast-forward when possible; preserve and review any divergent fork
commits rather than force-resetting them. Then update and commit Neuromono's
submodule pin. Keep the submodule URL pointing to the fork.

## Build and download

The workflow must first be present on the repository's default branch. Select
**Actions → Neurodesktop ARM64 candidate → Run workflow**, or from this checkout:

```sh
gh workflow run neurodesktop-arm64-candidate.yml --repo Vbitz/neuromono --ref main
gh run list --repo Vbitz/neuromono --workflow neurodesktop-arm64-candidate.yml
# Select the run you just dispatched; inspect its head SHA before downloading.
gh run view RUN_ID --repo Vbitz/neuromono
gh run watch RUN_ID --repo Vbitz/neuromono --exit-status
mkdir -p artifacts/neurodesktop-RUN_ID
gh run download RUN_ID --repo Vbitz/neuromono --name neurodesktop-arm64-RUN_ID-ATTEMPT --dir artifacts/neurodesktop-RUN_ID
```

The job needs access to the native `ubuntu-24.04-arm` runner, sufficient Actions
minutes, disk and artifact storage. It uses only `contents: read` and checks out
only the public Neurodesktop submodule, so it does not require credentials for
other private submodules. No registry credentials or package publication are
needed. The large image artifact expires after three days; download it promptly.
If runner or storage policy blocks execution, fix that prerequisite rather than
substituting another image. Building and archiving this full image is disk-heavy.

Before upload, the job verifies the Buildx image ID and Linux/ARM64 architecture,
scans CRITICAL vulnerabilities using the pinned source's exception policy, then
runs the upstream Slurm, regular/no-CVMFS/package-only-sudo, and HPC checks on
that exact image ID. A failing check prevents image upload. Check failure details
in the Actions logs and the separate `neurodesktop-diagnostics-RUN_ID-ATTEMPT`
artifact. Diagnostics are retained even when scanning fails; they contain no
image archive and do not establish acceptance. Cleanup restores the temporary
user-namespace setting.

## Import without Docker Desktop

On macOS, in the downloaded artifact directory:

```sh
shasum -a 256 -c SHA256SUMS
cat provenance.json
# Compare both source commits to the selected run and Neuromono gitlink.
gunzip -k neurodesktop-arm64.tar.gz
```

The manifest records both commits, image config ID, platform, run ID/attempt and
completed checks. `SHA256SUMS` protects transfer integrity; it is not a signature
or a reproducible-build claim. The Dockerfile can still fetch upstream build
inputs. Keep the original compressed file for checksum verification.

CrumbleCracker imports the **uncompressed** Docker archive directly, without a
Docker daemon or registry login. Supply an absolute path:

```python
crumblecracker.smoke(
    image="docker-archive:/absolute/path/neurodesktop-arm64.tar",
    cache_dir="build/neurodesktop-candidate-RUN_ID/cache",
    storage="build/neurodesktop-candidate-RUN_ID/shared",
)
```

This uses fresh development paths, not the user's existing sessions or storage.
The smoke check covers guest boot/commands and shared-folder persistence across
restarts; it does not establish Glass display, clipboard, resizing, GPU or native
GUI acceptance. Those remain separate tests of NeurodeskAppX with the same
archive. The workflow also does not establish live CVMFS/scientific acceptance.
Do not change the application default image based only on these container checks.

Large image archives must be downloaded to the native peer (for example with
`gh run download`), not routed through the small browser-file or SCS download
limits. No `docker load` step is required for CrumbleCracker.
