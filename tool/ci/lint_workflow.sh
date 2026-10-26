#!/usr/bin/env bash
set -euo pipefail
# actionlint 1.7.12 predates GitHub's documented concurrency.queue feature:
# https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency
# Guard our exact queued policy, then suppress only that obsolete schema error.
# All other workflow, expression and shell diagnostics remain errors.
awk '
  /^  queue:/ { total++; if ($0 != "  queue: max") exit 1 }
  /^  cancel-in-progress:/ { if ($0 != "  cancel-in-progress: false") exit 1; cancel++ }
  END { if (total != 1 || cancel != 1) exit 1 }
' .github/workflows/release.yml
actionlint -ignore '^unexpected key "queue" for "concurrency" section\.' .github/workflows/release.yml
shellcheck tool/ci/*.sh tool/ci/linux-tools/clang tool/ci/linux-tools/clang++ tool/build_app.sh
