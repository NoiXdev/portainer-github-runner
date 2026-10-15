# Contributing

Small project, few rules.

## Before you open a pull request

**Do not point this runner at this repository.** It takes pull requests from
forks, which is exactly the case the README tells you not to use a
socket-mounted runner for. There is no CI here on purpose.

## What is welcome

- Another host or deployment flavour, as long as the two rules survive:
  identical paths for the work root, and a prune whose filter keeps the images
  the next job needs.
- Reasons. A comment that says *why* a line exists is worth more here than the
  line. Both rules in `docker-compose.yml` exist because their absence produces
  failures that do not name their cause, and that is written down so the next
  person does not have to rediscover it.
- Corrections. If a measurement in the README no longer holds — GitHub's
  pricing above all — say so with what you measured.

## What is not

- Making the Docker socket optional by hiding it. If you want isolation, use a
  tool built for it; a half-sandbox that reads as safe is worse than an honest
  warning.
- A feature that needs a second service to be understood. One stack, two
  services, is the whole point.

## Style

- Comments explain why, not what.
- `sh -n cleanup.sh` before you push a change to it; it is POSIX `sh`, not bash.
- Every variable the compose file reads appears in `stack.env.example`, with
  what happens if you get it wrong.
