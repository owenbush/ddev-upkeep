#!/usr/bin/env bats

# The upgrade path from the un-namespaced commands.
#
# The add-on published `ddev fixture-load` and friends until they were
# namespaced to `ddev upkeep-fixture-load`. `ddev add-on get` copies the new
# files in but does not take the old ones out, so an upgraded project would
# keep four orphans that still work — sourcing the same library, under names
# this add-on no longer documents, with nothing to say they are superseded.
#
# install.yaml removes them, guarded on the file being ours. Both halves of
# that matter and both are tested here: ours goes, somebody else's stays.

load helpers

setup() {
  upkeep_test_setup
}

teardown() {
  upkeep_test_teardown
}

# A command file as this add-on used to install it.
write_old_command() {
  local name="$1"
  mkdir -p "${TESTDIR}/.ddev/commands/host"
  cat > "${TESTDIR}/.ddev/commands/host/${name}" <<EOF
#!/usr/bin/env bash

#ddev-generated
## Command provided by the upkeep add-on (https://github.com/owenbush/ddev-upkeep)
## Description: the superseded ${name}
echo "old ${name}"
EOF
  chmod +x "${TESTDIR}/.ddev/commands/host/${name}"
}

@test "reinstalling over the old command names removes them" {
  for old in fixture-create fixture-load fixture-list fixture-prune; do
    write_old_command "${old}"
    assert_file_exist "${TESTDIR}/.ddev/commands/host/${old}"
  done

  run ddev add-on get "${DIR}"
  assert_success

  for old in fixture-create fixture-load fixture-list fixture-prune; do
    assert_file_not_exist "${TESTDIR}/.ddev/commands/host/${old}"
  done

  # And the namespaced ones are what is there instead.
  for new in upkeep-fixture-create upkeep-fixture-load upkeep-fixture-list upkeep-fixture-prune; do
    assert_file_exist "${TESTDIR}/.ddev/commands/host/${new}"
  done
}

@test "a fixture-load belonging to somebody else is left alone" {
  # One of ours planted alongside, deliberately. Without it this test passes
  # whenever the cleanup does not run at all — which is exactly what happened
  # the first time: the action looked in the wrong directory, removed nothing,
  # reported success, and this assertion was satisfied by a cleanup that never
  # happened. A guard that misses looks identical to a file that was never
  # there, so the test has to prove the cleanup ran before it can prove the
  # cleanup was careful.
  mkdir -p "${TESTDIR}/.ddev/commands/host"
  write_old_command "fixture-list"

  cat > "${TESTDIR}/.ddev/commands/host/fixture-load" <<'EOF'
#!/usr/bin/env bash
## Description: not this add-on's command
echo "someone else's fixture-load"
EOF
  chmod +x "${TESTDIR}/.ddev/commands/host/fixture-load"

  run ddev add-on get "${DIR}"
  assert_success

  assert_file_not_exist "${TESTDIR}/.ddev/commands/host/fixture-list"

  assert_file_exist "${TESTDIR}/.ddev/commands/host/fixture-load"
  run cat "${TESTDIR}/.ddev/commands/host/fixture-load"
  assert_output --partial "someone else's fixture-load"
}
