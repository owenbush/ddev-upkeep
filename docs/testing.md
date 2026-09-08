# Running the test suite

The suite uses [bats-core](https://bats-core.readthedocs.io/) with
bats-assert, bats-file and bats-support (`brew install bats-core bats-assert
bats-file bats-support`).

```bash
# No release exists yet, so exclude the release-tagged install test:
bats tests --filter-tags '!release'
```

Each test provisions a scratch ddev project under `${HOME}/tmp` (the upstream
template convention), installs the add-on from the working tree, and deletes
the project again in teardown. `UPKEEP_FIXTURE_LIBRARY` is pointed inside the
scratch dir, so runs never touch your real `~/.upkeep/fixtures` library.

## Local macOS quirk: `~/tmp` not writable

The harness hardcodes `${HOME}/tmp`. If your real `~/tmp` is not writable
(e.g. root-owned), run bats with a shim HOME that contains a writable `tmp/`
and symlinks to the dirs ddev and docker need:

```bash
SHIM=~/.ddev-upkeep-test-home
mkdir -p "$SHIM/tmp"
for d in .ddev .docker .colima .gitconfig Library .ddev_mutagen_data_directory; do
  [ -e "$HOME/$d" ] && ln -sfn "$HOME/$d" "$SHIM/$d"
done
HOME="$SHIM" bats tests --filter-tags '!release'
```

The `.ddev_mutagen_data_directory` symlink matters: without it, `ddev start`
under the shim HOME spawns a second mutagen daemon whose inherited file
descriptors keep bats hanging forever after the tests have finished.

The shim must live under your real `$HOME` when docker only mounts `$HOME`
(the Colima default), so that the scratch projects are mountable.

## What the files cover

- `test.bats` — upstream template smoke tests: add-on installs from the
  working tree (and, `release`-tagged, from the latest GitHub release).
- `fixtures-roundtrip.bats` — the core story: create a fixture, mutate the
  DB, load restores the fixture state, a second load restores via the
  materialized snapshot (fast path), `upkeep-fixture-list` reports it.
- `fixtures-resolution.bats` — module fixtures shadow same-named library
  fixtures; `upkeep-fixture-prune` removes only materialized snapshots (never
  dumps); module-destination `upkeep-fixture-create` sanitizes by default
  (`--no-sanitize` skips it); missing/unknown fixture names exit non-zero.

Sanitization is asserted via its failure mode in the bare scratch project
(no drush installed); the full `drush sql:sanitize` run is exercised by the
manual end-to-end pass recorded in `docs/manual-e2e-conditions-helper.md`.
