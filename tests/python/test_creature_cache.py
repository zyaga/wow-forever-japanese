"""The client's creature cache read for each creature's display ids (the voice panel's heads)."""

import struct

import pytest
from wfj.io import creature_cache
from wfj.io.creature_cache import CreatureCacheError, read_displays


@pytest.fixture
def fixture(root):
    # three records cut from the Forever 1.60.1.70938 cache: a plain NPC, a titled one, one with two models
    return root / "tests/fixtures/wdb-creature/creaturecache-70938.wdb"


def test_the_cache_gives_each_creature_its_display_ids(fixture):
    build, displays = read_displays(fixture)
    assert build == 70938
    # the first two agree with VMaNGOS display_id1: Tog Rustsprocket and Carla Granger (a titled NPC)
    assert displays[6119] == [4864]
    assert displays[1291] == [1439]
    assert displays[8419] == [7729, 7730]
    assert sorted(displays) == [1291, 6119, 8419]


def test_a_build_with_no_pinned_layout_is_refused(fixture, tmp_path):
    buf = bytearray(fixture.read_bytes())
    struct.pack_into("<I", buf, 4, 99999)
    path = tmp_path / "creaturecache.wdb"
    path.write_bytes(bytes(buf))
    with pytest.raises(CreatureCacheError, match="build 99999 has no pinned"):
        read_displays(path)


def test_a_file_that_is_not_a_creature_cache_is_refused(root):
    quest = next((root / "tests/fixtures/wdb").glob("*.wdb"))
    with pytest.raises(CreatureCacheError, match="not a creature cache"):
        read_displays(quest)


def _display_list_at(payload: bytes) -> int:
    lay = creature_cache.layout_for(70938)
    return creature_cache._display_list_offset(payload, lay)


def test_a_display_list_that_does_not_add_up_is_an_error(fixture, tmp_path):
    buf = bytearray(fixture.read_bytes())
    first_len = struct.unpack_from("<I", buf, 28)[0]
    payload = bytes(buf[32 : 32 + first_len])
    at = 32 + _display_list_at(payload)
    struct.pack_into("<f", buf, at + 4, 7.5)  # the stated total no longer matches the entries' probabilities
    path = tmp_path / "creaturecache.wdb"
    path.write_bytes(bytes(buf))
    with pytest.raises(CreatureCacheError, match="creature 6119: display list"):
        read_displays(path)


def test_a_creature_cached_twice_is_reported(fixture, tmp_path):
    buf = fixture.read_bytes()
    first_len = struct.unpack_from("<I", buf, 28)[0]
    first = buf[24 : 32 + first_len]
    path = tmp_path / "creaturecache.wdb"
    path.write_bytes(buf[:24] + first + buf[24:])
    with pytest.raises(CreatureCacheError, match="creature 6119 is cached twice"):
        read_displays(path)
