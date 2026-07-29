[![add-on registry](https://img.shields.io/badge/DDEV-Add--on_Registry-blue)](https://addons.ddev.com)
[![tests](https://github.com/owenbush/ddev-upkeep/actions/workflows/tests.yml/badge.svg?branch=main)](https://github.com/owenbush/ddev-upkeep/actions/workflows/tests.yml?query=branch%3Amain)
[![last commit](https://img.shields.io/github/last-commit/owenbush/ddev-upkeep)](https://github.com/owenbush/ddev-upkeep/commits)
[![release](https://img.shields.io/github/v/release/owenbush/ddev-upkeep)](https://github.com/owenbush/ddev-upkeep/releases/latest)

# DDEV Upkeep

## Overview

This add-on integrates Upkeep into your [DDEV](https://ddev.com/) project.

## Installation

```bash
ddev add-on get owenbush/ddev-upkeep
ddev restart
```

After installation, make sure to commit the `.ddev` directory to version control.

## Usage

| Command | Description |
| ------- | ----------- |
| `ddev fixture-create <name> [--dest=module\|library] [--no-sanitize]` | Dump the current DB to a portable fixture (`<name>.sql.gz`). Sanitizes via `drush sql:sanitize` by default when destined for the module repo. Warns when the dump exceeds 5 MB (`UPKEEP_FIXTURE_SIZE_WARN_MB`) |
| `ddev fixture-load <name>` | Load a fixture: first use imports the dump and materializes a snapshot; later loads restore the snapshot (fast path). Module `tests/fixtures/` shadows the shared library |
| `ddev fixture-list` | List fixtures in both scopes with size and snapshot state |
| `ddev fixture-prune` | Delete this project's disposable materialized snapshots (never the `.sql.gz` dumps) |
| `ddev describe` | View service status and used ports for Upkeep |
| `ddev logs -s upkeep` | Check Upkeep logs |

Fixtures resolve module-first: `tests/fixtures/<name>.sql.gz` in the module checkout, then the shared library (`UPKEEP_FIXTURE_LIBRARY`, defaulting to `$UPKEEP_COCKPIT/fixtures`, defaulting to `~/.upkeep/fixtures`).

## Advanced Customization

To change the Docker image:

```bash
ddev dotenv set .ddev/.env.upkeep --upkeep-docker-image="ddev/ddev-utilities:latest"
ddev add-on get owenbush/ddev-upkeep
ddev restart
```

Make sure to commit the `.ddev/.env.upkeep` file to version control.

All customization options (use with caution):

| Variable | Flag | Default |
| -------- | ---- | ------- |
| `UPKEEP_DOCKER_IMAGE` | `--upkeep-docker-image` | `ddev/ddev-utilities:latest` |
| `UPKEEP_FIXTURE_LIBRARY` | `--upkeep-fixture-library` | `$UPKEEP_COCKPIT/fixtures`, else `~/.upkeep/fixtures` |
| `UPKEEP_FIXTURE_SIZE_WARN_MB` | `--upkeep-fixture-size-warn-mb` | `5` |

## Credits

**Contributed and maintained by [@owenbush](https://github.com/owenbush)**
