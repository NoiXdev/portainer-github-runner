## What this changes

<!-- One or two sentences. -->

## Why

<!-- What went wrong without it, or what you measured. A reason beats a
     description: this project's comments exist to stop the next person
     rediscovering a failure that does not name its cause. -->

## How you know it works

<!-- What you ran, on what. For a compose change: the host, the Docker
     version, and a job that actually used it. For cleanup.sh: `sh -n` plus a
     run with and without the flag. -->

## Checklist

- [ ] The work root is still mounted at its own host path (`RUNNER_WORK_ROOT`
      used three times), or this change does not touch it
- [ ] The prune still keeps what the next job needs — no unfiltered
      `docker image prune -af`
- [ ] Volumes are still opt-in (`PRUNE_VOLUMES` defaults to `false`)
- [ ] Any new variable is in `stack.env.example` with its failure mode
- [ ] No new mount, capability or network path that the README does not explain
