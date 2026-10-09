#!/usr/bin/env python3

"""Tag retention policy shared by the CI tag cleaners.

GitHub Packages and Docker Registry v2 expose the same information in
different shapes. Each cleaner normalises its backend's output into
``ImageItem`` records and then delegates the keep/delete decision here, so the
age and count thresholds are tuned in exactly one place.

Policy, in order:
  1. a tag listed in ``protected_tags`` is always kept;
  2. otherwise the ``max_keep`` most recent images are kept;
  3. otherwise any image younger than ``max_age_days`` is kept.

Protected tags do not consume the ``max_keep`` budget, and cosign signatures
are never counted as images -- a signature survives if and only if the image it
signs survives.
"""

import logging
import os
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Dict, Iterable, List, Optional, Sequence, Set, Tuple


logger = logging.getLogger(__name__)

# Tags that must survive regardless of age. GitHub publishes both channels;
# the GitLab mirror only publishes latest.
LATEST_PROTECTED: Tuple[str, ...] = ("latest", "latest-cache")
ALL_PROTECTED: Tuple[str, ...] = ("latest", "latest-cache", "testing", "testing-cache")


def signature_tag(digest: str) -> str:
    """The tag cosign uses for the signature of ``digest``."""
    return f"{digest.replace(':', '-')}.sig"


def digest_from_signature_tag(tag: str) -> str:
    """Inverse of :func:`signature_tag`."""
    return tag.removesuffix(".sig").replace("-", ":")


@dataclass(frozen=True)
class ImageItem:
    """One tag or signature, normalised across backends."""

    label: str
    """Human-readable identifier used in log lines."""

    digest: str
    """Image digest in colon form. For signatures, the digest that was signed."""

    date: datetime

    tags: Tuple[str, ...] = field(default_factory=tuple)
    is_signature: bool = False
    handle: Optional[str] = None
    """Backend-specific identifier used to delete this item."""


def select_active_digests(
    items: Iterable[ImageItem],
    max_age_days: int,
    max_keep: int,
    protected_tags: Sequence[str] = (),
) -> Set[str]:
    """Return the digests that must survive, ignoring signatures."""
    images = sorted(
        (item for item in items if not item.is_signature),
        key=lambda item: item.date,
        reverse=True,
    )

    protected = set(protected_tags)
    now = datetime.now(timezone.utc)

    active: Set[str] = set()
    kept = 0

    for item in images:
        if protected.intersection(item.tags):
            logger.info(f"Keeping {item.label} (protected tag)")
            active.add(item.digest)
            continue

        if kept < max_keep:
            logger.info(f"Keeping {item.label} (within the {max_keep} most recent)")
            active.add(item.digest)
            kept += 1
            continue

        age_days = (now - item.date).days
        if age_days <= max_age_days:
            logger.info(f"Keeping {item.label} ({age_days}d old, limit {max_age_days}d)")
            active.add(item.digest)

    return active


def split_keep_delete(
    items: Iterable[ImageItem],
    active_digests: Set[str],
) -> Tuple[List[ImageItem], List[ImageItem]]:
    """Partition ``items`` into (keep, delete) using ``active_digests``."""
    keep: List[ImageItem] = []
    delete: List[ImageItem] = []

    for item in items:
        # A signature lives exactly as long as the image it signs.
        survives = item.digest in active_digests
        (keep if survives else delete).append(item)

    return keep, delete


def retention_from_env(protected_tags: Sequence[str] = ()) -> Tuple[int, int, Tuple[str, ...]]:
    """Read MAX_AGE_DAYS, MAX_KEEP and the protected tag list from the environment."""
    return (
        int(os.environ.get("MAX_AGE_DAYS", 7)),
        int(os.environ.get("MAX_KEEP", 5)),
        tuple(protected_tags),
    )


def by_date_desc(items: Iterable[ImageItem]) -> List[ImageItem]:
    """Newest first, for readable build logs."""
    return sorted(items, key=lambda item: item.date, reverse=True)


def summarize(kept: Sequence[ImageItem], deleted: Sequence[ImageItem], scope: str) -> Dict[str, int]:
    logger.info(f"{scope}: keeping {len(kept)}, deleting {len(deleted)}")
    return {"kept": len(kept), "deleted": len(deleted)}