# Neuromono Workflows

The runnable SA2 configuration is [AGENTS.star](AGENTS.star). Each repository
has a module namespace: `neurodesktop`, `neurocontainers_arm64`,
`neurocontainers_arm64.neurocontainers`, `neurocommand`, `neurodesk_app`, and
`crumblecracker`; `neuromono` owns the parent workspace. Unsupported operations
are commented beside their intended namespace. These are development commands
with native host authority; importing the configuration starts no workloads.

Build the updated SA2 executable, then run from this directory:

```sh
go -C ../sa2 build -o /tmp/neuromono-sa2 .
/tmp/neuromono-sa2 -script workflows/smoke.star
printf 'neurodesktop.git.status(check=True).stdout\n' | /tmp/neuromono-sa2 -script -
```

Script mode uses `default_repl` without starting a model turn. The smoke script
checks all repository workspaces and Git bindings, including the nested recipe
repository. It does not claim container, GUI, VM or scientific test coverage.

## Neurodesktop

The [manual ARM64 candidate workflow](workflows/neurodesktop/README.md) builds
the pinned Neurodesktop fork submodule in Neuromono Actions, validates the exact
image, and exports a checksummed Docker archive for direct CrumbleCracker import.
No local Docker Desktop or registry publication is required.

- Build a new image based on local changes.
- Run the image on arm64 Linux/macOS and amd64 Linux.
- Run unit tests and tests inside a locally built image.
- Open a browser and terminal into the running image.
- Collect logs and debug failed startup.

## Neurocontainers

- Open a new PR with recipe changes and monitor Actions results.
- Build a container locally and open a terminal to test it.
- Run individual test cases or the full test suite.
- Create a new recipe or update an existing version.
- Build and test on native ARM64.
- Download CI artifacts and reproduce a failed test locally.

## Neurocommand

- Install a new instance in a sandbox.
- Find, install, and run a container in the sandbox.
- Test with CVMFS enabled and disabled.
- Verify generated menus and module discovery.

## Neurodesk App

- Compile a new version.
- Test locally on Windows, macOS, and Linux.
- Run against a locally built Neurodesktop image.
- Test Docker, Podman, and TinyRange backends.
- Build and test platform installers.

## CrumbleCracker / NeurodeskAppX

- Build and launch both apps (SquadVM and NeurodeskAppX).
- Run headless VM smoke tests.
- Test shared folders and persistence across restarts.
- Test GPU and software rendering.

## Across repos

- Test a local change through the whole stack.
- Update submodule pins to verified versions.

## Implemented development paths

Neurodesktop provides `build`, `start`, `ready`, `test` and `test_image`. Image
handles retain exact IDs, and container handles provide logs, status, file copy,
user-selected execution, stop/start/restart and cleanup. The standard profile
explicitly grants a privileged root container and 1 GiB shared memory, as the
repository's existing test runner does. `privileged_mode=False` is available
when the selected test profile permits it. Tests requiring an HPC identity need
a separately configured profile. The default Jupyter port is an example; select
ports/environment appropriate to the image. Readiness checks an HTTP response,
not authenticated UI behavior. Keep a resource tracker to recover after errors.

The nested Neurocontainers module wraps locked uv setup, recipe initialization,
builds, builder tests, deploy smoke checks and local-candidate fulltests.
`fulltest` takes an explicit release metadata file and optional test configuration;
the caller must verify that metadata selects the intended local candidate.
Apptainer inspection/execution/shell descriptions use the recipe workspace.
The ARM64 parent wraps its existing prepare/build/test script and manual CI
dispatch. That script requires native Linux ARM64, Docker Buildx, Apptainer,
DataLad and git-annex; Apple Silicon alone does not satisfy its native Linux gate.
Actions must remain disabled in the recipe fork; dispatch the orchestration repo.

Each repository's `github` namespace supports PR creation/checks, run inspection,
watching, artifact listing and named artifact download. Download into an existing
dedicated directory. Match the run's source SHA, platform and image digest before
reproduction; a published artifact smoke test does not establish recipe fulltest
acceptance. Large artifacts remain host-local. Image handles support exact-image
tagging and archive saving; `neuromono.load_image` imports an archive. Cross-host
transfer/registry policy remains explicit. Browser downloads still cap files at
16 MiB and CAH storage at 1 GiB; these limits have not been raised.

Neurodesk App wraps locked Yarn setup, builds, Jest, native launch and installer
packaging. Its package metadata pins Yarn Classic 1.22.22 for the existing v1
lockfile. Install Node/Corepack and prepare that Yarn release on each host;
SA2's Yarn helper will not download a package manager implicitly.
Docker/Podman can use a candidate tagged
`vnmd/neurodesktop:<local-tag>` in the same engine and selected in app settings.
Native UI assertions, isolated app profiles, installer installation tests and
TinyRange local-image handoff remain commented. Packaging a Windows/Linux
installer on macOS does not prove it installs or runs on that OS.

CrumbleCracker wraps the existing two-app build, Go tests, native launches and
product smoke executable. The smoke helper signs the executable with the existing
hypervisor entitlements on macOS and uses separate development cache/shared paths.
It tests guest execution, shared writes and persistence across VM restarts.
Native window/GPU automation remains deferred. Neurocommand exports unit tests,
`build_test_image` and `acceptance`; its unit-test helper accepts `executor=` to
reuse a bound guest runner. See the acceptance procedure below.

## CVMFS sandbox integration

The public cc adapter and SA2 standing grants are now implemented, reusing cc's
existing lazy userspace reader. Administrators configure repository names, fixed
HTTPS mirrors, cache/object limits and the separate `allow_cvmfs_fetch` permission.
Server chats select repositories at creation:
`sandbox.linux("neurocommand-test", workspace=w, cvmfs=["neurodesk.ardc.edu.au"])`.
The share appears read-only at `/cvmfs/neurodesk.ardc.edu.au`; no host or guest
FUSE mount is needed. Reads use the Peer network only for the granted
mirror/repository paths, independently of general guest internet.

The adapter uses bounded per-guest response caches in RAM; shared persistent
disk caching remains future work. `vm.status().cvmfs` exposes mount, cache and
fetch diagnostics. A ready VM is not evidence of a successful repository read.
Local HTTPS fixture tests cover actual catalogs/files, failover, read-only
behavior, cancellation, cache and redirect bounds. The opt-in real KVM test is
documented in [SA2's sandbox guide](../sa2/docs/LINUX_SANDBOX.md#read-only-cvmfs-shares).
The real Server/Peer/KVM test passed on `ws1` (Linux/amd64), including guest Go
build/tests, two-guest draft visibility, repeated live repository reads,
read-only enforcement and absence of the share in an unselected guest.

Use a digest-pinned Neurocommand test image with its interpreter, Lmod, Apptainer
and menu dependencies prepared. Generate the instance configuration and install
into guest-local paths; never invoke its system-file installer on the peer host.
Run one guest with the approved CVMFS share and one without it using an explicit
local SIF. Check module discovery, menus and a deterministic scientific command
in both. Linux/amd64 is the currently supported SA2 sandbox host/platform.

The test image recipe, isolated installation and acceptance harness now live in
[`workflows/neurocommand`](workflows/neurocommand). The dependency image has
built successfully on `ws1`; the paired acceptance also exercises nested
Apptainer, generated modules and a deterministic scientific command. The paired
run passed with guest internet disabled: local SIF and expanded CVMFS container,
656 generated desktop entries in each guest, the complete candidate pytest suite
with Lmod initialized, and a generated 2×2×2 image of value 7 whose voxel sum is
56. See the [validation record](workflows/neurocommand/VALIDATION.md) and
[captured reports](workflows/neurocommand/validation/ws1-20261012.json).

## Neurocommand acceptance with command runners

SA2 now supports `vm.runner(cwd=..., env=...)` and native
`privileged.runner(...)`. Both provide string argv through `run`, explicit
`shell` execution, decoded text plus raw output bytes, and automatic cleanup of
completed process captures. Git, Go and Python/uv helpers accept `executor=`;
Python's existing `runner="pytest"` still selects the test framework. Server
chats can load these libraries directly without native execution authority.
See [SA2's runner contract](../sa2/docs/LINUX_SANDBOX.md#bound-command-runners).

Build [the dependency image](workflows/neurocommand/Dockerfile) from this root
using `neurocommand.build_test_image(base_image, apptainer_image, tag=...)`, or:

```sh
docker buildx build --platform linux/amd64 --load \
  --build-arg BASE_IMAGE="$PINNED_UBUNTU_REFERENCE" \
  --build-arg APPTAINER_IMAGE="$PINNED_APPTAINER_REFERENCE" \
  -f workflows/neurocommand/Dockerfile -t neurocommand-test:local .
```

Both inputs must be operator-selected `@sha256:` references for Linux/amd64.
The base must provide Ubuntu-family apt packages and be ABI-compatible with the
Apptainer image's `/opt/apptainer` distribution. The build probes Python, Lmod and
Apptainer; it installs test dependencies from this checkout's requirements and
includes no published Neurocommand source. Publish the resulting dependency
image to a registry accessible to the Peer, then configure its exact digest as
the `neurocommand-test` sandbox catalog entry. A Docker-local image ID is not a
sandbox catalog reference. Allow enough RAM, boot time and lifetime for the
scientific test; the example requests 2 CPUs, 4 GiB and a 30-minute command timer.
Choose CVMFS cache/object limits suitable for the selected container's objects.
For local testing, a loopback-only HTTPS registry with its certificate supplied
to the test process via `SSL_CERT_FILE` avoids publishing the image externally.

Mount the current Neuromono SCS draft, including local Neurocommand changes and
these workflow files. Supply a JSON-compatible spec with actual artifact paths
and expectations established before execution; these values are illustrative:

```python
spec = {
    "container": "tool_1.0_20260101.simg",
    "local_sif": "/workspace/artifacts/tool_1.0_20260101.simg",
    "cvmfs_image": "/cvmfs/neurodesk.ardc.edu.au/containers/tool_1.0_20260101/tool_1.0_20260101.simg",
    "sif_sha256": "<verified 64-character SHA-256 of the local SIF>",
    "image_files": {"/opt/tool/bin/toolstats": "<verified SHA-256 of the scientific executable>"},
    "command": ["toolstats", "/workspace/fixtures/tiny-input.nii.gz"],
    "stdout_sha256": "<expected SHA-256 of exact scientific stdout bytes>",
}
```

Neurodesk CVMFS publishes expanded container directories under `.simg` names.
The local path must be a SIF; the CVMFS path may be an expanded directory or a
SIF with the expected hash. Supply hashes for selected scientific binaries and
other relevant files in `image_files`; both formats must match them. This proves
the selected files match, not equality of entire container root filesystems.
The scientific command must be exposed by the container; use a small
deterministic fixture, such as a known-volume statistics check. Do not derive
the expected result from the candidate run itself. Files must already exist in
the mounted draft, dependency image or CVMFS share; the harness does not download
a replacement artifact or enable guest internet.

Define [acceptance.star](workflows/neurocommand/acceptance.star) in a Server chat
(paste its definitions into the REPL; project-file `load` is not supported), then:

```python
reports = neurocommand_acceptance("neurocommand-test", scs.open("neuromono"), spec)
print(json.encode(reports))
```

It runs fresh guests sequentially without and with CVMFS and closes each guest
after a returned command result, including ordinary test failures. If execution
or transport raises before this cleanup, close any surviving VM explicitly;
normal VM lease/lifetime cleanup still applies. Server chats do not evaluate the
root `AGENTS.star`; the namespace's `acceptance(vm, spec, mode)` is a convenience
for configurations that already supply a VM handle.

The driver fingerprints materialized candidate files and modes, excluding Git
metadata, `.venv`, `local` and Python/test caches. It rejects source symlinks,
copies the candidate into guest-private storage, generates isolated LXDE menu
files/configuration/launchers, runs its pytest suite, deploys wrappers/modules
from the selected container, verifies Lmod keyword discovery and executes the scientific
command through the generated wrapper. Apptainer uses user namespaces and
temporary SIF extraction to avoid requiring loop devices or a FUSE image mount.
It checks the local SIF, selected container files and scientific output hashes and
confirms the mounted source stayed unchanged. The paired report also compares
source/selected-file/output identities and guest image digests across modes, and records
CVMFS fetch/cache diagnostics. This verifies generated menu metadata; native UI
interaction and the system-file `install.sh` path remain outside this harness.

The real menu builder, input validation and source identity checks can run locally:

```sh
uv run --no-project --python python3 --with setuptools==84.0.0 \
  python -m unittest discover -s workflows/neurocommand -p test_acceptance.py -v
```

These local checks do not boot a VM, execute a SIF or establish live CVMFS/scientific
acceptance. Linux acceptance is deliberately opt-in and fails on missing
prerequisites once enabled. Build SA2's guest-init payload first, then run:

```sh
bash tools/build-peer.sh --guest-only
SA2_NEUROCOMMAND_VM=1 \
SA2_NEUROCOMMAND_ROOT=/path/to/current/neuromono \
SA2_NEUROCOMMAND_IMAGE=registry.example/neurocommand-test@sha256:... \
SA2_NEUROCOMMAND_SPEC=/path/to/spec.json \
SA2_SANDBOX_CVMFS_MIRROR=https://s1brisbane-cvmfs.openhtc.io/cvmfs \
SA2_SANDBOX_VM_STATE_DIR=/path/to/isolated/cache \
go test ./internal/server -run '^TestSandboxNeurocommandIntegration$' -v -count=1 -timeout 40m
```

Run this command from the SA2 checkout. Use `-count=1` for every live run: Go's
test cache does not reliably track external candidate trees or live repositories.
It imports the current candidate and
workflow files into a new Server draft, preserves file modes and evaluates the
paired workflow through an actual Peer. The local SIF may live in the dependency
image under `/artifacts` to keep large binaries out of the source draft. Test
shutdown closes guests and the Peer even on failure.

## Native desktop prerequisites and local coverage

Native peer sessions already support macOS and Windows. Use native checkouts and
project configuration on each OS; peerless CAH compute remains Linux-only.
Reliable automated desktop coverage needs a logged-in display session, an
isolated app profile, launch/shutdown control, and UI assertions/screenshots.
Install/uninstall verification additionally needs disposable users or VMs and
platform signing/installer prerequisites. CrumbleCracker needs Hypervisor.framework
on Apple Silicon, KVM on Linux, or Windows Hypervisor Platform on Windows.

Enabling SA2 sandbox guests on this Apple Silicon Mac requires upstream work:
cc's embedded sandbox backend and custom-init contract currently target
Linux/amd64, as do SA2 admission and guest-init packaging. It is more than removing
the scheduler's architecture check. Native CrumbleCracker already supports this
host and can be exercised separately. Cross-platform peerless execution would
also need a filesystem transport with the required native platform semantics.

| Coverage | On an Apple Silicon Mac |
| --- | --- |
| SA2 REPL/configuration, adapters and ordinary unit tests | Local; Linux-only integration checks still need Linux |
| Neurodesktop ARM64 image build/runtime tests | Local through a running Docker/Podman Linux VM |
| Neurodesktop amd64 image tests | Possible with configured emulation; not evidence of native amd64 coverage |
| Neurocontainers native ARM64 acceptance | Native Linux ARM64 peer/runner required |
| Neurocommand guest tests through `sandbox.linux` | Linux/amd64 peer with KVM required today |
| Neurodesk App macOS build, launch and packaging | Local with Node/Yarn and packaging prerequisites |
| CrumbleCracker ARM64 VM smoke/share/persistence | Local with a signed executable and suitable image |
| macOS GPU/software display checks | Local native app/window; automation deferred |
| Windows/Linux app and installer acceptance | Native OS machines or suitable disposable environments |

On the initial evaluation host Docker and Podman CLIs were installed but their
engines were stopped. Start one before real container checks. Tool availability,
free disk/memory and the repository's test dependencies still need checking for
each workflow. Browser automation built around the Linux sandbox is deferred.
