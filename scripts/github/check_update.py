#!/usr/bin/env python3

import logging
import os
import sys
import requests

from scripts.ci.common import write_key_value_file
from scripts.ci.registry import DockerRegistryClient


logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")
logger = logging.getLogger(__name__)


def main():
    upstream_image = os.environ.get("UPSTREAM_IMAGE", "ublue-os/bazzite-dx-nvidia")
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
    ud = upstream_client.get_created_date("latest")

    logger.info(f"Checking Local (GitHub API): {user}/{image_name}")

    ld = None
    try:
        api_url = f"https://api.github.com/users/{user}/packages/container/{image_name}/versions"
        headers = {"Accept": "application/vnd.github.v3+json"}
        if token:
            headers["Authorization"] = f"Bearer {token}"

        resp = requests.get(api_url, headers=headers)
        if resp.status_code == 200:
            for v in resp.json():
                if "latest" in v.get("metadata", {}).get("container", {}).get("tags", []):
                    date_str = v.get("created_at")
                    if date_str:
                        ld = upstream_client.parse_date(date_str)
                    break
        else:
            logger.error(f"GitHub API fetch failed: {resp.status_code} - {resp.text}")
    except Exception as e:
        logger.error(f"Error fetching local date via GitHub API: {e}")

    if not ud:
        logger.error("Could not fetch upstream date. Building anyway.")
        write_key_value_file(os.environ["GITHUB_OUTPUT"], "needs_update", "true")
        sys.exit(0)

    if not ld:
        logger.warning("Could not fetch local date. Assuming first build. Building anyway.")
        write_key_value_file(os.environ["GITHUB_OUTPUT"], "needs_update", "true")
        sys.exit(0)

    logger.info(f"Upstream Date: {ud}")
    logger.info(f"Local Date:    {ld}")

    if ud > ld:
        logger.info("Update Available. Proceeding to build.")
        write_key_value_file(os.environ["GITHUB_OUTPUT"], "needs_update", "true")
        requests.post(
            "https://gitlab.com/api/v4/projects/76001048/trigger/pipeline",
            data={"token": os.environ.get("GITLAB_TOKEN"), "ref": "main"},
        )
        sys.exit(0)

    logger.info("System is up to date. Stopping pipeline.")
    write_key_value_file(os.environ["GITHUB_OUTPUT"], "needs_update", "false")
    sys.exit(0)


if __name__ == "__main__":
    main()
