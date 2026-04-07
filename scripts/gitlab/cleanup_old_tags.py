#!/usr/bin/env python3

import logging
import os
import sys
from datetime import datetime, timezone

from scripts.ci.registry import DockerRegistryClient


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

    def delete_tag(self, tag, digest):
        if self.dry_run:
            logger.info(f"[DRY RUN] Delete {tag}")
            return True

        resp = self.client.delete_manifest(digest)
        if resp.status_code in [200, 202, 204]:
            logger.info(f"Deleted {tag}")
            return True
        logger.error(f"Failed delete {tag}: {resp.status_code}")
        return False

    def get_cosign_sig_name(self, image_digest):
        clean_digest = image_digest.replace(":", "-")
        return f"{clean_digest}.sig"

    def run(self):
        max_age_days = int(os.environ.get("MAX_AGE_DAYS", 7))
        max_keep = int(os.environ.get("MAX_KEEP", 5))
        protected_tags = ["latest", "latest-cache"]

        logger.info(f"Scanning {self.repo}...")
        tags = self.client.get_all_tags()
        logger.info(f"Found {len(tags)} tags. Parsing metadata...")

        tag_data = []
        for tag in tags:
            meta = self.client.get_tag_metadata(tag)
            if meta:
                tag_data.append(meta)

        tag_data.sort(key=lambda x: x["date"], reverse=True)

        active_digests = set()
        active_signatures = set()
        image_count = 0

        for item in tag_data:
            name = item["name"]
            digest = item["digest"]

            if name.endswith(".sig"):
                continue

            age_days = (datetime.now(timezone.utc) - item["date"]).days
            should_keep = False

            if name in protected_tags:
                should_keep = True
            elif image_count < max_keep:
                should_keep = True
                image_count += 1
            elif age_days <= max_age_days:
                should_keep = True

            if should_keep:
                active_digests.add(digest)
                active_signatures.add(self.get_cosign_sig_name(digest))

        logger.info(f"Analysis Complete. Protecting {len(active_digests)} images and their signatures.")

        for item in tag_data:
            name = item["name"]
            digest = item["digest"]

            if name.endswith(".sig"):
                if name in active_signatures:
                    logger.info(f"Keeping {name} (Signature of Active Image)")
                else:
                    logger.info(f"Deleting {name} (Orphaned/Expired Signature)")
                    self.delete_tag(name, digest)
                continue

            if digest in active_digests:
                logger.info(f"Keeping {name} (Active Image)")
            else:
                logger.info(f"Deleting {name} (Expired/Excess Image)")
                self.delete_tag(name, digest)


if __name__ == "__main__":
    cleaner = DockerV2Cleaner()
    cleaner.run()
