# CLAUDE.md — ddev-upkeep

DDEV add-on providing named database fixtures (gzipped SQL dumps with
fast-restore materialized snapshots) for Drupal projects; the fixture layer
of the Upkeep orchestrator, also usable standalone. User docs: `README.md`.

## Layout

- `install.yaml` — add-on manifest: the files installed into a project's
  `.ddev/` (requires ddev >= 1.24.10).
- `commands/host/upkeep-fixture-{create,load,list,prune}` — the four host commands;
  thin argument parsing over the shared library.
- `upkeep/fixtures-lib.sh` — all shared logic: env overlay
  (`.ddev/.env.upkeep`, caller env wins), fixture-name validation, scope
  resolution (module `tests/fixtures/` first, then
  `UPKEEP_FIXTURE_LIBRARY` > `$UPKEEP_COCKPIT/fixtures` >
  `~/.upkeep/fixtures`), materialization/staleness (engine identity + dump
  checksum in `.ddev/upkeep/snapshots/<name>.meta`), sanitize-by-default for
  module destinations, 5 MB size warning (`UPKEEP_FIXTURE_SIZE_WARN_MB`).
- `docker-compose.upkeep.yaml` — the `upkeep` service
  (`UPKEEP_DOCKER_IMAGE`, default `ddev/ddev-utilities:latest`).
- `tests/*.bats` — bats suite; `docs/testing.md` explains coverage.
- `docs/manual-e2e-conditions-helper.md` — recorded end-to-end pass against
  a real module.

## Running tests

bats-core with bats-assert/bats-file/bats-support. No release exists yet, so
exclude release-tagged tests. If your `~/tmp` is not writable, use the
shim-HOME invocation (full explanation in `docs/testing.md`):

```bash
SHIM=~/.ddev-upkeep-test-home
mkdir -p "$SHIM/tmp"
for d in .ddev .docker .colima .gitconfig Library .ddev_mutagen_data_directory; do
  [ -e "$HOME/$d" ] && ln -sfn "$HOME/$d" "$SHIM/$d"
done
HOME="$SHIM" bats tests --filter-tags '!release'
```

Tests provision real ddev projects under `${HOME}/tmp` and delete them in
teardown; they never touch the real `~/.upkeep/fixtures` library.

## Conventions

- Every installed file keeps the `#ddev-generated` marker and the add-on
  template's header comment format (`## Description:` / `## Usage:` /
  `## Example:`).
- Dumps (`.sql.gz`) are the portable truth and are never deleted by any
  add-on command; materialized snapshots are disposable caches and must stay
  out of version control.
- Fixture dumps destined for a module repo are sanitized by default
  (`drush sql:sanitize`); do not weaken that default.
- POSIX-leaning bash, `set -eu -o pipefail`, shellcheck-clean.
