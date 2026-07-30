# Shared setup/teardown helpers for the upkeep fixture integration tests.
#
# Mirrors the template harness in test.bats (scratch ddev project under
# ${HOME}/tmp per test), plus:
#   - installs the add-on from the working tree in setup, since every fixture
#     test exercises the installed commands;
#   - points UPKEEP_FIXTURE_LIBRARY at a per-test directory inside TESTDIR so
#     tests never touch the real ~/.upkeep/fixtures library. ddev host
#     commands inherit the caller's environment, and the add-on treats
#     already-set env vars as authoritative over .ddev/.env.upkeep.
#
# NOTE (local macOS runs): the harness hardcodes ${HOME}/tmp. If your real
# ~/tmp is not writable, run bats with a shim HOME that symlinks the real
# .ddev, .docker and Library dirs and contains a writable tmp/ — see
# docs/testing.md. CI (ubuntu) needs no shim.

upkeep_test_setup() {
  set -eu -o pipefail

  export GITHUB_REPO=owenbush/ddev-upkeep

  TEST_BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
  export BATS_LIB_PATH="${BATS_LIB_PATH}:${TEST_BREW_PREFIX}/lib:/usr/lib/bats"
  bats_load_library bats-assert
  bats_load_library bats-file
  bats_load_library bats-support

  export DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." >/dev/null 2>&1 && pwd)"
  export PROJNAME="test-$(basename "${GITHUB_REPO}")"
  mkdir -p "${HOME}/tmp"
  export TESTDIR="$(mktemp -d "${HOME}/tmp/${PROJNAME}.XXXXXX")"
  export DDEV_NONINTERACTIVE=true
  export DDEV_NO_INSTRUMENTATION=true

  # Keep fixture-library writes inside the sandbox.
  export UPKEEP_FIXTURE_LIBRARY="${TESTDIR}/library"
  mkdir -p "${UPKEEP_FIXTURE_LIBRARY}"

  ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1 || true
  cd "${TESTDIR}"
  run ddev config --project-name="${PROJNAME}" --project-tld=ddev.site
  assert_success
  run ddev start -y
  assert_success
  run ddev add-on get "${DIR}"
  assert_success
}

upkeep_test_teardown() {
  set -eu -o pipefail
  ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1
  if [ -n "${GITHUB_ENV:-}" ]; then
    [ -e "${GITHUB_ENV:-}" ] && echo "TESTDIR=${HOME}/tmp/${PROJNAME}" >> "${GITHUB_ENV}"
  else
    [ "${TESTDIR}" != "" ] && rm -rf "${TESTDIR}"
  fi
}

# Run a SQL statement against the project's `db` database and print the
# result without column headers.
upkeep_sql() {
  echo "$1" | ddev mysql -N db
}
