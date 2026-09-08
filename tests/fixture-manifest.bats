#!/usr/bin/env bats

# The sidecar that makes a dump mean something.
#
# A dump encodes references to code — enabled extensions, plugin IDs in config,
# field types — and captures none of it. Loaded into a codebase that does not
# provide that code, Drupal cannot build a container, and the failure lands in
# whatever ran next, blaming the wrong thing. So a fixture carries a manifest
# of what it needs, and loading satisfies it or refuses before touching the
# database.
#
# The project here is a bare ddev project with no Drupal, so what these can
# reach is the manifest's own machinery: that create writes one, and that load
# reads it and refuses on a requirement it cannot meet. The core-version
# mismatch needs a working `drush status` and is covered by the shell-level
# harness instead.

load helpers

setup() {
  upkeep_test_setup
}

teardown() {
  upkeep_test_teardown
}

@test "creating a fixture writes a manifest beside the dump" {
  run ddev upkeep-fixture-create smoke --dest=library
  assert_success

  assert_file_exist "${UPKEEP_FIXTURE_LIBRARY}/smoke.sql.gz"
  assert_file_exist "${UPKEEP_FIXTURE_LIBRARY}/smoke.yml"

  run cat "${UPKEEP_FIXTURE_LIBRARY}/smoke.yml"
  assert_success
  assert_output --partial "db_engine:"
  assert_output --partial "created_at:"
  assert_output --partial "upkeep-fixture-create"
}

@test "a dump with no manifest loads exactly as it always did" {
  run ddev upkeep-fixture-create bare --dest=library
  assert_success
  rm -f "${UPKEEP_FIXTURE_LIBRARY}/bare.yml"

  run ddev upkeep-fixture-load bare
  assert_success
}

@test "an extension the codebase does not have refuses before the import" {
  run ddev upkeep-fixture-create needy --dest=library
  assert_success

  cat > "${UPKEEP_FIXTURE_LIBRARY}/needy.yml" <<'EOF'
db_engine: 'unused'
extensions:
  - a_module_that_is_not_here
EOF

  run ddev upkeep-fixture-load needy
  assert_failure
  assert_output --partial "a_module_that_is_not_here"
  assert_output --partial "not in this codebase"
}

@test "a manifest carrying nothing actionable does not block the load" {
  run ddev upkeep-fixture-create quiet --dest=library
  assert_success

  cat > "${UPKEEP_FIXTURE_LIBRARY}/quiet.yml" <<'EOF'
# nothing this project has to satisfy
db_engine: 'unused'
created_at: '2026-01-01T00:00:00Z'
EOF

  run ddev upkeep-fixture-load quiet
  assert_success
}
