#!/usr/bin/env python3

import logging
import os
import smtplib
import ssl
import sys
from email.message import EmailMessage

from scripts.ci.common import write_key_value_file
from scripts.ci.registry import DockerRegistryClient


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
    upstream_image = os.environ.get("UPSTREAM_IMAGE", "ublue-os/bazzite-dx-nvidia")
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
    ud = upstream_client.get_created_date("latest")

    logger.info(f"Checking Local: {registry}/{local_image}")
    local_client = DockerRegistryClient(registry, local_image, username=user, password=pwd)
    ld = local_client.get_created_date("latest")

    if not ud:
        logger.error("Could not fetch upstream date.")
        write_key_value_file("build.env", "FORCE_BUILD", "true")
        sys.exit(0)

    if not ld:
        logger.warning("Could not fetch local date. Assuming first build.")
        write_key_value_file("build.env", "FORCE_BUILD", "true")
        sys.exit(0)

    logger.info(f"Upstream Date: {ud}")
    logger.info(f"Local Date:    {ld}")

    if ud > ld:
        logger.info("Update Available. Proceeding to build.")
        send_notification(ud, ld)
        write_key_value_file("build.env", "FORCE_BUILD", "true")
        sys.exit(0)

    logger.info("System is up to date. Stopping pipeline.")
    write_key_value_file("build.env", "FORCE_BUILD", "false")
    sys.exit(0)


if __name__ == "__main__":
    main()
