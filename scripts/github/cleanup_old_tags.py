#!/usr/bin/env python3

import logging
import os
import sys
from datetime import datetime, timezone

from scripts.ci.github_packages import GitHubPackagesClient


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

    def run(self):
        max_age_days = int(os.environ.get("MAX_AGE_DAYS", 7))
        max_keep = int(os.environ.get("MAX_KEEP", 5))
        protected_tags = ["latest", "latest-cache"]

        logger.info(f"Scanning package {self.image_name}...")
        versions = self.client.get_all_versions()
        logger.info(f"Found {len(versions)} versions.")

        version_data = []
        sig_data = []

        for v in versions:
            dt = self.client.parse_date(v["created_at"])
            if not dt:
                continue

            tags = v["metadata"]["container"]["tags"]
            is_sig = any(t.endswith(".sig") for t in tags) if tags else False
            if not tags:
                is_sig = True

            item = {
                "id": v["id"],
                "tags": tags,
                "date": dt,
                "digest": v["name"],
            }

            if is_sig:
                sig_data.append(item)
            else:
                version_data.append(item)

        version_data.sort(key=lambda x: x["date"], reverse=True)

        active_digests = set()
        image_count = 0

        for item in version_data:
            tags = item["tags"]
            digest = item["digest"]
            age_days = (datetime.now(timezone.utc) - item["date"]).days
            should_keep = False

            if any(t in protected_tags for t in tags):
                should_keep = True
            elif image_count < max_keep:
                should_keep = True
                image_count += 1
            elif age_days <= max_age_days:
                should_keep = True

            if should_keep:
                active_digests.add(digest)

        logger.info(f"Analysis Complete. Keeping {len(active_digests)} images. Proceeding to cleanup.")

        for item in version_data:
            if item["digest"] not in active_digests:
                logger.info(f"Deleting expired image {item['digest']} {item['tags']}")
                self.client.delete_version(item["id"])

        for item in sig_data:
            if item["tags"]:
                sig_tag = item["tags"][0]
                clean_digest = sig_tag.replace(".sig", "").replace("-", ":")
                if clean_digest not in active_digests:
                    logger.info(f"Deleting orphaned signature {item['digest']} {item['tags']}")
                    self.client.delete_version(item["id"])
            else:
                logger.info(f"Deleting untagged signature {item['digest']}")
                self.client.delete_version(item["id"])


if __name__ == "__main__":
    cleaner = GitHubPackageCleaner()
    cleaner.run()
