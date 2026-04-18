#!/usr/bin/env python3

from datetime import datetime


def parse_iso_datetime(date_str):
    if not date_str:
        return None

    normalized = date_str.replace("Z", "+00:00")
    try:
        return datetime.fromisoformat(normalized)
    except ValueError:
        if "." in normalized and "+" in normalized:
            main, tz = normalized.rsplit("+", 1)
            try:
                return datetime.fromisoformat(f"{main[:26]}+{tz}")
            except ValueError:
                return None
        return None


def write_key_value_file(path, key, value):
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(f"{key}={value}\n")
