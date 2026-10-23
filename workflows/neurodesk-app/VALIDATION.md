# Native Jupyter-first acceptance — October 23, 2026

## Exact candidates

- App: `7e31e4c5f7dfc746e46d4a2b14e875b04ec8c379` (`crumblecracker-jupyter-first`).
- CrumbleCracker: `8dea4fe4cb81c41037aa19d648fd47c101dce0b4` (`jupyter-first-headless`).
- Neurodesktop: `433cddfa58ab6424adaa11e2f12616c93c192e0a` (`jupyter-first-glass`).
- Candidate workflow: `Vbitz/neuromono`, run `39907142801`, attempt 1.
- ARM64 image ID: `sha256:4e8145dabe525aa5df8229105fe24d3df15a98efd9790f4d66e161c1f77e43a7`.
- Uncompressed Docker archive SHA-256: `3afd3f65a992a847072b6cc26a87f9a08ae00f9edc0a5ada19ed034168b7f63d`.

The source-built candidate passed Slurm, installed-image/package-only sudo, and
foreign-UID/HPC checks before export. Downloaded SHA256SUMS were verified before
unpacking. The vulnerability scan reported findings and remained advisory for
this internal candidate; this is not a security-release approval. No published
image or runtime binary was substituted for the candidates under test.

## Native execution

On a logged-in Apple Silicon macOS peer, built/signed the local runtime and
compiled Electron app. Used an isolated profile, home/cache, working folder, and
storage under `neurodesk-app/build/cc-gpu-yAYHg8/`; CVMFS was disabled. The same
candidate cache/profile was reused between software and GPU runs to fit available
disk space. This is repeated-boot coverage, not a separate scientific-data
persistence acceptance test. Normal user profiles and storage were untouched.

The harness runs the real application/session/server classes and preload IPC:

1. Start Jupyter and check authenticated readiness. An unauthenticated request
   must fail with 401/403.
2. Verify Jupyter active, desktop service inactive, and no X11 socket.
3. Load real JupyterLab and its app-owned native Desktop launcher card.
4. GPU run: click the app's top-bar Desktop button to start the native window.
   Software run: click the Jupyter launcher to start it. Then click the other
   entry point to confirm it targets the existing VM/window.
5. Wait for actual native frame presentation, check X11 and `glxinfo -B`, allow
   desktop startup to settle, and reject uniform/black framebuffer captures.
6. Request owned-backend shutdown and wait for its process to exit.

| Mode | Result | Renderer | Acceleration |
| --- | --- | --- | --- |
| GPU enabled | PASS | `virgl (vmsh Darwin VirGL)` | `yes`, OpenGL 4.1 |
| GPU disabled | PASS | `llvmpipe (LLVM 21.1.8, 128 bits)` | `no` |

Both final desktop captures were visually inspected: Neurodesk wallpaper, panel,
and desktop icons are present. The desktop PNG is captured from the VM display
session after native presentation, not an operating-system screenshot of window
chrome. The Jupyter PNG shows the actual launcher card.

Evidence:
- `validation/darwin-arm64-gpu.json`
- `validation/darwin-arm64-software.json`
- `validation/darwin-arm64-gpu-desktop.png`
- `validation/darwin-arm64-software-desktop.png`
- `validation/darwin-arm64-jupyter.png`

## Issues found and resolved during acceptance

The initial import exhausted disk space. Removed only its failed isolated cache
and the previous candidate's redundant decompressed archive; retained the older
compressed archive and reports. Subsequent retries reused the isolated cache.
A backgrounded native window stalled Jupyter frontend rendering; the test now
keeps the display awake, foregrounds its window, and bounds asynchronous probes.
The first desktop capture was too early and black despite a valid virgl report.
Final acceptance additionally waits for desktop startup and nonuniform pixels.
One diagnostic retry was terminated after screenshot capture stalled; later
runs use bounded capture and completed graceful owned-process shutdown.

## Other checks and limitations

- App TypeScript/preload build: PASS.
- App Jest: 5 suites, 122 tests PASS.
- Scoped ESLint: no errors; existing protocol snake_case naming warnings remain.
- Edited workflow YAML and 21 Bash blocks: syntax checks PASS (not installer execution).
- CrumbleCracker full Go suite: PASS; signed native build: PASS.
- Neurodesktop full unit, code-quality, and codespell CI: PASS.
- Neurodesktop draft PR #2 had no review comments/reviews when inspected; its
  upstream-style image workflow stopped at the hard vulnerability scan. The
  parent internal-candidate workflow above completed with advisory scanning.

No Windows/Linux native GUI acceptance, installer installation/signing/notarization,
CVMFS acceptance, scientific GPU workloads, or performance benchmarks are claimed.
The accelerated windowless path is currently Apple Silicon only. Native sessions
require the Jupyter-first image changes; existing published image versions may
be incompatible. Use the candidate archive override described in the app's
`CRUMBLECRACKER.md` until a compatible image is explicitly released.
