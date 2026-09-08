# Manual end-to-end pass: conditions_helper (2026-07-30)

Verification of the add-on against a real maintained module, per the plan:
a fresh clone of <https://git.drupalcode.org/project/conditions_helper.git>
set up with [ddev-drupal-contrib](https://github.com/ddev/ddev-drupal-contrib)
version 1.1.5 following its README, plus this add-on installed from the
working tree.

Environment: macOS (arm64), ddev v1.25.1, Docker via Colima, mariadb 11.8.

> **The commands were renamed after this run.** What is transcribed below as
> `ddev fixture-create` / `-load` / `-list` / `-prune` is now
> `ddev upkeep-fixture-create` and so on. The transcript is left exactly as it
> was recorded — it is evidence of what happened on 2026-07-30, and editing a
> record of a real run to match later code is how a record stops being worth
> keeping. Everything it establishes about behaviour still holds.

## Setup

```console
$ git clone https://git.drupalcode.org/project/conditions_helper.git
$ cd conditions_helper
# Added "drush/drush": "^13" to require-dev by hand (per the
# ddev-drupal-contrib README, dev dependencies go in require-dev directly).
$ ddev config --project-name=upkeep-e2e-conditions-helper --project-type=drupal --docroot=web --php-version=8.3 --corepack-enable
$ ddev add-on get ddev/ddev-drupal-contrib --version 1.1.5
$ ddev add-on get /Users/owen/contrib/ddev-upkeep
$ ddev start -y
$ ddev poser
$ ddev symlink-project
$ ddev config --update
$ ddev restart
$ ddev drush site:install minimal -y --account-pass=admin
 [success] Installation complete.
$ ddev drush status --field=bootstrap
Successful
```

## Fixture cycle transcript

Verbatim (drush deprecation notices from the sanitize plugins elided for
brevity; every command exited 0):

```console
$ ddev fixture-create smoke
Destination is the module repo: sanitizing the database with 'drush sql:sanitize' (skip with --no-sanitize).
Note: this modifies the current project database.
 * Sanitize user passwords.
 * Sanitize user emails.
 * Preserve user emails and passwords for the specified roles.
 * Sanitize text fields associated with users.
 // Do you want to sanitize the current database?: yes.
 [success] User passwords sanitized.
 [success] User emails sanitized.
Exporting database to /Users/owen/.upkeep-task6-scratch/conditions_helper/tests/fixtures/smoke.sql.gz ...
Wrote database dump from project 'upkeep-e2e-conditions-helper' database 'db' to file .../tests/fixtures/smoke.sql.gz in gzip format.
Created fixture 'smoke' (module scope): .../tests/fixtures/smoke.sql.gz (116.5 KB)

$ ddev fixture-list
NAME                 SCOPE     SIZE       SNAPSHOT   NOTE
smoke                module    116.5 KB   no

Module fixtures:  /Users/owen/.upkeep-task6-scratch/conditions_helper/tests/fixtures
Fixture library:  /Users/owen/.upkeep/fixtures
Resolution order: module first, then library.

$ ddev drush sql:query "UPDATE config SET data='' WHERE name='system.site'"
$ ddev drush sql:query "SELECT name, LENGTH(data) FROM config WHERE name='system.site'"
system.site	0

$ ddev fixture-load smoke
Fixture 'smoke' (module scope): importing dump .../tests/fixtures/smoke.sql.gz ...
Successfully imported database 'db' for upkeep-e2e-conditions-helper
Loaded fixture 'smoke': imported dump and materialized snapshot in 2s (first-use path; subsequent loads restore the snapshot).

$ ddev drush sql:query "SELECT name, LENGTH(data) FROM config WHERE name='system.site'"
system.site	470

$ ddev drush sql:query "UPDATE config SET data='' WHERE name='system.site'"
$ ddev fixture-load smoke
Fixture 'smoke' (module scope): restoring from materialized snapshot ...
Loaded fixture 'smoke': restored from materialized snapshot in 1s (fast path).

$ ddev drush sql:query "SELECT name, LENGTH(data) FROM config WHERE name='system.site'"
system.site	470

$ ddev drush status --field=bootstrap
Successful

$ ddev fixture-prune
Removing materialized snapshot: .../.ddev/upkeep/materialized/smoke.sql
Removing snapshot metadata: .../.ddev/upkeep/snapshots/smoke.meta
Removed 1 materialized snapshot(s). Fixture dumps (.sql.gz) were not touched; the next 'ddev fixture-load' will rebuild snapshots from them.

$ ls tests/fixtures
smoke.sql.gz
```

## Observations

- Module-destination `fixture-create` ran `drush sql:sanitize` by default,
  and the dump landed in the module's `tests/fixtures/` (module scope).
- 116.5 KB dump — no size warning, correctly under the 5 MB threshold.
- The mutated `system.site` config row (blanked to length 0) was restored to
  its original 470 bytes by both the first-use path and the snapshot fast
  path; the site still fully bootstrapped afterwards.
- `fixture-prune` removed only the materialized artifact and its metadata;
  the committed-style dump under `tests/fixtures/` was untouched.
