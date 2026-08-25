from __future__ import annotations

import hashlib
import json
from typing import Any


def request_fingerprint(route: str, body: dict[str, Any]) -> str:
    encoded = json.dumps({"route": route, "body": body}, sort_keys=True, separators=(",", ":"), default=str)
    return hashlib.sha256(encoded.encode("utf-8")).hexdigest()

