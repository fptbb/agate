#!/usr/bin/env python3

"""Removes expired tags from the Docker Registry v2 (Quay) mirror.

Backend-specific concerns -- listing tags and deleting manifests -- stay here.
The retention decision is delegated to scripts.common.retention.
"""

import logging
import os
import sys

from scripts.common.registry import DockerRegistryClient
from scripts.common.retention import (
    LATEST_PROTECTED,
    ImageItem,
    digest_from_signature_tag,
    retention_from_env,
    select_active_digests,
    split_keep_delete,
    summarize,
)


logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")
logger = logging.getLogger(__name__)


class DockerV2Cleaner:
    def __init__(self):
        self.registry = os.environ.get("BB_REGISTRY", "quay.io")
        namespace = os.environ.get("BB_REGISTRY_NAMESPACE")
        image = os.environ.get("IMAGE_NAME", "agate")
        self.repo = f"{namespace}/{image}"
        self.username = os.environ.get("BB_USERNAME")
        self.password = os.environ.get("BB_PASSWORD")
        self.dry_run = os.environ.get("DRY_RUN", "false").lower() == "true"

        if not all([namespace, image, self.username, self.password]):
            logger.error("Missing variables.")
            sys.exit(1)

        self.client = DockerRegistryClient(
            self.registry,
            self.repo,
            username=self.username,
            password=self.password,
            auth_scope="pull,push",
        )

    def collect_items(self) -> list:
        """Normalise registry tags into ImageItem records."""
        logger.info(f"Scanning {self.repo}...")
        tags = self.client.get_all_tags()
        logger.info(f"Found {len(tags)} tags. Parsing metadata...")

        items = []
        for tag in tags:
            meta = self.client.get_tag_metadata(tag)
            if not meta:
                continue

            if tag.endswith(".sig"):
                # A signature tag is named after the digest it signs, and its
                # own manifest digest is a different value. Track the signed
                # digest so the signature survives exactly as long as its image.
                items.append(
                    ImageItem(
                        label=tag,
                        digest=digest_from_signature_tag(tag),
                        date=meta["date"],
                        tags=(tag,),
                        is_signature=True,
                        handle=meta["digest"],
                    )
                )
            else:
                items.append(
                    ImageItem(
                        label=tag,
                        digest=meta["digest"],
                        date=meta["date"],
                        tags=(tag,),
                        handle=meta["digest"],
                    )
                )
        return items

    def delete(self, item: ImageItem) -> bool:
        if self.dry_run:
            logger.info(f"[DRY RUN] Delete {item.label}")
            return True

        resp = self.client.delete_manifest(item.handle)
        if resp.status_code in (200, 202, 204):
            logger.info(f"Deleted {item.label}")
            return True
        logger.error(f"Failed delete {item.label}: {resp.status_code}")
        return False

    def run(self):
        max_age_days, max_keep, protected = retention_from_env(LATEST_PROTECTED)

        items = self.collect_items()
        active = select_active_digests(
            items,
            max_age_days=max_age_days,
            max_keep=max_keep,
            protected_tags=protected,
        )
        logger.info(f"Protecting {len(active)} images and their signatures.")

        keep, delete = split_keep_delete(items, active)
        summarize(keep, delete, f"{self.registry}/{self.repo}")

        for item in keep:
            logger.info(f"Keeping {item.label}")
        for item in delete:
            self.delete(item)


if __name__ == "__main__":
    DockerV2Cleaner().run()