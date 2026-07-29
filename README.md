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
| `ddev describe` | View service status and used ports for Upkeep |
| `ddev logs -s upkeep` | Check Upkeep logs |

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

## Credits

**Contributed and maintained by [@owenbush](https://github.com/owenbush)**
