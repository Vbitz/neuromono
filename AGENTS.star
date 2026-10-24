load("//stdlib/github.star", github_pr_merge="pr_merge")
"""Neuromono development workflows.

Each repository owns its workspace, Git/GitHub tools and commands. Commands run
with the native peer's host authority; workspace scoping is not a process sandbox.
Nothing builds, installs, downloads or starts at configuration initialization.
Unsupported workflows are commented at the relevant namespace below.
Read the affected repository's AGENTS.md before editing it.
"""

load("//stdlib/apptainer.star", apptainer_exec = "exec", apptainer_inspect = "inspect", apptainer_shell = "shell")
load("//stdlib/containers.star", "load_archive", "resource_tracker", container_build = "build", container_run = "run")
load("//stdlib/git.star", git_tools = "tools")
load("//stdlib/github.star", github_download = "run_download", github_pr_create = "pr_create", github_tools = "tools", github_workflow_run = "workflow_run")
load("//stdlib/golang.star", go_run = "run", go_test = "test", golang = "tools")
load("//stdlib/nodejs.star", "yarn_install", yarn_run = "yarn_run_script")
load("//stdlib/python.star", "uv_run", "uv_sync", python_test = "test")

_root = privileged.workspace(".")
_linux_platform = "linux/" + platform.split("/")[1]

def _git_call(name, directory):
    def call(*args, **kwargs):
        if "cwd" in kwargs:
            fail("repository Git tools already select their workspace")
        kwargs["cwd"] = directory
        return getattr(git_tools, name)(*args, **kwargs)

    return call

def _github_call(function, directory, repository):
    def call(*args, **kwargs):
        if "cwd" in kwargs:
            fail("repository GitHub tools already select their workspace")
        kwargs["cwd"] = directory
        if "repo" not in kwargs:
            kwargs["repo"] = repository
        return function(*args, **kwargs)

    return call

def _repository(path, repository):
    def _github_pr_edit(number, title = None, body = None, base = None, repo = None, cwd = None, check = True):
        """Edit PR metadata in any selected repository without changing its branch."""
        if not str(number).isdigit() or not repo or repo.startswith("-"):
            fail("A numeric PR and explicit repository are required")
        args = ["pr", "edit", str(number), "--repo", repo]
        for flag, value in [("--title", title), ("--body", body), ("--base", base)]:
            if value != None:
                args += [flag, value]
        if title == None and body == None and base == None:
            fail("Specify PR metadata to edit")
        return privileged.run("gh", cwd = cwd, check = check, timeout_ms = 120000, env = {"GH_PROMPT_DISABLED": "1", "GH_PAGER": "cat"}, *args)

    def _github_pr_state(number, state, comment = None, repo = None, cwd = None, check = True):
        """Close or reopen a PR, optionally leaving a redirect; never delete branches."""
        if state not in ["close", "reopen"] or not str(number).isdigit() or not repo or repo.startswith("-"):
            fail("Specify close/reopen, a numeric PR, and a repository")
        args = ["pr", state, str(number), "--repo", repo]
        if comment != None:
            args += ["--comment", comment]
        return privileged.run("gh", cwd = cwd, check = check, timeout_ms = 120000, env = {"GH_PROMPT_DISABLED": "1", "GH_PAGER": "cat"}, *args)
    directory = privileged.workspace(path)
    return module(
        path,
        workspace = directory,
        repository = repository,
        git = module("git", **{name: _git_call(name, directory) for name in [
            "status",
            "diff",
            "log",
            "show",
            "rev_parse",
            "remotes",
            "fetch",
            "merge",
            "branches",
            "switch",
            "add",
            "commit",
            "push",
            "submodule_status",
            "submodule_update",
            "submodule_sync",
        ]}),
        github = module(
            "github",
            pr_create = _github_call(github_pr_create, directory, repository),
            pr_edit = _github_call(_github_pr_edit, directory, repository),
            pr_state = _github_call(_github_pr_state, directory, repository),
            pr_merge = _github_call(github_pr_merge, directory, repository),
            pr_checks = _github_call(github_tools.pr_checks, directory, repository),
            run_list = _github_call(github_tools.run_list, directory, repository),
            run_view = _github_call(github_tools.run_view, directory, repository),
            run_watch = _github_call(github_tools.run_watch, directory, repository),
            run_artifacts = _github_call(github_tools.run_artifacts, directory, repository),
            run_download = _github_call(github_download, directory, repository),
        ),
    )

_desktop = _repository("neurodesktop", "Vbitz/neurodesktop")
_recipes = _repository("neurocontainers-arm64/neurocontainers", "Vbitz/neurocontainers")
_arm64 = _repository("neurocontainers-arm64", "Vbitz/neurocontainers-arm64")
_command = _repository("neurocommand", "Vbitz/neurocommand")
_app = _repository("neurodesk-app", "Vbitz/neurodesk-app")
_crumble = _repository("crumblecracker", "tinyrange/crumblecracker")

def _desktop_build(platform = _linux_platform, backend = "docker", tag = None, build_args = {}, resources = None):
    """Build these Neurodesktop sources and retain the exact candidate image ID."""
    return container_build(context = ".", platform = platform, backend = backend, tag = tag, build_args = build_args, resources = resources, cwd = _desktop.workspace, check = True)

def _desktop_start(image, cvmfs = False, grant_sudo = False, ports = ("127.0.0.1:18888:8888",), mounts = (), privileged_mode = True):
    """Start a local candidate using the repository's standard root-container profile.

    privileged_mode grants host-engine privileges, including nested Apptainer.
    CVMFS success requires a supported architecture, network and actual mounted read.
    """
    for port in ports:
        if not (port.startswith("127.0.0.1:") or port.startswith("[::1]:")):
            fail("Neurodesktop ports must bind loopback")
    return container_run(image, platform = image.platform, backend = image.backend, ports = ports, mounts = mounts, env = {
        "CVMFS_DISABLE": "false" if cvmfs else "true",
        "GRANT_SUDO": "true" if grant_sudo else "false",
    }, user = "root", shm_size = "1gb", privileged = privileged_mode, cwd = _desktop.workspace, check = False)

def _desktop_ready(candidate):
    """Wait for an HTTP response; authentication and application checks follow separately."""
    return candidate.wait_ready(["curl", "--silent", "--show-error", "--output", "/dev/null", "--max-time", "2", "http://127.0.0.1:8888/api/status"], attempts = 90, interval_seconds = 2)

def _desktop_unit(*paths):
    return privileged.run("uv", "run", "--no-project", "--with", "pytest==8.4.2", "python", "-m", "pytest", cwd = _desktop.workspace, check = True, timeout_ms = 1800000, *(paths if paths else ["tests/unit"]))

def _desktop_image_tests(candidate, *paths):
    return candidate.exec(["pytest"] + list(paths if paths else ["/opt/tests/"]), user = "jovyan", env = {"NEURODESKTOP_TEST_ALLOW_GLOBAL_DESKTOP_SERVICES": "1"}, check = True, timeout_ms = 1800000)

neurodesktop = _desktop + module("neurodesktop", build = _desktop_build, start = _desktop_start, ready = _desktop_ready, test = _desktop_unit, test_image = _desktop_image_tests, resources = resource_tracker)

# Deferred: sandbox browser automation, screenshots and authenticated Jupyter UI tests.
# neurodesktop.browser_test(candidate, suite = "startup")
# Deferred: direct candidate PTY attachment; the existing peer terminal supports
# manually running docker/podman exec -it CID /bin/bash.
# neurodesktop.terminal(candidate)

def _recipe_command(command, *args):
    return uv_run(command, cwd = _recipes.workspace, check = True, timeout_ms = 21600000, *args)

def _recipe_sync():
    return uv_sync(cwd = _recipes.workspace, check = True)

def _recipe_build(recipe, *args):
    return _recipe_command("sf-build", recipe, *args)

def _recipe_init(name, version):
    return _recipe_command("sf-init", name, version)

def _recipe_smoke(recipe, *args):
    """Run sf-test deploy/smoke checks; this does not establish fulltest acceptance."""
    return _recipe_command("sf-test", recipe, *args)

def _recipe_fulltest(recipe, release_file, test_config = None, runtime = "apptainer"):
    """Test an explicitly selected local candidate using its release metadata.

    test_config may select a prepared subset; keep suite identity/version intact.
    No published-release fallback is requested.
    """
    args = [recipe, "--release-file", release_file, "--location", "local", "--runtime", runtime]
    if test_config != None:
        args += ["--test-config", test_config]
    return _recipe_command("sf-test-remote", *args)

def _recipe_unit(*paths):
    return _recipe_command("python", "-m", "pytest", *(paths if paths else ["builder/tests"]))

def _recipe_inspect(artifact, **kwargs):
    kwargs["cwd"] = _recipes.workspace
    return apptainer_inspect(artifact, **kwargs)

def _recipe_exec(artifact, command, **kwargs):
    kwargs["host_cwd"] = _recipes.workspace
    return apptainer_exec(artifact, command, **kwargs)

def _recipe_shell(artifact, **kwargs):
    kwargs["host_cwd"] = _recipes.workspace
    return apptainer_shell(artifact, **kwargs)

neurocontainers = _recipes + module(
    "neurocontainers",
    sync = _recipe_sync,
    build = _recipe_build,
    init_recipe = _recipe_init,
    test = _recipe_unit,
    smoke = _recipe_smoke,
    fulltest = _recipe_fulltest,
    inspect = _recipe_inspect,
    exec = _recipe_exec,
    shell = _recipe_shell,
)
# shell() describes an interactive command; launching a candidate PTY is deferred.
# neurocontainers.terminal(image)
# A named-case selector is aspirational; use fulltest(test_config=...) for now.
# neurocontainers.fulltest(recipe, release_file, cases = ["selected-case"])

def _arm64_phase(phase, *args):
    return _recipe_command("python", "../scripts/arm64.py", phase, *args)

def _arm64_prepare(recipe, variant = "arm64"):
    return _arm64_phase("prepare", "--recipe", recipe, "--variant", variant)

def _arm64_build():
    return _arm64_phase("build")

def _arm64_test():
    return _arm64_phase("test")

def _arm64_dispatch(recipe, ref, variant = "arm64"):
    """Dispatch only the orchestration repo; Actions stay disabled in the recipe fork."""
    return github_workflow_run("build-arm64.yml", repo = _arm64.repository, cwd = _arm64.workspace, inputs = {"recipe": recipe, "neurocontainers_ref": ref, "variant": variant}, check = True)

neurocontainers_arm64 = _arm64 + module("neurocontainers_arm64", neurocontainers = neurocontainers, prepare = _arm64_prepare, build = _arm64_build, test = _arm64_test, dispatch = _arm64_dispatch)

def _command_tests(*paths, executor = None):
    return python_test(cwd = _command.workspace if executor == None else None, executor = executor, runner = "pytest", check = True, *(paths if paths else ["test"]))

def _command_test_image(base_image, apptainer_image, tag = None, backend = "docker"):
    """Build test dependencies; both base references must identify exact digests."""
    for reference in [base_image, apptainer_image]:
        if "@sha256:" not in reference or len(reference.split("@sha256:")[-1]) != 64:
            fail("test image inputs must be digest-pinned OCI references")
    return container_build(context = ".", dockerfile = "workflows/neurocommand/Dockerfile", platform = "linux/amd64", build_args = {"BASE_IMAGE": base_image, "APPTAINER_IMAGE": apptainer_image}, tag = tag, backend = backend, cwd = _root, check = True)

def _command_acceptance(vm, spec, mode, source = "/workspace/neurocommand", driver = "/workspace/workflows/neurocommand/acceptance.py"):
    """Test local candidate sources inside a caller-owned guest; return its report."""
    if mode not in ["local", "cvmfs"]:
        fail("acceptance mode must be local or cvmfs")
    guest = vm.runner(cwd = source, env = {"SA2_NEUROCOMMAND_GUEST": "1", "PATH": "/opt/neurocommand-test/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"})
    result = guest.run("/opt/neurocommand-test/bin/python3", driver, "--source", source, "--mode", mode, stdin = json.encode(spec), check = True, timeout_ms = 1800000, output_limit = 1048576)
    if result.stdout_truncated or result.stderr_truncated:
        fail("acceptance output truncated; inspect the guest's report/logs")
    return json.decode(result.stdout)

neurocommand = _command + module("neurocommand", test = _command_tests, build_test_image = _command_test_image, acceptance = _command_acceptance)
# Server-chat workflow: use the dependency image recipe and driver in workflows/neurocommand.
# CVMFS selection is supported with the administrator's separate fetch grant:
# vm = sandbox.linux("neurocommand-test", workspace = scs.open("neuromono"), cvmfs = ["neurodesk.ardc.edu.au"])
# neurocommand.acceptance(vm, spec, mode = "cvmfs")
# vm.status().cvmfs  # read-only mount/cache/fetch diagnostics
# Repeat mode = "local" in a guest without CVMFS. The spec pins the SIF and scientific output.

def _app_sync():
    return privileged.run("npm", "exec", "--yes", "--package=yarn@1.22.22", "--", "yarn", "install", "--frozen-lockfile", cwd = _app.workspace, check = True, timeout_ms = 1800000)

def _app_build():
    return privileged.run("npm", "exec", "--yes", "--package=yarn@1.22.22", "--", "yarn", "build", cwd = _app.workspace, check = True, timeout_ms = 1800000)

def _app_tests(*args):
    return privileged.run("npm", "exec", "--yes", "--package=yarn@1.22.22", "--", "yarn", "test", cwd = _app.workspace, check = True, timeout_ms = 1800000, *args)

def _app_launch():
    """Launch the compiled app on this native peer; close the returned process afterward."""
    return yarn_run("start", cwd = _app.workspace, background = True, timeout_ms = 0)

def _app_package(target):
    if target not in ["linux-64", "linux-arm64", "mac", "win"]:
        fail("installer target must be linux-64, linux-arm64, mac or win")
    return yarn_run("dist:" + target, cwd = _app.workspace, check = True, timeout_ms = 1800000)

def _app_acceptance(*args):
    """Run the checkout's isolated app/Glass acceptance harness, retaining screenshots under build/."""
    return privileged.run("node", "scripts/crumblecracker-e2e.js", cwd = _app.workspace, env = {"NEURODESK_CC_BINARY": _crumble.workspace.path("build/NeurodeskAppX")}, check = False, background = True, kill_tree = True, timeout_ms = 3600000, *args)
def _app_check(tool, *paths):
    """Run scoped formatting, lint, or workflow syntax checks in the app checkout."""
    for path in paths:
        if path.startswith(("-", "/")) or ".." in path.split("/"):
            fail("checks require workspace-relative paths")
    if tool == "format":
        return privileged.run("node", "node_modules/prettier/bin-prettier.js", "--write", cwd = _app.workspace, check = True, *paths)
    if tool == "lint":
        return privileged.run("node", "node_modules/eslint/bin/eslint.js", cwd = _app.workspace, check = False, *paths)
    if tool == "workflows" and not paths:
        return privileged.run("node", "scripts/check-workflows.js", cwd = _app.workspace, check = True)
    fail("check must be format, lint or workflows")
neurodesk_app = _app + module("neurodesk_app", sync = _app_sync, build = _app_build, test = _app_tests, launch = _app_launch, package = _app_package, acceptance=_app_acceptance, check=_app_check)
# Docker/Podman can use image.tag("vnmd/neurodesktop:<local-tag>") and select that
# tag in app settings. Confirm the app uses the same engine/image before testing.
# Deferred: isolated app profiles, full image override, TinyRange local image
# import, native UI automation, and installer install/launch/uninstall checks.
# neurodesk_app.launch(image = candidate, backend = "tinyrange", profile = "test")
# neurodesk_app.test_installer(installer, platform = "windows/amd64")

def _crumble_build():
    """Build both apps and guest init; tools/build.go signs macOS binaries."""
    return go_run("./tools/build.go", cwd = _crumble.workspace, check = True, timeout_ms = 1800000)

def _crumble_tests(*packages):
    return go_test(cwd = _crumble.workspace, check = True, timeout_ms = 1800000, *(packages if packages else ["./..."]))

def _crumble_smoke(image, cache_dir = "build/sa2-smoke/cache", storage = "build/sa2-smoke/shared"):
    """Boot, execute, write a share, restart and verify persistence in isolated storage."""
    if "build" not in _crumble.workspace.list_dir("."):
        _crumble.workspace.mkdir("build")
    suffix = ".exe" if platform.startswith("windows/") else ""
    binary = _crumble.workspace.path("build/product-smoke" + suffix)
    golang.build("./tools/smoke", output = binary, cwd = _crumble.workspace)
    if platform.startswith("darwin/"):
        privileged.run("codesign", "--force", "--sign", "-", "--entitlements", _crumble.workspace.path("tools/entitlements.xml"), binary, cwd = _crumble.workspace, check = True)
    return privileged.run(binary, "-cache-dir", _crumble.workspace.path(cache_dir), "-storage", _crumble.workspace.path(storage), "-image", image, cwd = _crumble.workspace, check = True, timeout_ms = 1800000)

def _crumble_launch(app = "NeurodeskAppX"):
    if app not in ["SquadVM", "NeurodeskAppX"]:
        fail("app must be SquadVM or NeurodeskAppX")
    suffix = ".exe" if platform.startswith("windows/") else ""
    return privileged.run(_crumble.workspace.path("build/" + app + suffix), "-cache-dir", _crumble.workspace.path("build/sa2-" + app + "/cache"), "-storage", _crumble.workspace.path("build/sa2-" + app + "/shared"), cwd = _crumble.workspace, background = True, kill_tree = True, timeout_ms = 0)

def _crumble_guest_test(cache_dir, image = "smoke", desktop = False):
    """Run the existing signed, opt-in guest integration test on an isolated prepared candidate."""
    if not cache_dir.startswith("build/") or ".." in cache_dir.split("/"):
        fail("guest acceptance must use a build/ development cache")
    suffix = ".exe" if platform.startswith("windows/") else ""
    binary = _crumble.workspace.path("build/headless-acceptance" + suffix)
    privileged.run("go", "test", "-c", "-o", binary, "./internal/desktopapp", cwd = _crumble.workspace, check = True, timeout_ms = 1800000)
    if platform.startswith("darwin/"):
        privileged.run("codesign", "--force", "--sign", "-", "--entitlements", _crumble.workspace.path("tools/entitlements.xml"), binary, cwd = _crumble.workspace, check = True)
    return privileged.run(binary, "-test.run", "^TestHeadlessGuestIntegration$", "-test.v", "-test.timeout", "10m", cwd = _crumble.workspace, env = {"NDAPPX_HEADLESS_TEST_CACHE": _crumble.workspace.path(cache_dir), "NDAPPX_HEADLESS_TEST_IMAGE": image, "NDAPPX_HEADLESS_TEST_DESKTOP": "1" if desktop else "0", "NDAPPX_HEADLESS_TEST_EPHEMERAL": "0"}, check = False, timeout_ms = 660000)
crumblecracker = _crumble + module("crumblecracker", build = _crumble_build, test = _crumble_tests, smoke = _crumble_smoke, launch = _crumble_launch, guest_test = _crumble_guest_test)
# Deferred: a typed client for NeurodeskAppX's headless API and native window/GPU
# automation. The existing headless API explicitly rejects GPU acceleration.
# crumblecracker.test_rendering(gpu = True)
# crumblecracker.test_rendering(gpu = False)

def _mono_dispatch(ref = "main"):
    """Dispatch only Neuromono's pinned ARM64 candidate workflow."""
    return github_workflow_run("neurodesktop-arm64-candidate.yml", repo = "Vbitz/neuromono", cwd = _root, ref = ref, check = True)
def _mono_unpack_candidate(directory):
    """Verify downloaded candidate checksums and decompress its Docker archive."""
    if not directory.startswith("workflows/neurodesktop/validation/run-") or ".." in directory.split("/"):
        fail("candidate directory must be an isolated validation/run-* directory")
    location = _root.path(directory)
    privileged.run("shasum", "-a", "256", "-c", "SHA256SUMS", cwd = location, check = True, timeout_ms = 1800000)
    privileged.run("gzip", "-dk", "neurodesktop-arm64.tar.gz", cwd = location, check = True, timeout_ms = 1800000)
    return _root.path(directory + "/neurodesktop-arm64.tar")
neuromono = module("neuromono", workspace = _root, git = module("git", **{name: _git_call(name, _root) for name in ["status", "diff", "add", "commit", "push", "submodule_status", "submodule_update", "submodule_sync"]}), github = module("github", run_list = _github_call(github_tools.run_list, _root, "Vbitz/neuromono"), run_view = _github_call(github_tools.run_view, _root, "Vbitz/neuromono"), run_watch = _github_call(github_tools.run_watch, _root, "Vbitz/neuromono"), run_artifacts = _github_call(github_tools.run_artifacts, _root, "Vbitz/neuromono"), run_download = _github_call(github_download, _root, "Vbitz/neuromono")), dispatch_candidate = _mono_dispatch, load_image = load_archive, unpack_candidate = _mono_unpack_candidate)
# Aspirational whole-stack acceptance: source override for local Neurocommand,
# explicit image handoff to each app backend, native UI checks, and a manifest
# linking every tested revision/image/test result before updating parent pins.
# neuromono.test_stack(neurocommand = local_command, image = local_desktop)
# neuromono.pin_verified(manifest)
# Large images stay on the peer or use an explicit registry/archive transfer.
# Browser downloads remain limited to 16 MiB; CAH files remain limited to 1 GiB.

environment = {
    # Configuration installation requires explicit user approval.
    "edit_agents_star": privileged.edit_agents_star,
    "neuromono": neuromono,
    "neurodesktop": neurodesktop,
    "neurocontainers_arm64": neurocontainers_arm64,
    "neurocommand": neurocommand,
    "neurodesk_app": neurodesk_app,
    "crumblecracker": crumblecracker,
}
peerless_environment = environment
default_repl = repl(environment)
default = privileged.model("gpt-6-astra", "medium", default_cost_limit = 5.0).create(
    repl = repl(environment),
    prompt_addons = ["Read WORKFLOWS.md and the affected repository's AGENTS.md. Native process tools use host authority. Never substitute published artifacts for the local candidate under test. Unsupported workflows are commented in AGENTS.star."],
)
