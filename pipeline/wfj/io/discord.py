"""Discord's webhook, the one call a release announcement makes (docs/operations/release.md, ADR-072): a
`multipart/form-data` POST with the message as the `payload_json` part and each attachment as a `files[n]`
part, the way Discord's reference describes uploads. The webhook URL comes from the caller (read from the
environment at run time) and never appears in an error, a log line or anything printed: an error carries
Discord's status and the start of its answer only.
"""

from __future__ import annotations

import http.client
import json
import secrets
import urllib.error
import urllib.request
from collections.abc import Mapping, Sequence
from pathlib import PurePath
from typing import Any

# The file types Discord shows inline, with the content type their part is sent as.
CONTENT_TYPES = {
    "jpg": "image/jpeg",
    "jpeg": "image/jpeg",
    "png": "image/png",
    "webp": "image/webp",
    "gif": "image/gif",
    "mp4": "video/mp4",
    "webm": "video/webm",
    "mov": "video/quicktime",
}
BODY_PREVIEW = 300  # characters of Discord's answer an error keeps
TIMEOUT = 60
USER_AGENT = "wow-forever-japanese release (https://github.com/zyaga/wow-forever-japanese)"


class DiscordError(RuntimeError):
    pass


def content_type(name: str) -> str | None:
    """The content type of a file Discord shows inline, by its extension; None for any other file."""
    return CONTENT_TYPES.get(PurePath(name).suffix[1:].lower())


def multipart(payload: Mapping[str, Any], files: Sequence[tuple[str, bytes]]) -> tuple[bytes, str]:
    """The request body and its boundary: `payload_json`, then `files[0]`, `files[1]`, ... in the order given,
    each file part carrying the file name and the content type its extension says."""
    boundary = "wfj" + secrets.token_hex(16)
    head = f"--{boundary}\r\n".encode()
    parts = [
        head,
        b'Content-Disposition: form-data; name="payload_json"\r\nContent-Type: application/json\r\n\r\n',
        json.dumps(payload).encode("utf-8"),
        b"\r\n",
    ]
    for n, (name, data) in enumerate(files):
        kind = content_type(name) or "application/octet-stream"
        parts.extend(
            [
                head,
                f'Content-Disposition: form-data; name="files[{n}]"; filename="{name}"\r\n'.encode(),
                f"Content-Type: {kind}\r\n\r\n".encode(),
                data,
                b"\r\n",
            ]
        )
    parts.append(f"--{boundary}--\r\n".encode())
    return b"".join(parts), boundary


def post(url: str, payload: Mapping[str, Any], files: Sequence[tuple[str, bytes]]) -> dict[str, Any]:
    """Send the message and return Discord's answer (the created message, with `?wait=true`)."""
    # Refused without being repeated: a secret pasted with a stray space or line break would otherwise
    # surface in the request error, token and all.
    if not url.startswith("https://") or any(c.isspace() or ord(c) < 32 for c in url):
        raise DiscordError("the webhook URL is not a plain https URL")
    body, boundary = multipart(payload, files)
    request = urllib.request.Request(
        url + ("&" if "?" in url else "?") + "wait=true",
        data=body,
        method="POST",
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}", "User-Agent": USER_AGENT},
    )
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
            answer = response.read()
    except urllib.error.HTTPError as e:
        text = e.read().decode("utf-8", errors="replace")[:BODY_PREVIEW]
        raise DiscordError(f"Discord answered {e.code}: {text}") from None
    except urllib.error.URLError as e:
        raise DiscordError(f"Discord could not be reached: {e.reason}") from None
    except (ValueError, http.client.HTTPException) as e:
        raise DiscordError(f"the request to Discord failed: {type(e).__name__}") from None
    try:
        data = json.loads(answer)
    except ValueError:
        return {}
    return data if isinstance(data, dict) else {}
