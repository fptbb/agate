#!/usr/bin/env python3

import os
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
PUBLIC_DIR = REPO_ROOT / "public"
PROJECT_PATH = os.environ.get("CI_PROJECT_PATH", "fpsys/agate")
DEFAULT_BRANCH = os.environ.get("CI_DEFAULT_BRANCH", "main")
RAW_BASE = f"https://gitlab.com/{PROJECT_PATH}/-/raw/{DEFAULT_BRANCH}"
ARTIFACTHUB_URL = "https://artifacthub.io/packages/container/agate/agate/"


def render_redirect_html(target_url: str, title: str = "Redirecting") -> str:
    return f"""<!DOCTYPE html>
<html lang="en">
    <head>
        <meta charset="utf-8" />
        <title>{title}</title>
        <meta http-equiv="refresh" content="0; url={target_url}" />
        <link rel="canonical" href="{target_url}" />
    </head>
    <body>
        <noscript>
            Redirecting to <a href="{target_url}">{target_url}</a>
        </noscript>
    </body>
</html>
"""


def tracked_files() -> list[str]:
    result = subprocess.run(
        ["git", "ls-files"],
        cwd=REPO_ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    return [line for line in result.stdout.splitlines() if line]


def write_page(relative_path: str, target_url: str, title: str = "Redirecting") -> None:
    dest = PUBLIC_DIR / relative_path
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(render_redirect_html(target_url, title), encoding="utf-8")


def main() -> None:
    PUBLIC_DIR.mkdir(parents=True, exist_ok=True)

    # Keep the root landing page as the Artifact Hub redirect.
    (PUBLIC_DIR / "index.html").write_text(
        render_redirect_html(ARTIFACTHUB_URL, "Agate"),
        encoding="utf-8",
    )
    (PUBLIC_DIR / "404.html").write_text(
        render_redirect_html(ARTIFACTHUB_URL, "Page not found"),
        encoding="utf-8",
    )

    for relative_path in tracked_files():
        if relative_path == "index.html":
            continue

        target_url = f"{RAW_BASE}/{relative_path}"
        write_page(relative_path, target_url, f"Redirecting to {relative_path}")


if __name__ == "__main__":
    main()
