"""Exercise the configured REPL and repository boundaries without building or networking."""

for repository in [neurodesktop, neurocontainers_arm64, neurocontainers_arm64.neurocontainers, neurocommand, neurodesk_app, crumblecracker]:
    print(repository.workspace.path())
    result = repository.git.status(check = True)
    if not result.success or result.timed_out:
        fail("git status failed for " + repository.repository)

if neurocontainers_arm64.neurocontainers.repository != "Vbitz/neurocontainers":
    fail("nested recipe repository is not configured")

print("Neuromono REPL smoke check passed.")
