"""Run only inside an SA2 Linux guest; JSON stdin supplies explicit test artifacts.

The mounted checkout is the candidate. All generated configuration, menu files,
container wrappers and pytest writes stay in a new guest-private directory.
"""

import argparse
import configparser
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import stat
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET


SKIP = {".git", ".venv", "__pycache__", ".pytest_cache", "local"}


def sha256(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for data in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(data)
    return digest.hexdigest()


def tree_hash(root):
    digest = hashlib.sha256()
    for path in sorted(root.rglob("*")):
        relative = path.relative_to(root)
        if any(part in SKIP for part in relative.parts):
            continue
        if path.is_symlink():
            raise ValueError(f"candidate source must be materialized, not a symlink: {relative}")
        if not path.is_file():
            continue
        mode = str(stat.S_IMODE(path.stat().st_mode)).encode()
        digest.update(str(relative).encode() + b"\0" + mode + b"\0" + sha256(path).encode() + b"\0")
    return digest.hexdigest()


def validate_spec(spec, mode):
    for key in ("sif_sha256", "stdout_sha256"):
        if not re.fullmatch(r"[0-9a-f]{64}", spec.get(key, "")):
            raise ValueError(f"{key} must be an expected SHA-256, supplied before execution")
    container = spec.get("container", "")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.+-]*_[A-Za-z0-9][A-Za-z0-9.+-]*_[0-9]{8}\.simg", container):
        raise ValueError("container must be name_version_YYYYMMDD.simg")
    command = spec.get("command")
    if not isinstance(command, list) or not command or any(not isinstance(arg, str) or "\0" in arg for arg in command):
        raise ValueError("command must be nonempty string argv for a deterministic scientific check")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.+-]*", command[0]):
        raise ValueError("command[0] must be the exposed executable name, without a path")
    files = spec.get("image_files")
    if not isinstance(files, dict) or not files:
        raise ValueError("image_files must supply expected SHA-256 values for selected container files")
    for name, expected in files.items():
        path = Path(name)
        if not path.is_absolute() or ".." in path.parts or str(path) != name or not re.fullmatch(r"[0-9a-f]{64}", expected):
            raise ValueError("image_files requires clean absolute container paths and SHA-256 values")
    key = "cvmfs_image" if mode == "cvmfs" else "local_sif"
    image = Path(spec.get(key, spec.get("cvmfs_sif", "") if mode == "cvmfs" else ""))
    if not image.is_absolute() or not (image.is_file() or mode == "cvmfs" and image.is_dir()):
        raise ValueError(f"{key} must name an existing SIF (or an expanded CVMFS container)")
    if mode == "cvmfs" and not image.resolve().is_relative_to("/cvmfs/neurodesk.ardc.edu.au"):
        raise ValueError("cvmfs_image must use the approved Neurodesk CVMFS repository")
    return image


def run(argv, cwd, env, capture=False):
    result = subprocess.run(
        argv, cwd=cwd, env=env, check=True, timeout=600,
        stdout=subprocess.PIPE if capture else sys.stderr, stderr=sys.stderr,
    )
    return result.stdout if capture else None


def verify_image_files(image, spec, root, env):
    # CVMFS publishes expanded sandboxes, not byte-identical SIF files. Verify
    # operator-selected content in both formats before running the candidate.
    actual = {}
    for name, expected in sorted(spec["image_files"].items()):
        output = run(["singularity", "exec", "--cleanenv", str(image), "sha256sum", name], root, env, capture=True)
        digest = output.decode().split()[0]
        if digest != expected:
            raise AssertionError(f"container file {name}: SHA-256 {digest} != {expected}")
        actual[name] = digest
    return actual


def install(source, root, env):
    root = root.resolve(strict=True)
    candidate = root / "source"
    shutil.copytree(source, candidate, ignore=shutil.ignore_patterns(*SKIP))
    destination = root / "install"
    for name in ("icons", "applications", "desktop-directories"):
        (destination / name).mkdir(parents=True)
    config = configparser.ConfigParser()
    config["neurodesk"] = {
        "installdir": str(destination), "deskenv": "lxde", "edit": "n",
        "appmenu": "", "appdir": str(destination / "applications"),
        "deskdir": str(destination / "desktop-directories"),
        "sh_prefix": "", "singularity_opts": "",
    }
    with (candidate / "config.ini").open("w") as stream:
        config.write(stream)
    run([sys.executable, "-m", "neurodesk"], candidate, env)
    ET.parse(destination / "neurodesk-applications.menu")
    desktops = list((destination / "applications").glob("*.desktop"))
    if not desktops or not list((destination / "bin").glob("*.sh")):
        raise AssertionError("candidate did not generate desktop entries and command launchers")
    for desktop in desktops:
        entry = configparser.ConfigParser(interpolation=None, strict=False)
        entry.read(desktop)
        if not entry.has_option("Desktop Entry", "Exec"):
            raise AssertionError(f"missing Exec in {desktop}")
        argv = shlex.split(entry["Desktop Entry"]["Exec"])
        if len(argv) < 2 or argv[0] != "/bin/bash" or not Path(argv[1]).is_relative_to(destination / "bin") or not Path(argv[1]).is_file():
            raise AssertionError(f"desktop entry does not select its generated launcher: {desktop}")
    return candidate, destination, len(desktops)


def check_container(candidate, root, image, spec, env):
    stem = spec["container"][:-5]
    name_version, _date = stem.rsplit("_", 1)
    name, version = name_version.rsplit("_", 1)
    deployment = root / "containers" / stem
    shutil.copytree(candidate / "neurodesk/transparent-singularity", deployment)
    (deployment / spec["container"]).symlink_to(image)
    # --storage=local plus the existing SIF prevents retrieval/fallback. Some
    # candidate versions still probe registry metadata; guest internet is off.
    run(["bash", "run_transparent_singularity.sh", "--container", spec["container"], "--storage", "local"], deployment, env)
    module = f"{name}/{version}"
    modulefile = root / "containers/modules" / name / f"{version}.lua"
    if not modulefile.is_file() or not (deployment / spec["command"][0]).is_file():
        raise AssertionError("candidate did not generate the selected module and executable wrapper")
    module_env = dict(env, SA2_MODULE=module, SA2_KEYWORD=spec["command"][0])
    discovery = run(["bash", "-c", "set -e; source /usr/share/lmod/lmod/init/bash; module --ignore-cache keyword \"$SA2_KEYWORD\" 2>&1"], root, module_env, capture=True)
    if module.encode() not in discovery:
        raise AssertionError(f"Lmod keyword discovery did not find {module}: {discovery!r}")
    script = 'set -e; source /usr/share/lmod/lmod/init/bash; module load "$SA2_MODULE"; exec "$@"'
    output = run(["bash", "-c", script, "neurocommand-check", *spec["command"]], root, module_env, capture=True)
    digest = hashlib.sha256(output).hexdigest()
    if digest != spec["stdout_sha256"]:
        raise AssertionError(f"scientific stdout SHA-256 {digest} != {spec['stdout_sha256']}")
    return module, digest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", default="/workspace/neurocommand")
    parser.add_argument("--mode", choices=("local", "cvmfs"), required=True)
    args = parser.parse_args()
    if sys.platform != "linux" or os.environ.get("SA2_NEUROCOMMAND_GUEST") != "1":
        parser.error("invoke through vm.runner in a Linux guest")
    spec = json.load(sys.stdin)
    image = validate_spec(spec, args.mode)
    actual = sha256(image) if image.is_file() else None
    if actual is not None and actual != spec["sif_sha256"]:
        raise AssertionError(f"SIF SHA-256 {actual} != {spec['sif_sha256']}")
    cvmfs = Path("/cvmfs/neurodesk.ardc.edu.au")
    if (args.mode == "cvmfs") != cvmfs.is_dir():
        raise AssertionError("CVMFS mount presence disagrees with requested mode")
    source = Path(args.source).resolve(strict=True)
    before = tree_hash(source)
    root = Path(tempfile.mkdtemp(prefix="sa2-neurocommand-", dir="/tmp"))
    env = dict(os.environ, HOME=str(root / "home"), XDG_CONFIG_HOME=str(root / "home/.config"),
               NEURODESKTOP_LOCAL_CONTAINERS=str(root / "containers"),
               MODULEPATH=str(root / "containers/modules"),
               APPTAINER_CACHEDIR=str(root / "apptainer-cache"),
               APPTAINER_TMPDIR=str(root / "tmp"),
               APPTAINER_USERNS="true", APPTAINER_UNSQUASH="true",
               APPTAINER_BINDPATH="/workspace,/cvmfs,/data,/mnt,/neurodesktop-storage,/tmp", DISPLAY="")
    # Neurocommand tests whether CVMFS_DISABLE is empty; the string "false"
    # disables CVMFS too. Leave it absent for the CVMFS branch.
    env.pop("CVMFS_DISABLE", None)
    if args.mode == "local":
        env["CVMFS_DISABLE"] = "true"
    for directory in ("home", "tmp", "apptainer-cache", "containers/modules"):
        (root / directory).mkdir(parents=True)
    image_files = verify_image_files(image, spec, root, env)
    candidate, destination, desktop_count = install(source, root, env)
    try:
        run(["bash", "-c", 'set -e; source /usr/share/lmod/lmod/init/bash; exec "$@"', "candidate-pytest",
             sys.executable, "-m", "pytest", "-q", "test", "--basetemp", str(root / "pytest")], candidate, env)
    except subprocess.CalledProcessError:
        print(f"pytest CVMFS_DISABLE={env.get('CVMFS_DISABLE')!r}", file=sys.stderr)
        for log in (root / "pytest").rglob("module-calls.log"):
            print(f"{log}:\n{log.read_text()}", file=sys.stderr)
        raise
    module, stdout_hash = check_container(candidate, root, image, spec, env)
    if tree_hash(source) != before:
        raise AssertionError("acceptance modified the mounted source checkout")
    report = {"mode": args.mode, "source_sha256": before, "sif_sha256": actual,
              "image_format": "sif" if image.is_file() else "sandbox", "image_files": image_files,
              "stdout_sha256": stdout_hash, "module": module, "desktop_entries": desktop_count,
              "install": str(destination), "root": str(root), "command": spec["command"], "image": str(image)}
    (root / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report))


if __name__ == "__main__":
    main()
