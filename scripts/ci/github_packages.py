#!/usr/bin/env python3

import logging
from urllib.parse import quote

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

        self.package_name = quote(self.image_name, safe="")
        self.api_urls = self._build_api_urls()
        self.api_url = self.api_urls[0]

    def parse_date(self, date_str):
        return parse_iso_datetime(date_str)

    def _build_api_urls(self):
        owner_type = self._get_owner_type()
        api_urls = []

        if owner_type == "organization":
            api_urls.append(
                f"https://api.github.com/orgs/{self.username}/packages/container/{self.package_name}/versions"
            )
        elif owner_type == "user":
            api_urls.append(
                f"https://api.github.com/users/{self.username}/packages/container/{self.package_name}/versions"
            )

        # Fallbacks for cases where owner type lookup is unavailable or package scope differs.
        api_urls.extend(
            [
                f"https://api.github.com/users/{self.username}/packages/container/{self.package_name}/versions",
                f"https://api.github.com/orgs/{self.username}/packages/container/{self.package_name}/versions",
                f"https://api.github.com/user/packages/container/{self.package_name}/versions",
            ]
        )

        deduped_urls = []
        for url in api_urls:
            if url not in deduped_urls:
                deduped_urls.append(url)
        return deduped_urls

    def _get_owner_type(self):
        try:
            resp = self.session.get(f"https://api.github.com/users/{self.username}")
            if resp.status_code != 200:
                logger.warning(
                    "Failed to determine GitHub owner type for %s: %s %s",
                    self.username,
                    resp.status_code,
                    resp.text,
                )
                return None
            owner_type = resp.json().get("type")
            if owner_type:
                return owner_type.lower()
        except Exception as exc:
            logger.warning("Error determining GitHub owner type for %s: %s", self.username, exc)
        return None

    def _get_versions_from_url(self, api_url):
        url = api_url + "?per_page=100"
        all_versions = []
        while url:
            resp = self.session.get(url)
            if resp.status_code != 200:
                return None, resp
            all_versions.extend(resp.json())

            link = resp.headers.get("Link")
            url = None
            if link and 'rel="next"' in link:
                for part in link.split(","):
                    if 'rel="next"' in part:
                        url = part.split(";")[0].strip(" <>")

        return all_versions, None

    def get_all_versions(self):
        for api_url in self.api_urls:
            try:
                all_versions, err_resp = self._get_versions_from_url(api_url)
                if all_versions is not None:
                    self.api_url = api_url
                    logger.info("Using GitHub Packages endpoint: %s", self.api_url)
                    return all_versions
                logger.warning(
                    "Failed to fetch versions from %s: %s %s",
                    api_url,
                    err_resp.status_code,
                    err_resp.text,
                )
            except Exception as exc:
                logger.error("Error fetching versions from %s: %s", api_url, exc)
        return []

    def delete_version(self, version_id):
        candidate_urls = [self.api_url, *self.api_urls]
        attempted = []

        for api_url in candidate_urls:
            if api_url in attempted:
                continue
            attempted.append(api_url)

            resp = self.session.delete(f"{api_url}/{version_id}")
            if resp.status_code == 204:
                self.api_url = api_url
                logger.info(f"Deleted version ID {version_id}")
                return True

            logger.warning(
                "Failed to delete version ID %s via %s: %s %s",
                version_id,
                api_url,
                resp.status_code,
                resp.text,
            )

        logger.error(f"Failed to delete version ID {version_id}: package version could not be deleted")
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
