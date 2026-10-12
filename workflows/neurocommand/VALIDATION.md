# Linux acceptance on ws1, 2026-10-12

The current candidate passed the paired Neurocommand workflow through an actual
SA2 Server, Peer and KVM guests on Linux/amd64. Guest internet was disabled for
both modes. [The captured reports](validation/ws1-20261012.json) record the actual
image, source, selected-file and scientific-output hashes and CVMFS diagnostics.

The test imported the local candidate into a new SCS draft, preserving file modes.
Neurocommand revision was `4027dfec96cf8aa5d371b5d73a7c30b45102352c`, with the
local-only module-test isolation fix in `test/test_fetch_and_run.py`. Both guest
runs used candidate source hash
`9a81599ce1c889ab76f58d0a97284a2e760139dea7a2d17f275b4155784b67fe`.

## Results

| Check | Result |
| --- | --- |
| Dependency image built from this checkout's requirements | Passed |
| Local SIF and expanded CVMFS container execution through nested Apptainer | Passed |
| Candidate pytest suite, with Lmod initialized for its optional integration cases | Passed in both guests |
| Isolated configuration, menus and launcher generation | 656 desktop entries in each guest |
| Generated module discovery, load and executable wrapper | `convert3d/1.0.0`, passed in both guests |
| Scientific check | `c3d -create 2x2x2 1x1x1mm -shift 7 -voxel-sum` returned `Voxel Sum: 56` |
| Mounted candidate preservation | Source hash unchanged in both guests |
| Matching selected scientific binary | `/opt/convert3d-1.0.0/bin/c3d` hashes matched |
| Matching guest image and scientific output | Hashes matched across modes |
| Real CVMFS reads with guest internet disabled | Passed; Brisbane HTTPS mirror |
| Guest and Peer cleanup | Passed; no retained VM capabilities |

The uncached paired run completed in 101.11 seconds. It used two CPUs and 4 GiB
per guest, sequentially. CVMFS fetched 660,002,472 bytes in 1,362 requests; its
final response cache retained 1,958,835 bytes within the 64 MiB limit. These are
observed transfer/cache statistics, not a performance guarantee. Shared persistent
caching and broader scientific workloads remain untested.

The scientific expectation comes from 8 voxels × 7. The exact expected stdout is
`Voxel Sum: 56` followed by a newline, with SHA-256
`3bbb06113ac148d0bfac735c50513877afe86f68c6e6d74b4e2940f05bfdb8b3`.

## Inputs and fixes discovered

The dependency image used Ubuntu
`sha256:a08e551cb33850e4740772b38217fc1796a66da2506d312abe51acda354ff061`
and Apptainer 1.4.5
`sha256:cfc99015d4af5e4f3f52ce5d5e569ed1e214b4d49a56a2f77b140d5e9cbee595`.
A separate fixture layer added the local SIF. Its final registry manifest was
`sha256:2a0fce60e12d0f546e4265ac338de38c680d5c2514bb8cf6dde21ee02c7e23e7`.
The image was served by a temporary loopback-only HTTPS registry on ws1; it was
not published externally. The local SIF was built from ws1's existing
`convert3d:1.0.0` image. The selected c3d binary matches CVMFS; the README files
differ, so the result does not claim identical entire root filesystems.

Live testing required these corrections:

- Accept expanded `.simg` directories on CVMFS and verify explicitly selected
  container-file hashes in both formats, plus the local SIF's complete hash.
- Use Apptainer user namespaces and temporary SIF extraction. The guest does
  not provide working loop devices for Apptainer's default root SIF mount.
- Leave `CVMFS_DISABLE` absent for transparent-singularity's CVMFS branch; that
  script treats any nonempty value, including `false`, as disabling CVMFS.
- Make local-only module test fixtures explicitly disable CVMFS, so a real
  repository mount cannot change their expected module path.
- Use the Brisbane or NIKHEF HTTPS mirrors. The primary mirror refused HTTPS
  connections during this run.
- Pass `-count=1` for live Go tests; cached passes do not validate changed
  external candidate trees or live repositories.

## Other validation and limits

The Linux runner/REPL tests, real two-guest shared-draft acceptance with guest Go
build/tests, and live CVMFS read-only/selection checks passed. The latter also
ran the Go stdlib helper using `executor=vm.runner(...)`, including a per-call
guest directory override. SA2's Linux
`go vet ./...` and cc's Linux race tests for `sandbox/fs` passed.

The complete Linux SA2 suite had one failure in unchanged code:
`TestLinuxSandboxReadOnlyRoots`. Fedora's `/usr/bin/ld` follows
`/etc/alternatives/ld`; the native Bubblewrap sandbox omits that link, so its C
compiler fixture cannot find the linker. This is separate from the KVM runner
and paired Neurocommand checks. The full suite is therefore not green.

This run does not cover browser interaction, system installation, native desktop
apps/installers, ARM64 guests, or every scientific container. Browser automation
remains deferred. Reproduction instructions are in
[WORKFLOWS.md](../../WORKFLOWS.md#neurocommand-acceptance-with-command-runners).
The isolated checkout, caches and detailed logs are retained on ws1 under
`/home/joshua/dev/tmp/sa2-neuromono-20261012`.
The temporary registry is stopped, and all test guests and Peer processes have
exited. Its retained image and certificate can be used to repeat the run locally.
