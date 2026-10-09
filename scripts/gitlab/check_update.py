#!/usr/bin/env python3

"""GitLab update check.

This pipeline only publishes the latest channel -- recipe-testing.yml is built
by GitHub Actions alone -- so only that channel is compared. The decision logic
lives in scripts.common.update_check.
"""

import logging
import os
import smtplib
import ssl
import sys
from email.message import EmailMessage

from scripts.common.registry import DockerRegistryClient
from scripts.common.update_check import LATEST_ONLY, compare, recipes_to_build
from scripts.common.utils import write_key_value_file


logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")
logger = logging.getLogger(__name__)


def send_notification(upstream_date, local_date):
    host = os.environ.get("EMAIL_HOST")
    port = os.environ.get("EMAIL_PORT")
    user = os.environ.get("EMAIL_USER")
    password = os.environ.get("EMAIL_PASSWORD")
    recipient = os.environ.get("EMAIL_TO")

    if not all([host, port, user, password, recipient]):
        logger.warning("Email configuration missing. Skipping notification.")
        return

    msg = EmailMessage()
    msg.set_content(
        f"Update Detected!\n\nUpstream Date: {upstream_date}\nLocal Date: {local_date}\n\nTriggering build..."
    )
    msg["Subject"] = "Agate: Bazzite Update Detected"
    msg["From"] = user
    msg["To"] = recipient

    try:
        context = ssl.create_default_context()
        with smtplib.SMTP(host, int(port)) as server:
            server.starttls(context=context)
            server.login(user, password)
            server.send_message(msg)
        logger.info(f"Notification sent to {recipient}")
    except Exception as e:
        logger.error(f"Failed to send email: {e}")


def main():
    upstream_image = os.environ.get("UPSTREAM_IMAGE", "ublue-os/bazzite-nvidia-open")
    upstream_registry = os.environ.get("UPSTREAM_REGISTRY", "ghcr.io")
    namespace = os.environ.get("BB_REGISTRY_NAMESPACE")
    image_name = os.environ.get("IMAGE_NAME", "agate")
    local_image = f"{namespace}/{image_name}"
    registry = os.environ.get("BB_REGISTRY", "quay.io")
    user = os.environ.get("BB_USERNAME")
    pwd = os.environ.get("BB_PASSWORD")

    logger.info(f"Checking Upstream: {upstream_registry}/{upstream_image}")
    upstream_client = DockerRegistryClient(
        upstream_registry,
        upstream_image,
        is_ghcr=("ghcr.io" in upstream_registry.lower()),
    )

    logger.info(f"Checking Local: {registry}/{local_image}")
    local_client = DockerRegistryClient(registry, local_image, username=user, password=pwd)

    upstream_dates = {tag: upstream_client.get_created_date(tag) for tag, _ in LATEST_ONLY}
    local_dates = {tag: local_client.get_created_date(tag) for tag, _ in LATEST_ONLY}

    channels = compare(upstream_dates, local_dates, LATEST_ONLY)

    if recipes_to_build(channels):
        send_notification(channels[0].upstream, channels[0].local)
        write_key_value_file("build.env", "FORCE_BUILD", "true")
    else:
        logger.info("System is up to date. Stopping pipeline.")
        write_key_value_file("build.env", "FORCE_BUILD", "false")

    sys.exit(0)


if __name__ == "__main__":
    main()