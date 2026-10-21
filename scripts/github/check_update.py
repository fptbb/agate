#!/usr/bin/env python3

"""GitHub Actions update check.

Fetches upstream/local tag dates via the shared helpers, then delegates the
comparison to scripts.common.update_check. On a detected update it also nudges
the GitLab mirror by triggering a pipeline there.
"""

import json
import logging
import os
import sys

import requests

from scripts.common.github_packages import GitHubPackagesClient
from scripts.common.registry import DockerRegistryClient
from scripts.common.update_check import CHANNELS, compare, recipes_to_build
from scripts.common.utils import write_key_value_file


logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")
logger = logging.getLogger(__name__)

GITLAB_PROJECT_ID = os.environ.get("GITLAB_PROJECT_ID", "76001048")


def trigger_gitlab_mirror():
    """Ask the GitLab mirror to rebuild. Its own update check is the final gate."""
    token = os.environ.get("GITLAB_TOKEN")
    if not token:
        logger.warning("GITLAB_TOKEN not set; skipping GitLab mirror trigger.")
        return

    url = f"https://gitlab.com/api/v4/projects/{GITLAB_PROJECT_ID}/trigger/pipeline"
    try:
        resp = requests.post(url, data={"token": token, "ref": "main"}, timeout=30)
        logger.info(f"GitLab mirror trigger returned {resp.status_code}")
    except Exception as exc:
        logger.error(f"Failed to trigger the GitLab mirror: {exc}")


def main():
    upstream_image = os.environ.get("UPSTREAM_IMAGE", "ublue-os/bazzite-nvidia-open")
    upstream_registry = os.environ.get("UPSTREAM_REGISTRY", "ghcr.io")
    image_name = os.environ.get("IMAGE_NAME", "agate")
    user = os.environ.get("USERNAME")
    token = os.environ.get("TOKEN")

    logger.info(f"Checking Upstream: {upstream_registry}/{upstream_image}")
    upstream_client = DockerRegistryClient(
        upstream_registry,
        upstream_image,
        is_ghcr=("ghcr.io" in upstream_registry.lower()),
    )

    logger.info(f"Checking Local (GitHub Packages): {user}/{image_name}")
    try:
        local_client = GitHubPackagesClient(image_name, user, token)
        local_dates = local_client.get_tag_dates()
    except Exception as exc:
        logger.error(f"Error fetching local dates from GitHub Packages: {exc}")
        local_dates = {}

    upstream_dates = {tag: upstream_client.get_created_date(tag) for tag, _ in CHANNELS}

    channels = compare(upstream_dates, local_dates, CHANNELS)
    recipes = recipes_to_build(channels)

    github_output = os.environ["GITHUB_OUTPUT"]
    write_key_value_file(github_output, "needs_update", "true" if recipes else "false")
    write_key_value_file(github_output, "recipes", json.dumps(recipes))

    if recipes:
        logger.info(f"Updates found for: {recipes}. Proceeding to build.")
        trigger_gitlab_mirror()
    else:
        logger.info("Everything is up to date.")

    sys.exit(0)


if __name__ == "__main__":
    main()