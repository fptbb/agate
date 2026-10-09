#!/usr/bin/env python3

"""Removes expired package versions from GitHub Packages.

Backend-specific concerns -- listing versions and deleting them -- stay here.
The retention decision is delegated to scripts.common.retention.
"""

import logging
import os
import sys

from scripts.common.github_packages import GitHubPackagesClient
from scripts.common.retention import (
    ALL_PROTECTED,
    ImageItem,
    digest_from_signature_tag,
    retention_from_env,
    select_active_digests,
    split_keep_delete,
    summarize,
)


logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")
logger = logging.getLogger(__name__)


class GitHubPackageCleaner:
    def __init__(self):
        self.image_name = os.environ.get("IMAGE_NAME", "agate")
        self.username = os.environ.get("USERNAME")
        self.token = os.environ.get("TOKEN")

        if not all([self.image_name, self.username, self.token]):
            logger.error("Missing variables.")
            sys.exit(1)

        self.client = GitHubPackagesClient(self.image_name, self.username, self.token)

    def collect_items(self) -> list:
        """Normalise package versions into ImageItem records."""
        logger.info(f"Scanning package {self.image_name}...")
        versions = self.client.get_all_versions()
        logger.info(f"Found {len(versions)} versions.")

        items = []
        for version in versions:
            created = self.client.parse_date(version.get("created_at"))
            if not created:
                continue

            tags = tuple(version.get("metadata", {}).get("container", {}).get("tags", []) or [])

            # A version with no tags is an orphaned signature: cosign detaches
            # the .sig blob from its image once the image tag is gone.
            if not tags or any(tag.endswith(".sig") for tag in tags):
                signed = digest_from_signature_tag(tags[0]) if tags else ""
                items.append(
                    ImageItem(
                        label=tags[0] if tags else version.get("name", "<untagged>"),
                        digest=signed,
                        date=created,
                        tags=tags,
                        is_signature=True,
                        handle=str(version["id"]),
                    )
                )
                continue

            items.append(
                ImageItem(
                    label=version.get("name", "<untagged>"),
                    digest=version.get("name", ""),
                    date=created,
                    tags=tags,
                    handle=str(version["id"]),
                )
            )
        return items

    def delete(self, item: ImageItem) -> None:
        logger.info(f"Deleting {item.label} {item.tags}")
        self.client.delete_version(int(item.handle))

    def run(self):
        max_age_days, max_keep, protected = retention_from_env(ALL_PROTECTED)

        items = self.collect_items()
        active = select_active_digests(
            items,
            max_age_days=max_age_days,
            max_keep=max_keep,
            protected_tags=protected,
        )

        keep, delete = split_keep_delete(items, active)
        summarize(keep, delete, f"ghcr.io/{self.username}/{self.image_name}")

        for item in keep:
            logger.info(f"Keeping {item.label} {item.tags}")
        for item in delete:
            self.delete(item)


if __name__ == "__main__":
    GitHubPackageCleaner().run()