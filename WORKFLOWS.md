# Neuromono Workflows

## Neurodesktop

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
