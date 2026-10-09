"""CurseForge's upload API, the two calls a voice release makes. Modelled on the BigWigsMods packager the
main addon releases with (release.sh v2.6.1, `upload_curseforge`): the game versions from
`/api/game/wow/versions`, the file from `/api/projects/<project id>/upload-file` as multipart form data
(`metadata` JSON and `file`), the token in the `x-api-token` header. The token comes from the caller (read
from the environment at run time) and is never printed, logged or written anywhere.
"""

from __future__ import annotations

import json
import re
import secrets
import urllib.error
import urllib.request
from collections.abc import Iterator, Mapping, Sequence
from pathlib import Path
from typing import Any

SITE = "https://wow.curseforge.com"
# the packager's game version type ids; Forever's is 88568 (release.sh, upload_curseforge)
FOREVER_TYPE = 88568
CHUNK = 1 << 20


class CurseForgeError(RuntimeError):
    def __init__(self, message: str, refused: str | None = None) -> None:
        super().__init__(message)
        self.refused = refused  # the relation slug CurseForge refused (error 1018), if that was the reason


_REFUSED = re.compile(r"Invalid slug in project relations: '([a-z0-9-]+)'")


def refused_relation(body: str) -> str | None:
    """The slug an upload's answer refuses as a relation: a project that does not exist yet for CurseForge,
    such as one still in review (error 1018)."""
    try:
        data = json.loads(body)
    except ValueError:
        return None
    if not isinstance(data, dict) or data.get("errorCode") != 1018:
        return None
    m = _REFUSED.search(str(data.get("errorMessage", "")))
    return m.group(1) if m else None


def interface_version(interface: str) -> str:
    """A TOC interface number as the game version name CurseForge lists: 16001 → 1.60.1 (the packager's
    rule)."""
    n = int(interface)
    return f"{n // 10000}.{n // 100 % 100}.{n % 100}"


def game_version_id(
    versions: Sequence[Mapping[str, Any]], interface: str, type_id: int = FOREVER_TYPE
) -> int:
    """The id of the game version for `interface`, chosen as the packager chooses: the exact name, else the
    newest lower one, else the newest of that type. Raises when CurseForge lists none of the type."""
    mine = [v for v in versions if v.get("gameVersionTypeID") == type_id]
    want = interface_version(interface)
    for v in mine:
        if v.get("name") == want:
            return int(v["id"])
    lower = [v for v in mine if str(v.get("name")) < want]
    pick = max(lower or mine, key=lambda v: int(v["id"]), default=None)
    if pick is None:
        raise CurseForgeError(f"CurseForge lists no game version of type {type_id} (for {want})")
    print(f"voice release: CurseForge has no game version {want}; using {pick['name']} like the packager")
    return int(pick["id"])


def metadata(
    display_name: str,
    game_version: int,
    release_type: str,
    changelog: str,
    required: Sequence[str] = (),
) -> dict[str, Any]:
    """The upload's `metadata` field. `required`: the slugs of the projects this file requires (the entry
    names the main addon and every pack; a pack names nothing)."""
    if release_type not in ("alpha", "beta", "release"):
        raise ValueError(f"release type {release_type!r}")
    out: dict[str, Any] = {
        "displayName": display_name,
        "gameVersions": [game_version],
        "releaseType": release_type,
        "changelog": changelog,
        "changelogType": "text",
    }
    if required:
        out["relations"] = {"projects": [{"slug": s, "type": "requiredDependency"} for s in required]}
    return out


def _get(url: str, token: str) -> Any:
    req = urllib.request.Request(url, headers={"x-api-token": token})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        raise CurseForgeError(f"GET {url}: HTTP {e.code}") from e
    except urllib.error.URLError as e:
        raise CurseForgeError(f"GET {url}: {e.reason}") from e


def game_versions(token: str) -> list[dict[str, Any]]:
    return list(_get(f"{SITE}/api/game/wow/versions", token))


def _multipart(meta: Mapping[str, Any], path: Path, boundary: str) -> tuple[list[bytes], int]:
    """(head and tail parts, total length); the file itself is streamed between them."""
    head = (
        f"--{boundary}\r\n"
        'Content-Disposition: form-data; name="metadata"\r\n\r\n'
        f"{json.dumps(meta, ensure_ascii=False)}\r\n"
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="file"; filename="{path.name}"\r\n'
        "Content-Type: application/zip\r\n\r\n"
    ).encode()
    tail = f"\r\n--{boundary}--\r\n".encode()
    return [head, tail], len(head) + path.stat().st_size + len(tail)


def _body(parts: list[bytes], path: Path) -> Iterator[bytes]:
    yield parts[0]
    with path.open("rb") as f:
        while chunk := f.read(CHUNK):
            yield chunk
    yield parts[1]


def upload(project_id: int, path: Path, meta: Mapping[str, Any], token: str) -> int:
    """Uploads one zip to a project. → the new file's id. Raises naming the HTTP status (413: the file is past
    the limit in front of the API)."""
    boundary = f"wfj{secrets.token_hex(12)}"
    parts, length = _multipart(meta, path, boundary)
    req = urllib.request.Request(
        f"{SITE}/api/projects/{project_id}/upload-file",
        data=_body(parts, path),
        method="POST",
        headers={
            "x-api-token": token,
            "Content-Type": f"multipart/form-data; boundary={boundary}",
            "Content-Length": str(length),
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=1800) as r:
            raw = r.read()
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")
        raise CurseForgeError(
            f"upload of {path.name} to project {project_id}: HTTP {e.code} {body[:300]}",
            refused_relation(body),
        ) from e
    except urllib.error.URLError as e:
        raise CurseForgeError(f"upload of {path.name} to project {project_id}: {e.reason}") from e
    try:
        return int(json.loads(raw).get("id", 0))
    except (ValueError, AttributeError):
        return 0  # uploaded; the answer just names no id
