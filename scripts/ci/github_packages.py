#!/usr/bin/env python3

import logging

import requests

from scripts.ci.common import parse_iso_datetime


logger = logging.getLogger(__name__)


class GitHubPackagesClient:
    def __init__(self, image_name, username, token):
        self.image_name = image_name
        self.username = username
        self.token = token

        self.session = requests.Session()
        self.session.headers.update(
            {
                "Authorization": f"token {self.token}",
                "Accept": "application/vnd.github.v3+json",
            }
        )

        self.api_url = f"https://api.github.com/user/packages/container/{self.image_name}/versions"

    def parse_date(self, date_str):
        return parse_iso_datetime(date_str)

    def get_all_versions(self):
        url = self.api_url + "?per_page=100"
        all_versions = []
        while url:
            try:
                resp = self.session.get(url)
                if resp.status_code != 200:
                    logger.error(f"Failed to fetch versions: {resp.status_code} {resp.text}")
                    break
                all_versions.extend(resp.json())

                link = resp.headers.get("Link")
                url = None
                if link and 'rel="next"' in link:
                    for part in link.split(","):
                        if 'rel="next"' in part:
                            url = part.split(";")[0].strip(" <>")
            except Exception as e:
                logger.error(f"Error fetching versions: {e}")
                break
        return all_versions

    def delete_version(self, version_id):
        resp = self.session.delete(f"{self.api_url}/{version_id}")
        if resp.status_code == 204:
            logger.info(f"Deleted version ID {version_id}")
            return True
        logger.error(f"Failed to delete version ID {version_id}: {resp.status_code} {resp.text}")
        return False

    def get_latest_tagged_date(self, tag="latest"):
        versions = self.get_all_versions()
        for version in versions:
            if tag in version.get("metadata", {}).get("container", {}).get("tags", []):
                date_str = version.get("created_at")
                if date_str:
                    return self.parse_date(date_str)
                break
        return None
