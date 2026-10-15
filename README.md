# portainer-github-runner

A self-hosted GitHub Actions runner as one Portainer stack, with the two things
such a stack usually lacks: a work directory that bind mounts actually resolve
through, and something that keeps the disk from filling up.

---

## ⚠️ Read this before you deploy it

**This runner mounts the host's Docker socket. That is root on the host.**

Any workflow this runner executes can start a privileged container and read or
write anything on the machine — the other stacks, their volumes, their secrets,
the host filesystem. There is no sandbox. "A workflow" includes any workflow
file in the repository you point it at, on any branch, written by anyone who
can push or open a pull request.

That is an acceptable trade for a **private repository, trusted authors, and a
host that carries nothing precious**. It is not acceptable if any of this is
true:

| situation | why it breaks | what to do instead |
|---|---|---|
| the repository is **public**, or accepts **pull requests from forks** | a stranger's pull request runs as root on your host | don't. If you must, `RUNNER_EPHEMERAL=true` and a throwaway VM, and read GitHub's own warning about self-hosted runners on public repositories |
| `RUNNER_SCOPE=org` | the runner accepts jobs from **every** repository in the organisation, including ones added later by someone else | scope it to one repository |
| the host runs **production**, or another project's data | a runaway or malicious job reaches it | give the runner its own machine |

GitHub says the same thing, more briefly, and they are right: *"We recommend
that you only use self-hosted runners with private repositories."* The reason
they give is the one in the table — a fork's pull request can run code on your
machine ([Adding self-hosted
runners](https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/add-runners)).

If you want isolation rather than trust, this is the wrong stack — use
[actions-runner-controller](https://github.com/actions/actions-runner-controller)
or rootless Docker.

---

## When it is worth it

GitHub bills hosted runner minutes; self-hosted minutes are free. (GitHub
announced a per-minute charge for self-hosted runners for March 2026, then
postponed it; it is not in effect as of October 2026. Re-check before relying
on it.)

The arithmetic only works for **long** jobs. Moving a two-minute typecheck
saves nothing and costs you a machine to look after. Measure your runs, move
the one job that dominates the bill, and leave the fast jobs on GitHub's
runners — then a push still gets its basic verdict when your host is off.

A worked example: a repository whose push cost 60 billed minutes, 52 of them a
single browser-test job. Moving that one job removed 87 % of the bill and left
four jobs, eight minutes, on GitHub.

## The two rules this stack encodes

**Identical paths.** The runner uses the host's Docker daemon, so every path it
hands to Docker is resolved on the host. A workflow step that bind-mounts its
checkout — `docker run -v "$PWD:/src"`, docker compose, testcontainers, a local
dev-environment tool — passes a path from inside the container to a daemon
outside it. If the work directory is not mounted at its own host path, Docker
silently creates empty directories and mounts those. Nothing errors. The
symptom is a container that starts and serves nothing, or a build that cannot
find files that are plainly there. `RUNNER_WORK_ROOT` is therefore used three
times: the env var and both sides of the volume.

**A filtered prune.** A persistent runner accumulates one image per branch
build, plus every container a job forgets to tear down, and nothing on a Docker
host removes them. The prune service does it hourly for anything older than
`PRUNE_KEEP`. The filter is the point: an unfiltered `docker image prune -af`
deletes what the next job needs and adds the download to every run.

### What the prune deliberately does not touch

- **Volumes.** `docker volume prune --all` on a shared host destroys other
  stacks' data — a volume whose container was removed counts as unused. Opt in
  with `PRUNE_VOLUMES=true` only when the host runs nothing but runners.
- **`_work`.** `actions/checkout` defaults to `clean: true` (`git clean -ffdx`),
  so each job starts from a clean tree. `_work/_tool` and `_work/_actions` are
  caches worth keeping; deleting them costs every job a re-download and buys a
  few hundred megabytes.

### What no prune can fix

State a job leaves **inside a volume it reuses** — a seeded test database is
the classic one. On a hosted runner the VM is discarded, so most workflows
never learned to clean up; on a persistent runner the next run then tests
against the previous run's leftovers, and no amount of pruning sees it.

Tear that down **in the workflow, at the start of the job as well as the end** —
a cancelled job never runs its cleanup step:

```yaml
- name: Tear down anything a previous run left behind
  run: docker compose -f your-stack.yml down -v --remove-orphans || true

# … the job …

- name: Tear down
  if: always()
  run: docker compose -f your-stack.yml down -v --remove-orphans || true
```

## Deploy

1. **Check the host can do the job.** Whatever your workflow binds must be free
   — ports above all, if the job serves anything. A runner that cannot bind its
   ports fails inside the job, not at deploy time.
2. **Create the work directory**, owned by uid 1000 (the runner user):
   ```bash
   sudo mkdir -p /srv/e2e-ci/_work
   sudo chown 1000:1000 /srv/e2e-ci/_work
   ```
3. **Get a registration token**: the repository's Settings → Actions → Runners →
   New self-hosted runner. Valid one hour, single-use.
4. **Deploy in Portainer**: Stacks → Add stack → **Repository**, this URL,
   compose path `docker-compose.yml`. Under Environment variables switch to
   **Advanced mode** and paste [`stack.env.example`](stack.env.example), then
   fill the five required values.
5. **Check it is Idle** under Settings → Actions → Runners, with your label.
6. **Point the job at it** — and only now, because a `runs-on` label with no
   runner behind it queues the job for 24 hours and then fails it:
   ```yaml
   runs-on: [self-hosted, linux, x64, your-label]
   ```

A deploy after the token expired fails with a registration error. Fetch a fresh
token and set the variable again; nothing else is lost.

## Resetting a host

`cleanup.sh` runs on the host and reports by default — it changes nothing until
you name a scope, because it cannot tell a job's leftovers from another stack's
data:

```bash
./cleanup.sh                              # what is using disk, what each flag would do
./cleanup.sh --containers --images        # the usual reset
./cleanup.sh --work /srv/e2e-ci/_work     # clear a work root, keeping _tool and _actions
KEEP=24h ./cleanup.sh --all               # spare anything younger than 24h
```

`--volumes` exists and is the one to think about: on a shared host it destroys
other stacks' data, because a volume whose container was removed counts as
unused.

## Several repositories on one host

Deploy this stack once per repository, under different Portainer stack names.
Give each its own `RUNNER_NAME`, `RUNNER_LABELS` and — this one bites — **its
own `RUNNER_WORK_ROOT`**. Two stacks sharing a work root overwrite each other's
checkouts.

Do not reach for `deploy.replicas`: every replica would register under the same
name and share one work root.

## License

MIT. See [LICENSE](LICENSE).
