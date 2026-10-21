#!/usr/bin/env python3

"""Backend-agnostic channel comparison shared by the CI update checks.

Both GitHub Actions and GitLab decide whether to rebuild by comparing the
creation date of an upstream tag against the date of the local image carrying
the same tag. Only the way those dates are fetched differs, so the comparison
and the decision live here.

A pipeline should pass only the channels it actually publishes; otherwise a
bump on a channel it never builds triggers pointless rebuilds.
"""

import logging
from dataclasses import dataclass
from datetime import datetime
from typing import Dict, Iterable, List, Optional, Sequence, Tuple


logger = logging.getLogger(__name__)

# tag -> recipe. Ordered by build priority.
CHANNELS: Tuple[Tuple[str, str], ...] = (
    ("latest", "recipe.yml"),
    ("testing", "recipe-testing.yml"),
)

# Channels published by the GitLab mirror.
LATEST_ONLY: Tuple[Tuple[str, str], ...] = (("latest", "recipe.yml"),)


@dataclass(frozen=True)
class Channel:
    """A single tag/recipe pair and the dates backing the decision."""

    tag: str
    recipe: str
    upstream: Optional[datetime]
    local: Optional[datetime]

    @property
    def needs_build(self) -> bool:
        if self.upstream is None:
            logger.error(f"[{self.tag}] could not fetch upstream date. Building anyway.")
            return True

        if self.local is None:
            logger.warning(f"[{self.tag}] no local image found. Assuming first build.")
            return True

        if self.upstream > self.local:
            logger.info(f"[{self.tag}] update available. Upstream: {self.upstream}, Local: {self.local}")
            return True

        logger.info(f"[{self.tag}] is up to date. Upstream: {self.upstream}, Local: {self.local}")
        return False


def compare(
    upstream_dates: Dict[str, datetime],
    local_dates: Dict[str, datetime],
    channels: Sequence[Tuple[str, str]] = CHANNELS,
) -> List[Channel]:
    """Pair each channel's upstream and local dates into a Channel."""
    return [
        Channel(tag=tag, recipe=recipe, upstream=upstream_dates.get(tag), local=local_dates.get(tag))
        for tag, recipe in channels
    ]


def recipes_to_build(channels: Iterable[Channel]) -> List[str]:
    """Recipes needing a build, in channel order."""
    return [channel.recipe for channel in channels if channel.needs_build]