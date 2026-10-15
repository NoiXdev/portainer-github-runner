# portainer-github-runner

A self-hosted GitHub Actions runner as one Portainer stack, with the two things
such a stack usually lacks: a work directory that bind mounts actually resolve
through, and something that stops the disk filling up.

## Why bother

GitHub bills hosted runner minutes; self-hosted minutes are free. (GitHub
announced a per-minute charge for self-hosted runners for March 2026 and then
postponed it; it is not in effect as of October 2026. Re-check before relying
on it.) The arithmetic only matters for long jobs — moving a two-minute
typecheck saves nothing and costs you a machine to look after. Measure first,
move the one job that dominates the bill, and leave the fast jobs on GitHub's
runners so a push still gets a verdict when your host is off.

## The two rules this stack exists to encode

**Identical paths.** The runner uses the host's Docker daemon, so every path it
gives Docker is resolved on the host. If the work directory is not mounted at
its own host path, Docker creates empty directories and mounts those — no
error, just a container that serves nothing or a build that cannot see files
that are plainly there. `RUNNER_WORK_ROOT` is therefore used three times, as
the env var and both sides of the volume.

**A filtered prune.** A persistent runner accumulates one image per branch
build, and nothing on a Docker host removes them. The prune service drops
images and build cache older than `PRUNE_KEEP` hourly. The filter is the point:
an unfiltered `docker image prune -af` deletes what the next job needs and adds
the download to every run.

## Deploy

1. **Check the host can do the job.** Whatever your workflow needs must be free
   here — ports above all, if the job serves anything. A runner that cannot
   bind its ports fails in the job, not at deploy.
2. **Create the work directory**, owned by uid 1000 (the runner user):
   ```bash
   sudo mkdir -p /srv/<purpose>-ci/_work
   sudo chown 1000:1000 /srv/<purpose>-ci/_work
   ```
3. **Get a registration token**: the repository's (or organisation's)
   Settings → Actions → Runners → New self-hosted runner. One hour,
   single-use.
4. **Deploy the stack** in Portainer from this repository, filling the
   variables from `.env.example`.
5. **Check it is Idle** under Settings → Actions → Runners, carrying the label
   you set.
6. **Point the job at it** — and only now, because a `runs-on` label with no
   runner behind it queues for 24 hours before failing:
   ```yaml
   runs-on: [self-hosted, linux, x64, <your-label>]
   ```

A deploy after the token expired fails with a registration error. Fetch a fresh
token, set the variable again; nothing else is lost.

## Several repositories on one host

Deploy this stack once per repository, under different Portainer stack names.
Give each its own `RUNNER_NAME`, `RUNNER_LABELS` and — this one bites —
**its own `RUNNER_WORK_ROOT`**. Two stacks sharing a work root will overwrite
each other's checkouts.

Do not reach for `deploy.replicas`: every replica would register under the same
`RUNNER_NAME` and share one work root.

## Security: the Docker socket is root on this host

The runner mounts `/var/run/docker.sock`. Any workflow it runs can start a
privileged container and read or write anything on the host. For a private,
single-author repository on a host that carries nothing precious, that is a
reasonable trade. It stops being one as soon as any of this is true:

- **the repository is public, or accepts pull requests from forks** — a pull
  request can then run arbitrary code as root on your host. Do not point this
  stack at such a repository without `RUNNER_EPHEMERAL=true` at minimum, and
  preferably not at all;
- **`RUNNER_SCOPE=org`** — the runner then accepts jobs from every repository
  in the organisation, including ones added later by someone else;
- **the host carries anything whose loss would hurt** — secrets, production
  data, another project's volumes.

In any of those cases, give the runner a throwaway VM, or use a rootless or
ephemeral setup instead of this one.

## Per-project notes

### Klubkern (`klubkern/klubkern-web`) — the E2E job

The case this stack was first written for. Worth reading as a worked example of
"what the host must provide".

- Measured 2026-10-13: one push cost 60 billed minutes, of which the Playwright
  E2E job was **52**. The other four jobs stayed on `ubuntu-latest`.
- The job runs DDEV, whose router publishes five hostnames on the host's
  **ports 80 and 443**, and the job fails unless all five answer `200`. Check
  with `ss -ltnp '( sport = :80 or sport = :443 )'` before deploying. If
  something holds them, moving DDEV's `router_http_port`/`router_https_port` is
  not enough on its own — the hardcoded test URLs have to follow.
- The project's CI override sets `performance_mode: none`, a real bind mount,
  which is precisely why the identical-paths rule is not optional there.
- `*.ddev.site` is public wildcard DNS pointing at 127.0.0.1 and needs no host
  entries, unless the host runs a DNS filter that strips private answers.
- Label `klubkern-e2e`, work root `/srv/klubkern-ci/_work`.
- Unproven at the time of writing: `ddev/github-action-setup-ddev` is built for
  GitHub-hosted runners and installs DDEV with `sudo`. If it fails inside the
  container, bake DDEV into a derived image rather than fighting the action.
