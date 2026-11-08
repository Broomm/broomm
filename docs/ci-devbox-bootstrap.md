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
devbox run --config tool/android -- bash -c 'cd ../.. && python3 -m unittest discover -s tool/ci -p "test_seed_*.py" -v'
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

Hosted run 42471848973 passed this Devbox preparation, all platform checks,
macOS native tests and four desktop packages. The independent Mesen run passed
all four ABIs. Android then hit the separate Gradle browser-download HTTP 504.

## Unchanged Gradle distribution

`tool/ci/seed_gradle.py` seeds the existing wrapper's exact 9.3.1 complete ZIP
through the same official release-asset API route. The 234,893,460-byte archive's
SHA-256 matches [Gradle's published checksum](https://gradle.org/release-checksums/).
No wrapper, version or distribution URL changes. The seed writes only beneath
the already private `.tool-cache/android/gradle/wrapper/dists` cache, respects
the wrapper's actual Java file lock, verifies the complete ZIP and publishes it
exclusively. The wrapper owns subsequent extraction. Foreign/partial data is
retained with a visible failure; bounded download failures remove only the seed's
own temporary file. No SDK installation or license acceptance is involved.

Three additional regression cases exercise exact/offline cache replay, corrupt
or partial inputs and preservation, and a separate Java process using the actual
checked-in wrapper's cache path and `FileChannel` lock. Together, all six tests
pass locally. CI runs them on Linux and macOS; its pre-provisioned Java/Python
are bootstrap prerequisites, while application compilation stays in Devbox.
The Gradle seed entry point is CI-only and receives the job token for that step.
Temporary test directories clean themselves up; CI cache cleanup is runner
disposal. Hosted Android compilation after this correction remains pending.
The actual checked-in wrapper also extracted the real verified ZIP and reported
Gradle 9.3.1 offline on macOS through Devbox's Java, without a download, SDK build
or license request. Its disposable distribution cache was removed afterward.
