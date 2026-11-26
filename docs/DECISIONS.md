# Decision Log

This file records why Baked Pasta is built the way it is: the choices that are not obvious from
the code, what was considered, and what was verified at the time. The repository was published
with a fresh history (D-16), so this log, not `git log`, is where the reasoning from before the
first public commit lives.

Many of these decisions rest on facts that change quickly: library compatibility, platform
limits, free-tier quotas, and what tooling (including AI coding tools) can do. Each entry therefore
ends with **Revisit when**: the condition that should prompt someone to check whether it still
holds.

**Keeping it current**

- Add an entry when you make a choice that a future reader would otherwise have to rediscover.
- Don't rewrite history. When a decision changes, mark the old entry `Superseded by D-NN` and add
  a new one. Small corrections (a version number, a link) can be edited in place.
- Record what you verified and how, so the next person can re-run the check instead of trusting it.

| ID | Decision | Status |
|---|---|---|
| [D-01](#d-01-two-configurations-local-sandbox-and-routable-infrastructure) | Two configurations: local sandbox and routable infrastructure | Accepted |
| [D-02](#d-02-no-inbound-web-ports-cloudflare-tunnel-and-access-in-front-of-the-console) | No inbound web ports; Cloudflare Tunnel and Access in front of the console | Accepted |
| [D-03](#d-03-oracle-cloud-always-free-as-the-reference-host) | Oracle Cloud Always Free as the reference host | Accepted |
| [D-04](#d-04-the-admin-console-is-downloaded-and-checksum-verified-not-committed) | The Admin Console is downloaded and checksum-verified, not committed | Accepted |
| [D-05](#d-05-ssh-deploys-ship-an-allowlist-of-files) | SSH deploys ship an allowlist of files | Accepted |
| [D-06](#d-06-the-admin-password-is-passed-only-to-the-first-boot-bootstrap) | The admin password is passed only to the first-boot bootstrap | Accepted |
| [D-07](#d-07-pin-everything-let-dependabot-propose-updates) | Pin everything; let Dependabot propose updates | Accepted |
| [D-08](#d-08-zt-app-uses-spring-boot-4-and-its-own-ziti-bridge) | zt-app uses Spring Boot 4 and its own Ziti bridge | Accepted |
| [D-09](#d-09-kotlin-and-coroutines-are-pinned-to-the-openziti-sdks-versions) | Kotlin and coroutines are pinned to the OpenZiti SDK's versions | Accepted |
| [D-10](#d-10-each-app-stays-on-a-java-lts-line-and-builds-with-its-maven-wrapper) | Each app stays on a Java LTS line and builds with its Maven wrapper | Accepted |
| [D-11](#d-11-stay-on-the-cloudflare-opentofu-provider-v4) | Stay on the Cloudflare OpenTofu provider v4 | Accepted |
| [D-12](#d-12-images-are-published-only-after-ci-tags-come-from-git) | Images are published only after CI; tags come from git | Accepted |
| [D-13](#d-13-multi-platform-images-build-on-native-runners) | Multi-platform images build on native runners | Accepted |
| [D-14](#d-14-diagrams-are-generated-svgs-with-light-and-dark-variants) | Diagrams are generated SVGs with light and dark variants | Accepted |
| [D-15](#d-15-private-reporting-channels-go-through-github) | Private reporting channels go through GitHub | Accepted |
| [D-16](#d-16-publish-with-a-fresh-repository-and-a-single-initial-commit) | Publish with a fresh repository and a single initial commit | Accepted |
| [D-17](#d-17-the-admin-console-is-selectable-zac-or-bpc) | The admin console is selectable: ZAC or BPC | Accepted |

---

## D-01: Two configurations, local sandbox and routable infrastructure

*Status: Accepted. Predates this log.*

**Context.** A single laptop stack is the fastest way to learn OpenZiti, but phones, cloud
workloads and remote colleagues cannot reach containers on a laptop's Docker network.

**Decision.** Ship two configurations. Configuration 1 runs everything in local containers with
`*.local` names on loopback. Configuration 2 runs the controller and edge router on a Linux host
that remote clients can reach, while the demo apps can stay on the workstation.

**Consequences.** Two compose stacks (`docker-compose.yaml` and the Ansible-rendered
`infrastructure/templates/docker-compose.yaml.j2`) must be kept in step when OpenZiti changes.

**Revisit when** OpenZiti's own quickstart covers the routable case well enough that the second
stack stops adding value.

## D-02: No inbound web ports; Cloudflare Tunnel and Access in front of the console

*Status: Accepted. Predates this log.*

**Context.** The Admin Console is a powerful web UI. Exposing it, or the controller's management
API, to the internet invites scanning and credential attacks.

**Decision.**

- The console is reachable only through an outbound Cloudflare Tunnel, gated by Cloudflare Access
  (SSO or email one-time code). nginx listens on `127.0.0.1:8080` as the tunnel's origin.
- The management API (1281) stays on the internal container network.
- Only the OpenZiti mTLS ports are public, on a DNS-only hostname: 1280 (client API, enrollment)
  and 8444 (edge router data plane). A small DDNS container keeps that record current.

**Consequences.** Depends on a Cloudflare account and domain (a quick-tunnel mode exists for
trials). The mTLS ports cannot go through the Cloudflare proxy, so that hostname exposes the
host's IP.

**Revisit when** OpenZiti can serve its own console over the overlay in a way that is easy to
demo, or Cloudflare's free tier changes what Tunnel and Access provide.

## D-03: Oracle Cloud Always Free as the reference host

*Status: Accepted. Predates this log.*

**Context.** Configuration 2 needs an always-on Linux host with a public IP, and a demo project
should cost nothing to run.

**Decision.** Provide an OpenTofu module for an OCI Ampere A1 instance (1 OCPU / 6 GB by default)
with a reserved IP, within the Always Free allowance. Ubuntu is the default; Oracle Linux (Podman,
firewalld, SELinux enforcing) is supported for a RHEL-family option. Any Fedora/Ubuntu host works
with `deploy-ziti.sh`; OCI is just the documented path.

**Consequences.** A1 capacity is often scarce in busy regions, and Oracle may reclaim idle
Always Free instances.

**Revisit when** Oracle changes the Always Free terms, or another provider offers a comparable
free tier.

## D-04: The Admin Console is downloaded and checksum-verified, not committed

*Status: Accepted 2026-11-20.*

**Context.** Two console builds (about 49 MB of build output) were committed: the stock upstream
release for the sandbox, and a build with the Access Canvas view for deployments. Build output in
git bloats every clone and can't be reviewed.

**Decision.** `scripts/fetch-console.sh` downloads a pinned zip and verifies its SHA-256 before
installing it:

- Sandbox (`menu/zac/`): upstream `ziti-console` release `app-ziti-console-v4.8.0`.
- Deployments (`infrastructure/console/`): the Access Canvas build `4.8.1-access-canvas-35f72f9`,
  published as a release asset of this repository (tag `console-4.8.1-access-canvas-35f72f9`).

`make sandbox-up` and `deploy-ziti.sh` fetch it when it is missing. A console built locally with
`scripts/build-console.sh` is kept unless `--force` is passed. Both directories are git-ignored.
`NOTICE` records the sources and checksums.

**Consequences.** First runs need network access to GitHub releases. The deployment console
depends on this repository's release asset staying in place: deleting or re-tagging that release
breaks deploys. Updating the console means building, uploading a new asset under a new tag, and
updating the URL and checksum in the script and `NOTICE`.

**Revisit when** the Access Canvas view ships in an upstream console release (then both
configurations can use upstream), or the console gets an official container image.

## D-05: SSH deploys ship an allowlist of files

*Status: Accepted 2026-11-20.*

**Context.** `deploy-ziti.sh --ssh` used to tar the whole `infrastructure/` directory from the
working tree. That sent git-ignored OpenTofu state, `terraform.tfvars` and provider binaries
(274 MB or more) to the target host, including tenancy details.

**Decision.** The bundle is an explicit allowlist of what the remote run reads: `deploy-ziti.sh`,
`infrastructure/ansible`, `infrastructure/templates`, `infrastructure/nginx`, and
`infrastructure/console` when deploying. The result was about 6 MB with no state files.
`infrastructure/deploy.sh` is now a thin wrapper around `deploy-ziti.sh` instead of a drifting
copy.

**Consequences.** A new file the remote side needs must be added to `BUNDLE_PATHS`, or the deploy
fails on the host.

**Revisit when** the deploy moves to a different transport (for example, Ansible pulling from a
release).

## D-06: The admin password is passed only to the first-boot bootstrap

*Status: Accepted 2026-11-20.*

**Context.** The OpenZiti quickstart (2.0.8) accepts the admin password only as a command-line
argument; it ignores the `ZITI_PWD` environment variable. A long-running controller started with
`--password` exposes it to every user on the host through `ps` and `/proc`.

**What was verified.** In a test, the password is needed only when the quickstart initializes the
controller. After initialization, the controller restarts without it, the original password still
logs in, and `admin/admin` is rejected.

**Decision.** Both compose stacks pass `--password` only on first boot, when no router certificate
exists yet. Every later start runs without it. The infrastructure stack exits with an error if the
bootstrap did not finish, so the admin user is never created with the quickstart's default
password. `ziti edge login` still takes the password as `-p`; that is a short-lived process inside
the container.

**Consequences.** The first boot still has the password in argv for a short time.

**Revisit when** the quickstart reads the password from an environment variable or file. Re-check
by starting a fresh controller without `--password` and confirming which password it sets.

## D-07: Pin everything; let Dependabot propose updates

*Status: Accepted 2026-11-20.*

**Context.** Floating tags (`latest`, `ZITI_VERSION=latest`, unbounded provider versions) make
builds unreproducible and let a compromised upstream tag reach users silently.

**Decision.**

- Container images are pinned by tag and digest, in compose files, Ansible vars and Dockerfiles.
- GitHub Actions are pinned by commit SHA, with the version in a comment.
- OpenTofu providers have bounded constraints and committed `.terraform.lock.hcl` files with
  checksums for five platforms (OpenTofu 1.13.8).
- Maven runs through the checked-in wrapper; downloaded artifacts have SHA-256 checks.
- Dependabot (`.github/dependabot.yml`) proposes weekly updates for all of these.

Dependabot PRs are reviewed, not auto-merged. When one is declined, add an `ignore` rule with a
comment saying why, so it doesn't return every week.

**Consequences.** Updating means changing a digest or SHA, which Dependabot does. A value pinned
in two places (for example the cloudflared image in the compose file and in
`infrastructure/ansible/vars/main.yml`) may only be bumped in one of them; check for duplicates
when accepting.

**Revisit when** Dependabot (or a successor) can be trusted to auto-merge patch updates after CI,
which would remove most of the review work.

## D-08: zt-app uses Spring Boot 4 and its own Ziti bridge

*Status: Accepted 2026-11-20.*

**Context.** zt-app was on Spring Boot 3.5, which is out of support. Its OpenZiti SDK (0.30.0)
could not talk to the 2.0.8 controller ("No enum constant ... OIDC_AUTH_WITH_CSR"), so the
dark-service demo never started. The `ziti-springboot` adapter targets Tomcat 10. Spring Boot 4
ships Tomcat 11, which removed `AbstractHttp11JsseProtocol`, so the adapter cannot load.

**Decision.** Move to Spring Boot 4.1 (matching `app/`). Replace `ziti-springboot` with
`ZitiServiceBridge`: a small component that binds the Ziti service with the core SDK and forwards
each overlay connection to Tomcat. Tomcat listens on `127.0.0.1` only, so the app is reachable
only through the overlay.

**What was verified.** In a sandbox test, a client identity reached `/hello` through
`ziti tunnel proxy`, and a direct connection from the container network was refused. This was
re-run after the SDK 0.36.0 update.

**Consequences.** The project now owns a small piece of networking code (accept loop, two-way
copy, shutdown) instead of an upstream adapter.

**Revisit when** OpenZiti publishes a Spring Boot 4 / Tomcat 11 integration. If it does, prefer it
and delete the bridge.

## D-09: Kotlin and coroutines are pinned to the OpenZiti SDK's versions

*Status: Accepted 2026-11-20.*

**Context.** The OpenZiti Java SDK is written in Kotlin. Spring Boot's dependency management
downgrades Kotlin to the version Boot manages (2.3.21 in Boot 4.1.2). With SDK 0.35.0 that failed
at runtime with `ClassNotFoundException: kotlin.coroutines.jvm.internal.SpillingKt`.

**Decision.** `zt-app/pom.xml` sets `kotlin.version` and `kotlin-coroutines.version` to the
versions in the SDK's own pom. For SDK 0.36.0 those are Kotlin 2.4.21 and coroutines 1.11.0.

**Consequences.** Every SDK bump must check its pom and update these properties. Dependabot does
not do this; it bumps only `openziti.version`.

**Revisit when** Spring Boot manages a Kotlin version at least as new as the SDK needs, or the SDK
shades its Kotlin runtime.

## D-10: Each app stays on a Java LTS line and builds with its Maven wrapper

*Status: Accepted 2026-11-20.*

**Context.** Dependabot proposed Java 24 images for zt-app. Java 24 is not a long-term-support
release. zt-app also built with a `maven:*-amazoncorretto-21` image, whose tag scheme Dependabot
misread (it proposed `3-amazoncorretto-24`).

**Decision.** `app` runs on Java 25 and `zt-app` on Java 21, both LTS, and each image matches the
pom's `java.version`. Both Dockerfiles build on Eclipse Temurin JDK images with the project's
Maven wrapper, so images build with the same Maven version as CI. Dependabot ignores major
Temurin updates, so it still proposes security patches.

**Consequences.** Moving to another LTS is a deliberate change to the pom, the Dockerfile and CI's
`setup-java` together.

**Revisit when** zt-app has a reason to move to Java 25 (nothing blocks it; it was not needed), or
the next LTS (Java 29, expected September 2027) is out.

## D-11: Stay on the Cloudflare OpenTofu provider v4

*Status: Accepted 2026-11-20.*

**Context.** Dependabot proposed `~> 5.29`. Provider v5 renames and reshapes most resources, so
upgrading is a configuration and state migration, not a version bump.

**Decision.** Keep `~> 4.x`; Dependabot ignores `cloudflare/cloudflare` versions 5 and later.
(An ignore rule for major updates was not enough: Dependabot proposed widening the requirement
to `~> 5.29`, which it does not classify as a major update.)

**Consequences.** v4 will eventually stop receiving fixes.

**Revisit when** Cloudflare announces v4's end of support, or a feature the project needs exists
only in v5. Plan the migration with `tofu plan` against a test zone.

## D-12: Images are published only after CI; tags come from git

*Status: Accepted 2026-11-20.*

**Context.** The publish workflow pushed images without running tests, and the version (1.0.2) and
`latest` were hard-coded in the workflow.

**Decision.** `ci.yml` runs Maven tests for both apps, ShellCheck, compose validation and a
diagram-freshness check, on pull requests and on `main`. `docker-publish.yml` calls it first.
Tags come from git: pushes to `main` publish `:main` and `:sha-<commit>`; a `vX.Y.Z` tag publishes
`:X.Y.Z`, `:X.Y` and `:sha-<commit>`. There is no `latest`. The sandbox compose file references a
released version, bumped after each release (see CONTRIBUTING.md, "Releasing").

**Consequences.** Releasing is "push a tag, then bump the compose file", two steps someone has to
remember.

**Revisit when** the release process grows (changelog generation, signed images, SBOMs); consider
release tooling then.

## D-13: Multi-platform images build on native runners

*Status: Accepted 2026-11-20.*

**Context.** Building arm64 under QEMU emulation took about 8 minutes for the app image alone.
GitHub offers native arm64 Linux runners.

**Decision.** Follow Docker's documented pattern for distributing a build across runners: each
image builds for `linux/amd64` on `ubuntu-24.04` and `linux/arm64` on `ubuntu-24.04-arm`, pushes by
digest, and a merge job creates one multi-platform manifest per image. Each leg has its own GitHub
Actions build cache. A publish takes about 2 minutes.

Digests pass between jobs as job outputs, not artifacts. Private repositories on the free plan
share 500 MB of Actions and Packages storage across the organization, other repositories had used
it up, and the artifact upload failed.

**Consequences.** The four job-output names are spelled out in the workflow; adding an app or a
platform means adding outputs.

**Revisit when** the storage quota stops being a constraint (for example, the repository is public
or the plan changes); artifacts are the more common pattern and scale without editing outputs.

## D-14: Diagrams are generated SVGs with light and dark variants

*Status: Accepted 2026-11-20.*

**Context.** The READMEs used ASCII diagrams, which render poorly in proportional fonts and on
phones.

**Decision.** `scripts/diagrams/build_diagrams.py` generates self-contained SVGs (no web fonts or
external references) into `assets/diagrams/`, each in a light and an `-on-dark` variant. The docs
show them with `<picture>` and `prefers-color-scheme`, which GitHub supports. CI fails if the
committed SVGs differ from the generator's output. The logo is generated the same way by
`scripts/logo/build_logo.py`.

**Consequences.** Diagram changes are code changes: edit the generator, run it, commit both.

**Revisit when** GitHub renders a diagram format (Mermaid or similar) that looks as good and themes
itself; generated text would then be easier to maintain.

## D-15: Private reporting channels go through GitHub

*Status: Accepted 2026-11-20.*

**Context.** SECURITY.md and the Code of Conduct need a private contact, and the project has no
dedicated mailbox.

**Decision.** Vulnerabilities are reported through GitHub's private vulnerability reporting
(Security tab). Conduct reports use the same form with a title starting "Conduct report", or
GitHub's report-abuse feature.

**Consequences.** Private vulnerability reporting must be enabled in the repository settings; it
is unavailable while the repository is private.

**Revisit when** the project gets a maintainer team or a dedicated contact address.

## D-16: Publish with a fresh repository and a single initial commit

*Status: Accepted 2026-11-21.*

**Context.** Before going public, the console build output was removed from the history with a
rewrite. GitHub keeps pull-request refs and the unreachable commits they point to, so the old
history (and closed Dependabot PRs against it) would stay visible in the original repository.

**Decision.** Publish from a new repository whose history starts with one commit containing the
current tree. The reasoning that lived in commit messages is captured in this log. The previous
private repository is kept as a backup and not published.

**Consequences.** `git blame` starts at the initial commit, so this file is the record for
anything decided before it. The releases were recreated in the new repository under the same
tags: v1.0.3, and the console asset whose download URL `scripts/fetch-console.sh` pins (same
file, same SHA-256).

**Going forward.** This was a one-time step. From here on, history is kept and not rewritten.

## D-17: The admin console is selectable: ZAC or BPC

*Status: Accepted 2026-11-20. Updated 2026-11-26: BPC v0.1.0 is pinned.*

**Context.** The Access Canvas started as a modification of ZAC (D-04). It is now growing into
its own console, the Baked Pasta Console (BPC): a separate React project that speaks the same
controller API (`/edge/management/v1`, with OIDC and password login) and is built for the same
`/zac/` path. BPC is not finished and has no published release yet.

**Decision.** Keep ZAC as the default and add BPC as an option in both configurations, selected
with `CONSOLE=bpc` (make), `--console bpc` (`deploy-ziti.sh`, `scripts/fetch-console.sh`) or
`BAKED_PASTA_CONSOLE=bpc`. BPC is installed into the same directory and served at the same
URLs as ZAC, so nginx, Ansible and the compose files don't change. Until BPC is released it is
built from a local checkout (`BPC_DIR`) or installed from an archive (`BPC_ZIP`). Each install
writes `.console-source`, so switching consoles replaces the installed one, while a custom ZAC
build is still never overwritten without `--force`. The sandbox nginx gained a fallback to
`index.html` under `/zac/`, because BPC uses path-based routes and a reload on, for example,
`/zac/identities` would otherwise return 404.

**What was verified.** In a sandbox test with a local BPC build, served through the portal's
nginx:

- Deep links reload, and the assets load.
- Login works against the 2.0.8 controller. BPC tries OIDC first; `/oidc` is not proxied, so it
  gets a 404 and falls back to password login.
- The live services and policies load.

The infrastructure nginx config served the same build at `/` and `/zac/`.

**Consequences.** A BPC install from `BPC_DIR` or `BPC_ZIP` is not checksum-pinned; the
`.console-source` file records what was installed. The console choice is per run: running
again without `CONSOLE=bpc` switches back to ZAC, unless `BAKED_PASTA_CONSOLE` is set.

**Update 2026-11-26.** BPC now publishes releases from a tag-triggered workflow in its own
repository. `scripts/fetch-console.sh` pins v0.1.0 (`ziti-console.zip`, SHA-256 `197b8028...`),
verified like ZAC, so `CONSOLE=bpc` needs no checkout; `BPC_DIR` and `BPC_ZIP` remain for
unreleased work. Pinned installs record their checksum (`pin=` in `.console-source`), so
bumping a pin replaces the installed console on the next run, while local builds, archives
and custom ZAC builds are still kept without `--force`. Verified: the v0.1.0 asset downloaded
anonymously matches GitHub's digest; in the sandbox, headless Chrome reached the login page on
the first visit, signed in, and loaded the canvas and the services, identities, policies and
routers pages with live data. It was then deployed to a routable host.

**Update 2026-11-26 (later).** Pinned BPC v0.1.1 (commit `0fc12fc`, SHA-256 `0da65198...`),
which shows the console version on the login screen and in the sidebar. It was the first
upgrade through the pin check: the deploy replaced v0.1.0 without `--force`.

**Update 2026-11-26 (pin helper).** `make bpc-pin [VERSION=vX.Y.Z]` (`scripts/pin-bpc.sh`,
default `latest`) moves the pin: it looks the release up on GitHub, downloads the asset, checks
it against the SHA-256 GitHub records for it, and rewrites the pin in `scripts/fetch-console.sh`,
`NOTICE` and the README. Deploying stays a separate step, so the repository always records what
is deployed and a new BPC release reaches a host only after someone pins and commits it. An
option to install "latest" at deploy time was considered and rejected for that reason.

**Revisit when** BPC is ready to be the default (then consider whether the modified ZAC build in
D-04 is still needed).
