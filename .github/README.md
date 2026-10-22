# .github

Contains this repo's continuous integration configuration. Despite the name,
the folder is **not GitHub-only**: it holds both pipelines. **GitLab CI is the
main pipeline** (builds `latest`); **GitHub Actions is the mirror/notifier** —
it runs more frequently and triggers GitLab for the actual main deployment.

## Structure

- `ci/` — the CI scripts, moved here from the repo root in 2026-10:
  - `ci/common/` — shared helpers reused by both pipelines
    - `utils.py` — ISO datetime parsing + key/value env file writes
    - `registry.py` — Docker Registry v2 client
    - `github_packages.py` — GitHub Packages client
    - `retention.py` — tag/version retention policy
    - `update_check.py` — backend-agnostic channel comparison
  - `ci/github/` — GitHub Actions pipeline scripts (mirror/notifier)
    - `check_update.py`, `cleanup_old_tags.py`
  - `ci/gitlab/` — GitLab CI pipeline scripts (main pipeline)
    - `check_update.py`, `check_package_updates.py`, `build_pages.py`,
      `cleanup_old_tags.py`
- `workflows/` — GitHub Actions workflows (`build.yml`).
- `.gitlab-ci.yml` — GitLab CI pipeline definition (main pipeline).
- `CODEOWNERS` — repository code owners.

## How the scripts are run

Both CI files set `PYTHONPATH` to the repo root so the `ci.` package
(resolved from `ci/`) imports work:

```yaml
export PYTHONPATH="$CI_PROJECT_DIR/.github"
python3 -m ci.gitlab.check_update
```

```yaml
PYTHONPATH: ${{ github.workspace }}/.github
python3 -m ci.github.check_update
```

Paths inside CI filters were updated accordingly (e.g. `.github/ci/**/*`).
