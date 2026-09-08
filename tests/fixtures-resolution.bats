#!/usr/bin/env bats

# Integration tests for fixture resolution order, prune safety, the
# sanitize-by-default rule for module destinations, and error exits.
#
# Module scope is activated the same way the add-on detects it: a *.info.yml
# file at the project root (the ddev-drupal-contrib layout). No Drupal install
# is needed for these paths; the sanitize-by-default assertion covers the
# attempt (drush is absent in the bare project, so the default create fails
# loudly while --no-sanitize succeeds). The full drush sql:sanitize run is
# covered by the manual end-to-end pass documented in docs/.

load 'helpers'

setup() {
  upkeep_test_setup
}

teardown() {
  upkeep_test_teardown
}

@test "module fixture shadows library fixture; prune removes only materialized snapshots" {
  set -eu -o pipefail

  # Make the project look like a module checkout.
  touch "${TESTDIR}/upkeep_probe.info.yml"
  mkdir -p "${TESTDIR}/tests/fixtures"

  # Same-named fixture in both scopes, with distinguishable content.
  upkeep_sql "CREATE TABLE upkeep_probe (id INT PRIMARY KEY, marker VARCHAR(64)); INSERT INTO upkeep_probe VALUES (1, 'from-library');"
  run ddev upkeep-fixture-create dual --dest=library
  assert_success
  upkeep_sql "UPDATE upkeep_probe SET marker='from-module' WHERE id=1;"
  run ddev upkeep-fixture-create dual --dest=module --no-sanitize
  assert_success
  assert_file_exist "${TESTDIR}/tests/fixtures/dual.sql.gz"
  assert_file_exist "${UPKEEP_FIXTURE_LIBRARY}/dual.sql.gz"

  # Load must resolve the module fixture, shadowing the library one.
  upkeep_sql "UPDATE upkeep_probe SET marker='scribbled' WHERE id=1;"
  run ddev upkeep-fixture-load dual
  assert_success
  assert_output --partial "'dual' (module scope)"
  run upkeep_sql "SELECT marker FROM upkeep_probe WHERE id=1;"
  assert_output --partial "from-module"

  # upkeep-fixture-list labels both scopes and marks the shadowed library copy.
  run ddev upkeep-fixture-list
  assert_success
  assert_output --regexp "dual +module"
  assert_output --regexp "dual +library +.*shadowed by module fixture"

  # Prune removes the materialized snapshot + metadata, never the dumps.
  assert_file_exist "${TESTDIR}/.ddev/upkeep/materialized/dual.sql"
  run ddev upkeep-fixture-prune
  assert_success
  assert_output --partial "Removing materialized snapshot"
  assert_file_not_exist "${TESTDIR}/.ddev/upkeep/materialized/dual.sql"
  assert_file_not_exist "${TESTDIR}/.ddev/upkeep/snapshots/dual.meta"
  assert_file_exist "${TESTDIR}/tests/fixtures/dual.sql.gz"
  assert_file_exist "${UPKEEP_FIXTURE_LIBRARY}/dual.sql.gz"

  # A pruned fixture is still loadable from its dump (rebuilds the snapshot).
  run ddev upkeep-fixture-load dual
  assert_success
  assert_output --partial "(first-use path"
}

@test "sanitize-by-default for module destinations; missing or unknown fixture exits non-zero" {
  set -eu -o pipefail

  touch "${TESTDIR}/upkeep_probe.info.yml"

  # Default module-destination create must attempt drush sql:sanitize.
  # This bare project has no drush, so the attempt fails loudly — proving the
  # sanitize step runs by default and that its failure aborts the create.
  run ddev upkeep-fixture-create sanitized --dest=module
  assert_failure
  assert_output --partial "sanitizing the database with 'drush sql:sanitize'"
  assert_output --partial "'drush sql:sanitize' failed"
  assert_file_not_exist "${TESTDIR}/tests/fixtures/sanitized.sql.gz"

  # --no-sanitize skips the sanitize step entirely and succeeds without drush.
  run ddev upkeep-fixture-create sanitized --dest=module --no-sanitize
  assert_success
  refute_output --partial "sanitizing"
  assert_file_exist "${TESTDIR}/tests/fixtures/sanitized.sql.gz"

  # Missing fixture name exits non-zero with a clear message.
  run ddev upkeep-fixture-load
  assert_failure
  assert_output --partial "Missing fixture name"

  run ddev upkeep-fixture-create
  assert_failure
  assert_output --partial "Missing fixture name"

  # Unknown fixture name exits non-zero and says where it looked.
  run ddev upkeep-fixture-load no-such-fixture
  assert_failure
  assert_output --partial "Fixture 'no-such-fixture' not found"
}
