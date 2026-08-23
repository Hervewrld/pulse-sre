# Git workflow for this project

Even working solo, this repo follows a team-style workflow on purpose - the
goal is to build the habits, not just get code committed.

## Branching

- `main` — always deployable. Never commit directly to it.
- `feature/<short-description>` — one branch per piece of work
  (e.g. `feature/api-health-endpoint`)
- Open a Pull Request into `main` even solo - use the PR description to
  explain *why*, and self-review the diff before merging.

## Commit messages (Conventional Commits)

Format: `<type>: <short summary>`

Common types:
- `feat:` — new functionality
- `fix:` — bug fix
- `chore:` — tooling, deps, config
- `docs:` — documentation only
- `refactor:` — code change with no behavior change

Example: `feat: add /health endpoint to api service`

CI/CD (Phase 5) will eventually key off these prefixes for changelog
generation and release tagging.

## Releases

Tag meaningful milestones with semantic versioning:

```bash
git tag -a v0.1.0 -m "Phase 0: basic API + worker skeleton"
git push origin v0.1.0
```

## Useful practice exercises

- Force a merge conflict on purpose (edit the same line on two branches) and resolve it.
- Use `git rebase -i` to squash a few messy commits before opening a PR.
- Use `git bisect` to find which commit introduced a bug once you have a few dozen commits.
