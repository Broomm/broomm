# Pinned CI Devbox bootstrap

The existing workflows use Devbox 0.18.4 through the pinned Jetify action.
On 2026-11-08, multiple clean runners failed before compilation when its
launcher downloaded the versioned binary through GitHub's browser asset URL.
One earlier Android attempt separately failed downloading Gradle with HTTP 504.
Those original failures remain recorded; neither is an application test result.

`tool/ci/seed_devbox.py` downloads the same official Devbox release through
GitHub's release-asset API before the existing action. The short-lived job token
is sent only to the API; storage redirects receive no authorization header.
The script accepts one bounded ordinary binary, checks both archive and binary
SHA-256/length, and exclusively publishes it into the versioned runner cache.
It refuses foreign cache entries and simultaneous preparation, retaining them.
The existing action still configures Nix, verifies the selected version and
checks the supplied binary checksum. No SDK or license is installed by this
step, and no tool version, application dependency or runtime payload changes.

The four Linux/macOS architecture pins, exact source commit and Apache-2.0
license provenance are in `tool/ci/devbox-0.18.4.json`. All four official archives
were downloaded and independently inspected on the development host; this does
not establish execution on the other architectures. Windows keeps its existing
Flutter action and pre-provisioned native toolchain.

For local regression checks, run from the repository:

```sh
devbox run --config tool/android -- bash -c 'cd ../.. && python3 -m unittest discover -s tool/ci -p test_seed_devbox.py -v'
devbox run --config tool/ci/lint check
```

The three cases exercise credential stripping/redirect rejection, verified
offline replay/foreign-cache preservation, and unsafe archives/held OS locks.
They use temporary fixtures and remove them automatically. CI runs these
independently on Linux and macOS before bootstrap. The seed entry point requires
GitHub Actions, its ephemeral token and `GITHUB_OUTPUT`; it is not a workstation
installation command. Its only persistent output is the disposable runner's
`~/.cache/devbox/bin/0.18.4_<platform>/devbox`, which the existing action then moves
to its normal runner executable location. Runner disposal is the cleanup.

Local boundary tests and workflow lint pass. Actual hosted workflow acceptance
remains pending until the next PR run completes.
