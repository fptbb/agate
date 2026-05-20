#!/usr/bin/env python3

import json
import logging
import os
import sys
import requests

from scripts.ci.common import write_key_value_file
from scripts.ci.registry import DockerRegistryClient


logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")
logger = logging.getLogger(__name__)


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

    logger.info(f"Checking Local (GitHub API): {user}/{image_name}")
    local_tags_dates = {}
    try:
        api_url = f"https://api.github.com/users/{user}/packages/container/{image_name}/versions"
        headers = {"Accept": "application/vnd.github.v3+json"}
        if token:
            headers["Authorization"] = f"Bearer {token}"

        resp = requests.get(api_url, headers=headers)
        if resp.status_code == 200:
            for v in resp.json():
                tags = v.get("metadata", {}).get("container", {}).get("tags", [])
                for tag in tags:
                    if tag not in local_tags_dates:
                        date_str = v.get("created_at")
                        if date_str:
                            local_tags_dates[tag] = upstream_client.parse_date(date_str)
        else:
            logger.error(f"GitHub API fetch failed: {resp.status_code} - {resp.text}")
    except Exception as e:
        logger.error(f"Error fetching local date via GitHub API: {e}")

    tags_to_check = {
        "latest": "recipe.yml",
        "testing": "recipe-testing.yml",
    }

    recipes_to_build = []
    any_update = False

    for tag, recipe in tags_to_check.items():
        logger.info(f"Analyzing tag: {tag}")
        ud = upstream_client.get_created_date(tag)
        ld = local_tags_dates.get(tag)

        build_this = False
        if not ud:
            logger.error(f"Could not fetch upstream date for {tag}. Building anyway.")
            build_this = True
        elif not ld:
            logger.warning(f"Could not fetch local date for {tag}. Assuming first build. Building anyway.")
            build_this = True
        elif ud > ld:
            logger.info(f"Update Available for {tag}. Upstream: {ud}, Local: {ld}")
            build_this = True
        else:
            logger.info(f"Tag {tag} is up to date. Upstream: {ud}, Local: {ld}")

        if build_this:
            recipes_to_build.append(recipe)
            any_update = True

    write_key_value_file(os.environ["GITHUB_OUTPUT"], "needs_update", "true" if any_update else "false")
    write_key_value_file(os.environ["GITHUB_OUTPUT"], "recipes", json.dumps(recipes_to_build))

    if any_update:
        logger.info(f"Updates found for: {recipes_to_build}. Proceeding to build.")
        requests.post(
            "https://gitlab.com/api/v4/projects/76001048/trigger/pipeline",
            data={"token": os.environ.get("GITLAB_TOKEN"), "ref": "main"},
        )
    else:
        logger.info("Everything is up to date.")
    
    sys.exit(0)


if __name__ == "__main__":
    main()
