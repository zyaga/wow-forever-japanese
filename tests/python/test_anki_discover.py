"""The Anki add-on finds the game's folders, and never names a file outside them."""

from pathlib import Path

from anki_addon import FIXTURES  # noqa: F401  (puts the add-on on the path)

from wfj_anki import discover


def game(tmp_path: Path, accounts: dict[str, list[str]]) -> Path:
    root = tmp_path / "World of Warcraft"
    for client, names in accounts.items():
        for name in names:
            folder = root / client / "WTF" / "Account" / name / "SavedVariables"
            folder.mkdir(parents=True)
            (folder / discover.SAVED_NAME).write_text("WFJ_Anki = {}\n", encoding="utf-8")
    return root


def test_every_client_and_account_under_the_game_folder(tmp_path):
    root = game(tmp_path, {"_forever_": ["ONE", "TWO"], "_retail_": ["ONE"]})
    (root / "_classic_era_" / "WTF" / "Account" / "ONE" / "SavedVariables").mkdir(parents=True)  # no saved file
    (root / "Data").mkdir()
    found = discover.saved_files(root)
    assert [(f.client.name, f.path.parts[-3]) for f in found] == [
        ("_forever_", "ONE"), ("_forever_", "TWO"), ("_retail_", "ONE")]
    assert all(f.path.name == "WoWForeverJapanese.lua" for f in found)


def test_a_client_folder_works_as_the_folder_too(tmp_path):
    root = game(tmp_path, {"_forever_": ["ONE"], "_retail_": ["ONE"]})
    found = discover.saved_files(root / "_forever_")
    assert [f.client for f in found] == [root / "_forever_"]


def test_a_folder_that_is_not_the_game_gives_nothing(tmp_path):
    assert discover.saved_files(tmp_path) == []
    assert discover.saved_files(tmp_path / "missing") == []


def test_the_chosen_folder_is_used_alone(tmp_path):
    chosen = game(tmp_path / "chosen", {"_forever_": ["ONE"]})
    game(tmp_path / "Volumes" / "Disk", {"_forever_": ["OTHER"]})
    found = discover.find(str(chosen), "Darwin", tmp_path / "home", tmp_path / "Volumes")
    assert [f.path.parts[-3] for f in found] == ["ONE"]
    empty = tmp_path / "empty"
    empty.mkdir()
    assert discover.find(str(empty), "Darwin", tmp_path / "home", tmp_path / "Volumes") == []


def test_with_no_folder_chosen_the_usual_places_are_tried(tmp_path):
    game(tmp_path / "Volumes" / "Disk" / "Games", {"_forever_": ["ONE"]})
    found = discover.find("", "Darwin", tmp_path / "home", tmp_path / "Volumes")
    assert [f.path.parts[-3] for f in found] == ["ONE"]
    assert discover.find("  ", "Darwin", tmp_path / "home", tmp_path / "none") == []


def test_the_usual_places_per_system(tmp_path):
    mac = discover.default_roots("Darwin", Path("/Users/someone"), tmp_path / "none")
    assert Path("/Applications/World of Warcraft") in mac
    windows = discover.default_roots("Windows", Path("C:/Users/someone"))
    assert Path("C:/Program Files (x86)/World of Warcraft") in windows
    assert Path("D:/Games/World of Warcraft") in windows
    assert discover.default_roots("Linux", Path("/home/someone"))


def test_the_signature_changes_when_a_saved_file_does(tmp_path):
    root = game(tmp_path, {"_forever_": ["ONE"]})
    files = discover.saved_files(root)
    before = discover.signature(files)
    assert before == discover.signature(files)
    files[0].path.write_text("WFJ_Anki = { 1 }\n", encoding="utf-8")
    assert discover.signature(files) != before


def test_media_paths_stay_inside_the_client(tmp_path):
    client = tmp_path / "_forever_"
    assert discover.screenshot(client, "WoWScrnShot_112526_101500.jpg") == client / "Screenshots" / "WoWScrnShot_112526_101500.jpg"
    for bad in ("", "../secret.jpg", "a/b.jpg", "..", "C:\\x\\y.jpg", "/etc/passwd"):
        assert discover.screenshot(client, bad) is None
    assert discover.sound(client, "WoWForeverJapanese_VoiceA/Sound/a-1.mp3") == \
        client / "Interface" / "AddOns" / "WoWForeverJapanese_VoiceA" / "Sound" / "a-1.mp3"
    assert discover.sound(client, "WoWForeverJapanese_VoiceA\\Sound\\a-1.mp3") is not None
    for bad in ("", "a-1.mp3", "OtherAddon/Sound/a.mp3", "WoWForeverJapanese_VoiceA/Sound/../x.mp3",
                "WoWForeverJapanese_VoiceA/Other/a.mp3", "../WoWForeverJapanese_VoiceA/Sound/a.mp3",
                "WoWForeverJapanese_VoiceA/Sound/b/a.mp3"):
        assert discover.sound(client, bad) is None
