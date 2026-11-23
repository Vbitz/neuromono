---
name: sync-submodules
description: Audit Neuromono's recursive submodule pins or sync its forks with upstream, preserving fork changes and publishing updated pins in dependency order.
---

# Sync Neuromono submodules

Run from the Neuromono root. Use `git submodule status --recursive` and read
the corresponding `.gitmodules` files to inventory the pinned commits and URLs.
Check branch, status, and remotes in every checkout before switching branches.
If a checkout has local changes or its current commit is outside the destination
branch history, preserve that work and inspect it before moving the pin.

| Checkout | Destination | Upstream |
| --- | --- | --- |
| `crumblecracker` | `tinyrange/crumblecracker:main` | Direct upstream |
| `neurocommand` | `Vbitz/neurocommand:main` | `neurodesk/neurocommand:main` |
| `neurocontainers-arm64` | `Vbitz/neurocontainers-arm64:main` | Standalone wrapper |
| `neurocontainers-arm64/neurocontainers` | `Vbitz/neurocontainers:main` | `neurodesk/neurocontainers:main` |
| `neurodesk-app` | `Vbitz/neurodesk-app:master` | `scigetorg/neurodesk-app:master` (formerly `neurodesk/neurodesk-app`) |
| `neurodesktop` | `Vbitz/neurodesktop:main` | `neurodesk/neurodesktop:main` |

## Audit

Verify repository names and default branches against GitHub or remote HEAD,
especially if a repository has moved. Fetch the fork branch, then compare the
recorded pin and checked-out HEAD independently with that branch. For forks, also
fetch the project's immediate upstream and compare the two branch tips.

```sh
git -C "$checkout" fetch --no-tags --no-recurse-submodules origin \
  "refs/heads/${branch}:refs/remotes/origin/${branch}"
git -C "$checkout" rev-list --left-right --count "$pin...origin/$branch"

git -C "$checkout" fetch --no-tags --no-recurse-submodules "$upstream_url" \
  "refs/heads/$upstream_branch"
git -C "$checkout" rev-list --left-right --count "origin/$branch...FETCH_HEAD"
```

Use `HEAD:<submodule-path>` in the immediate parent to get `pin`. Capture the
upstream SHA from `FETCH_HEAD` before another fetch in the same checkout. The
second comparison reports fork-only commits on the left and missing upstream
commits on the right. An audit ends with the comparisons and leaves pins alone.

## Sync

1. Work from each freshly fetched destination branch. Fast-forward a local
   branch that trails its remote. Fast-forward the fork if it is an ancestor of
   upstream. When the two have diverged, merge upstream into the fork to retain
   fork-only history. Use the published destination tip when it already contains
   upstream. Leave `neurodesk-app` on its default `master` branch.
2. Verify both the previous destination tip and fetched upstream tip are
   ancestors of the result. Inspect the diff from upstream to verify the
   surviving fork changes, and run validation appropriate to that diff.
3. For an authorized publication, use the fork's normal delivery workflow and
   push only to the fork. Keep Actions disabled on `Vbitz/neurocontainers`.
   Confirm the published child commit before committing its gitlink in the
   parent. Publish `neurocontainers` first, then its pin in
   `neurocontainers-arm64`, then the wrapper and other updated pins in Neuromono.
   Stage the relevant submodule paths explicitly.
4. Refetch destination and upstream heads for the final check. Verify each
   committed gitlink matches its intended published branch, every synced fork
   contains upstream, and `git submodule status --recursive` reports matching
   checkouts. Record any failed validation or publication separately from
   the commits that reached their destination.
