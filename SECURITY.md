# Security

## The threat model, stated plainly

This stack runs a GitHub Actions runner with the host's Docker socket mounted.
**That is root on the host.** Any workflow the runner executes can start a
privileged container and read or write anything on the machine. There is no
sandbox, and none is intended: the design assumes you trust every workflow in
the repository you point it at.

So the following are **not vulnerabilities in this project** — they are the
documented consequence of that design, and the README says so before the
install instructions:

- a workflow in the target repository reading host files or other containers,
- a pull request from a fork executing code on the host, when the runner is
  pointed at a public repository or one that accepts fork pull requests,
- an organisation-scoped runner picking up a job from a repository you did not
  expect.

If you need isolation rather than trust, this is the wrong tool. Use
[actions-runner-controller](https://github.com/actions/actions-runner-controller),
rootless Docker, or a per-job throwaway VM.

## What a report should cover

Things that *are* in scope:

- the stack granting more than it documents — a mount, a capability or a
  network path the README does not mention,
- the prune service removing something it says it will not (volumes with
  `PRUNE_VOLUMES=false`, or `_work` caches),
- `cleanup.sh` removing something outside the scope its flags name,
- a credential leaking into logs, image layers or the Portainer UI,
- documentation that understates a risk. A README that lulls somebody into
  pointing this at a public repository is a real defect, and worth a report.

## How to report

Open a [private security
advisory](https://github.com/NoiXdev/portainer-github-runner/security/advisories/new).
If you prefer e-mail, write to the address on
[noix.dev](https://noix.dev) and say the repository's name.

Please include the compose file and environment you used, the Docker version,
and what you expected instead. There is no bounty; there is a credit in the
advisory if you want one.

## Supported versions

`main` only. This is a few files, not a release train: pull the current `main`
and compare with yours.

One version does matter — the runner image is pinned on purpose, because a
runner that pulls a new image mid-job loses the job. That pin also means you do
not get the runner's own security updates automatically. GitHub force-upgrades
the runner binary when it falls too far behind, but bump `RUNNER_IMAGE`
deliberately now and again rather than relying on that.
