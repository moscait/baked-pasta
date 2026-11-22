# Security Policy

## Reporting a vulnerability

Please report vulnerabilities **privately**, not in a public issue, discussion or pull request.

Use GitHub's private reporting form: open the repository's **Security** tab and choose
**Report a vulnerability**. Include:

- what is affected (a script, compose file, playbook, OpenTofu module or demo app) and the commit
- how to reproduce it, and what an attacker gains
- any suggested fix

You will get an acknowledgement within 7 days. This is a community project maintained on a
best-effort basis, so fix timelines depend on severity and maintainer availability. We will tell
you when a fix is published and credit you in the advisory unless you prefer otherwise.

## Scope

In scope: everything in this repository, including the deployment scripts, Ansible playbooks,
compose files, nginx configuration, OpenTofu modules and the demo applications.

Out of scope, please report upstream instead:

- OpenZiti itself (controller, router, SDKs, Admin Console): see the
  [OpenZiti security policy](https://github.com/openziti/ziti/security/policy).
- Cloudflare, Oracle Cloud and other third-party services.

## Supported versions

Only the latest commit on `main` is supported. There are no backported fixes.

## Deployment expectations

Both configurations run OpenZiti's single-node `quickstart` image with an automatically generated
PKI. They are meant for demos, evaluation and small self-hosted use, not highly available
production. Reports about that design choice itself are not vulnerabilities, but reports about
ways the defaults are weaker than this documentation claims are very welcome.
