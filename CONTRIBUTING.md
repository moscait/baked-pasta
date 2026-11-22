# Contributing to Baked Pasta

Thanks for your interest in improving Baked Pasta. Bug reports, documentation fixes and pull
requests are all welcome.

By participating you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md). Security
problems go through the private process in [SECURITY.md](SECURITY.md), never a public issue.

## Before you start

- **Small fixes** (typos, docs, obvious bugs): open a pull request directly.
- **Larger changes** (new configurations, new services, changes to the security model): open an
  issue first so we can agree on the approach before you spend time on it.

## Repository layout

| Path | What it is |
|---|---|
| `docker-compose.yaml`, `menu/` | Configuration 1: the all-local sandbox |
| `deploy-ziti.sh`, `infrastructure/` | Configuration 2: routable infrastructure (Ansible, compose template, nginx, OpenTofu) |
| `app/`, `zt-app/` | Demo applications (Spring Boot; `zt-app` embeds the OpenZiti Java SDK) |
| `scripts/` | Admin Console fetch/build, logo and diagram generators, console demo recorder |
| `docs/DECISIONS.md` | Decision log: why things are the way they are. Add an entry when you make a choice a future reader would have to rediscover |

## Development setup

You need Docker (or Podman), GNU Make, `curl` and `unzip`. For the demo apps you need Java 25
(`app/`) and Java 21 or later (`zt-app/`); the Maven wrapper downloads Maven itself.

```bash
make sandbox-up          # fetches the Admin Console, generates .env, starts the sandbox
make sandbox-status
make sandbox-down
```

The OpenZiti Admin Console is build output and is not committed. `scripts/fetch-console.sh`
downloads a pinned build and verifies its SHA-256; `scripts/build-console.sh` builds one from
source. See [infrastructure/README.md](infrastructure/README.md#-updating-or-customizing-the-admin-console).

## Checks to run before opening a pull request

CI runs the same checks (`.github/workflows/ci.yml`):

```bash
(cd app && ./mvnw verify)
(cd zt-app && ./mvnw verify)
shellcheck -S warning deploy-ziti.sh infrastructure/deploy.sh scripts/*.sh scripts/console-demo/*.sh
OPENZITI_ADMIN_PASSWORD=x docker compose config --quiet
python3 scripts/diagrams/build_diagrams.py && git diff --exit-code assets/diagrams/
```

If you change an architecture diagram, edit `scripts/diagrams/build_diagrams.py` and regenerate
the SVGs; don't edit the SVGs by hand.

## Conventions

- **Commits** follow [Conventional Commits](https://www.conventionalcommits.org/): `feat:`, `fix:`,
  `docs:`, `chore:`, `ci:`, `refactor:`.
- **Pin what you consume.** Container images are pinned by tag *and* digest, GitHub Actions by
  commit SHA (with the version in a comment), downloads by SHA-256. Dependabot proposes updates.
- **Secrets never touch the command line or the repository.** Read them from the environment, pass
  them over stdin, and write them to `0600` files. Check `.gitignore` before adding new
  credential-bearing files.
- **Keep the two infrastructure compose files in sync.** `infrastructure/templates/docker-compose.yaml.j2`
  (used by Ansible) and `infrastructure/docker-compose.cloudflare.yaml` (manual `make ziti-up`)
  describe the same stack; a change to one almost always belongs in the other.
- **Shell scripts** use `set -euo pipefail`, quote expansions and pass `shellcheck -S warning`.

## Releasing (maintainers)

Demo images are published to GHCR by `.github/workflows/docker-publish.yml` after CI passes.
Pushes to `main` publish `:main` and `:sha-<commit>`. To cut a versioned release:

1. Tag the commit: `git tag -a v1.2.3 -m "v1.2.3" && git push origin v1.2.3`. This publishes
   `:1.2.3` and `:1.2`.
2. Point `docker-compose.yaml` at the new tag (`ghcr.io/moscait/baked-pasta-demo-app:1.2.3`, and
   the same for `baked-pasta-demo-zt-app`) in a follow-up pull request.

## License

By contributing you agree that your contributions are licensed under the
[Apache License 2.0](LICENSE), the same license as the project.
