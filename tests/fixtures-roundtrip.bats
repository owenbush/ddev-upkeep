#!/usr/bin/env bats

# Integration test for the fixture round-trip story:
# create -> mutate -> load restores state -> second load takes the snapshot
# fast path. Runs against a bare ddev project (no Drupal needed): the
# round-trip is about the database, not the site.

load 'helpers'

setup() {
  upkeep_test_setup
}

teardown() {
  upkeep_test_teardown
}

@test "fixture round-trip: create, mutate, load restores, second load uses the snapshot" {
  set -eu -o pipefail

  # Seed a recognizable database state.
  upkeep_sql "CREATE TABLE upkeep_probe (id INT PRIMARY KEY, marker VARCHAR(64)); INSERT INTO upkeep_probe VALUES (1, 'val-original');"

  # Create the fixture. Bare project => library destination.
  run ddev fixture-create smoke
  assert_success
  assert_output --partial "Created fixture 'smoke' (library scope)"
  assert_file_exist "${UPKEEP_FIXTURE_LIBRARY}/smoke.sql.gz"
  # Not a module destination: no sanitize step must run.
  refute_output --partial "sanitizing"

  # Mutate the database away from the fixture state.
  upkeep_sql "UPDATE upkeep_probe SET marker='val-mutated' WHERE id=1;"
  run upkeep_sql "SELECT marker FROM upkeep_probe WHERE id=1;"
  assert_output --partial "val-mutated"

  # First load: imports the dump and materializes the snapshot artifact.
  run ddev fixture-load smoke
  assert_success
  assert_output --partial "(first-use path"
  assert_file_exist "${TESTDIR}/.ddev/upkeep/materialized/smoke.sql"
  assert_file_exist "${TESTDIR}/.ddev/upkeep/snapshots/smoke.meta"
  run upkeep_sql "SELECT marker FROM upkeep_probe WHERE id=1;"
  assert_output --partial "val-original"

  # Mutate again; the second load must restore via the materialized snapshot.
  upkeep_sql "UPDATE upkeep_probe SET marker='val-mutated-again' WHERE id=1;"
  run ddev fixture-load smoke
  assert_success
  assert_output --partial "(fast path)"
  refute_output --partial "(first-use path"
  run upkeep_sql "SELECT marker FROM upkeep_probe WHERE id=1;"
  assert_output --partial "val-original"

  # fixture-list reports the fixture with its materialized snapshot.
  run ddev fixture-list
  assert_success
  assert_output --regexp "smoke +library +[0-9.]+ [KM]?B +yes"
}
