"""Define this helper in a Server chat, then call it with an explicit test spec.

This file uses Server capabilities; it is not a native -script entrypoint.
No work starts until neurocommand_acceptance is called.
"""

def neurocommand_acceptance(image, workspace, spec, cpu = 2, memory_mib = 4096):
    reports = {}
    for mode in ["local", "cvmfs"]:
        vm = sandbox.linux(
            image,
            workspace = workspace,
            internet = False,
            cvmfs = ["neurodesk.ardc.edu.au"] if mode == "cvmfs" else [],
            cpu = cpu,
            memory_mib = memory_mib,
        )
        guest = vm.runner(cwd = "/workspace/neurocommand", env = {
            "SA2_NEUROCOMMAND_GUEST": "1",
            "PATH": "/opt/neurocommand-test/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
        })
        result = guest.run(
            "/opt/neurocommand-test/bin/python3",
            "/workspace/workflows/neurocommand/acceptance.py",
            "--mode",
            mode,
            stdin = json.encode(spec),
            check = False,
            timeout_ms = 1800000,
            output_limit = 1048576,
        )
        status = vm.status()
        vm.close()
        if not result.success or result.timed_out or result.stdout_truncated or result.stderr_truncated:
            fail("Neurocommand {} acceptance failed (exit {}):\n{}\n{}".format(mode, result.exit_code, result.stdout, result.stderr))
        report = json.decode(result.stdout)
        report["guest_image_digest"] = status.digest
        report["guest_platform"] = status.platform
        report["cvmfs"] = [{"repository": share.repository, "fetched_bytes": share.fetched_bytes, "requests": share.requests, "cache_bytes": share.cache_bytes, "cache_limit_bytes": share.cache_limit_bytes} for share in status.cvmfs]
        if mode == "cvmfs" and (len(report["cvmfs"]) != 1 or report["cvmfs"][0]["fetched_bytes"] <= 0):
            fail("CVMFS acceptance did not fetch the selected repository")
        reports[mode] = report
    for key in ["source_sha256", "image_files", "stdout_sha256", "guest_image_digest", "guest_platform"]:
        if reports["local"][key] != reports["cvmfs"][key]:
            fail("local/CVMFS acceptance used different " + key)
    return reports
