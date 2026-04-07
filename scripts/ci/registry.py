#!/usr/bin/env python3

import json
import logging

import requests
from requests.auth import HTTPBasicAuth

from scripts.ci.common import parse_iso_datetime


logger = logging.getLogger(__name__)


class DockerRegistryClient:
    def __init__(self, registry, repo, username=None, password=None, is_ghcr=False, auth_scope="pull"):
        self.registry = registry
        self.repo = repo
        self.username = username
        self.password = password
        self.is_ghcr = is_ghcr
        self.auth_scope = auth_scope
        self.session = requests.Session()
        self.base_url = f"https://{self.registry}/v2"

        if self.is_ghcr:
            self.token = self.get_ghcr_token()
        elif self.username and self.password:
            self.token = self.get_auth_token()
        else:
            self.token = None

        if self.token:
            self.session.headers.update({"Authorization": f"Bearer {self.token}"})

        self.session.headers.update(
            {
                "Accept": "application/vnd.docker.distribution.manifest.v2+json, "
                "application/vnd.docker.distribution.manifest.list.v2+json, "
                "application/vnd.oci.image.manifest.v1+json, "
                "application/vnd.oci.image.index.v1+json",
            }
        )

    def get_ghcr_token(self):
        try:
            url = f"https://ghcr.io/token?scope=repository:{self.repo}:pull"
            return requests.get(url).json()["token"]
        except Exception as e:
            logger.warning(f"Failed GHCR fetch token: {e}")
            return None

    def get_auth_token(self):
        scope = f"repository:{self.repo}:{self.auth_scope}"
        auth_url = f"https://{self.registry}/v2/auth?service={self.registry}&scope={scope}"
        try:
            resp = requests.get(auth_url, auth=HTTPBasicAuth(self.username, self.password))
            if resp.status_code != 200:
                logger.error(f"Auth failed {self.registry}: {resp.status_code} {resp.text}")
                return None
            return resp.json().get("token")
        except Exception as e:
            logger.error(f"Auth error {self.registry}: {e}")
            return None

    def parse_date(self, date_str):
        return parse_iso_datetime(date_str)

    def fetch_manifest(self, digest_or_tag):
        try:
            resp = self.session.get(f"{self.base_url}/{self.repo}/manifests/{digest_or_tag}")
            if resp.status_code != 200:
                return None, None
            return resp.json(), resp.headers.get("Docker-Content-Digest")
        except Exception:
            return None, None

    def get_date_from_single_manifest(self, manifest):
        if "annotations" in manifest:
            created = manifest["annotations"].get("org.opencontainers.image.created")
            if created:
                return self.parse_date(created)
        if "config" in manifest:
            cfg_digest = manifest["config"].get("digest")
            if cfg_digest:
                resp = self.session.get(f"{self.base_url}/{self.repo}/blobs/{cfg_digest}")
                if resp.status_code == 200:
                    return self.parse_date(resp.json().get("created"))
        if "history" in manifest and len(manifest["history"]) > 0:
            try:
                v1 = json.loads(manifest["history"][0]["v1Compatibility"])
                return self.parse_date(v1.get("created"))
            except Exception:
                pass
        return None

    def get_created_date(self, tag):
        root_manifest, _ = self.fetch_manifest(tag)
        if not root_manifest:
            return None

        if "manifests" in root_manifest:
            sub_digest = root_manifest["manifests"][0]["digest"]
            sub_manifest, _ = self.fetch_manifest(sub_digest)
            if sub_manifest:
                return self.get_date_from_single_manifest(sub_manifest)
            return None

        return self.get_date_from_single_manifest(root_manifest)

    def get_all_tags(self):
        url = f"{self.base_url}/{self.repo}/tags/list"
        all_tags = []
        while url:
            try:
                resp = self.session.get(url)
                if resp.status_code != 200:
                    break
                data = resp.json()
                all_tags.extend(data.get("tags", []))
                link = resp.headers.get("Link")
                url = None
                if link and 'rel="next"' in link:
                    url = link.split(";")[0].strip("<>")
                    if not url.startswith("http"):
                        url = f"https://{self.registry}{url}"
            except Exception:
                break
        return all_tags

    def get_tag_metadata(self, tag):
        root_manifest, root_digest = self.fetch_manifest(tag)
        if not root_manifest:
            return None

        dt = None
        if "manifests" in root_manifest:
            sub_digest = root_manifest["manifests"][0]["digest"]
            sub_manifest, _ = self.fetch_manifest(sub_digest)
            if sub_manifest:
                dt = self.get_date_from_single_manifest(sub_manifest)
        else:
            dt = self.get_date_from_single_manifest(root_manifest)

        if dt:
            if dt.tzinfo is None:
                from datetime import timezone

                dt = dt.replace(tzinfo=timezone.utc)
            return {"name": tag, "date": dt, "digest": root_digest}
        return None

    def delete_manifest(self, digest):
        return self.session.delete(f"{self.base_url}/{self.repo}/manifests/{digest}")
