"""The add-on's own words, in English and Japanese. Anki's language decides which is shown."""

from __future__ import annotations

from . import plan
from .sync import Result

T = {
    "menu": ("WoW Forever Japanese", "WoW Forever Japanese"),
    "sync": ("Sync now", "今すぐ同期"),
    "again": ("Add deleted cards again", "削除したカードをもう一度追加"),
    "deleted": (
        "{n} word(s) have no card because you deleted it. Tools → WoW Forever Japanese → Add deleted cards again brings them back.",
        "{n} 語はカードを削除したため追加していません。ツール → WoW Forever Japanese →「削除したカードをもう一度追加」で戻せます。",
    ),
    "settings": ("Settings…", "設定…"),
    "reset": ("WoW Forever Japanese: reset to the game's data", "WoW Forever Japanese：ゲームのデータに戻す"),
    "title": ("WoW Forever Japanese", "WoW Forever Japanese"),
    "intro": (
        "Words you save in the game become cards here. New words arrive after a /reload or a logout in the game.",
        "ゲームで保存した単語がここでカードになります。新しい単語は、ゲームで /reload かログアウトをしたあとに届きます。",
    ),
    "folder": ("World of Warcraft folder", "World of Warcraft のフォルダ"),
    "folder_hint": ("Leave empty to look in the usual places", "空欄なら通常の場所を探します"),
    "browse": ("Browse…", "参照…"),
    "choose": ("Choose your World of Warcraft folder", "World of Warcraft のフォルダを選んでください"),
    "found_game": ("{game}: {n} word(s) for Anki.", "{game}：Anki 用の単語 {n} 語。"),
    "found_old": (
        "{game}: nothing for Anki yet. Update the addon in that game, then /reload once.",
        "{game}：Anki 用のデータがまだありません。そのゲームのアドオンを更新して、一度 /reload してください。",
    ),
    "not_found": (
        "No saved word list found here. Choose the folder named World of Warcraft, and save a word in the game first.",
        "ここには単語帳が見つかりません。World of Warcraft という名前のフォルダを選んでください。先にゲームで単語を保存しておく必要があります。",
    ),
    "front": ("Front of the card", "カードの表"),
    "front_sentence": ("The whole sentence, with the word marked", "文全体（単語に印）"),
    "front_word": ("The word alone", "単語だけ"),
    "audio": ("The sentence's audio plays", "文の音声を再生するのは"),
    "audio_back": ("With the answer", "答えを見たとき"),
    "audio_front": ("With the question too", "問題のときにも"),
    "choices_hint": (
        "These change every card at once, old ones too.",
        "すでにあるカードも含め、すべてのカードが一度に変わります。",
    ),
    "save": ("Save", "保存"),
    "close": ("Close", "閉じる"),
    "last": ("Last sync", "前回の同期"),
    "never": ("No sync yet.", "まだ同期していません。"),
    "nothing": ("Up to date: {words} word(s), nothing to change.", "最新です：{words}語、変更なし。"),
    "done": (
        "{added} new, {updated} updated ({words} word(s) in the game).",
        "新規 {added}、更新 {updated}（ゲームの単語：{words}語）。",
    ),
    "missing_images": (
        "{n} screenshot(s) not found in the Screenshots folder.",
        "スクリーンショット {n} 件が Screenshots フォルダに見つかりません。",
    ),
    "missing_audio": (
        "{n} sentence(s) have sound files that were not found (is the voice pack installed?).",
        "{n} 文の音声ファイルが見つかりません（音声パックは入っていますか？）。",
    ),
    "newer": (
        "The game's addon is newer than this add-on. Update the add-on to read its word list.",
        "ゲームのアドオンのほうが新しいバージョンです。単語帳を読むにはこのアドオンを更新してください。",
    ),
    "old_addon": (
        "The word list was found, but the game's addon has not written it for Anki yet. Update the addon in the "
        "game, then /reload once.",
        "単語帳は見つかりましたが、ゲームのアドオンがまだ Anki 用のデータを書き出していません。ゲームのアドオンを更新して、一度 /reload してください。",
    ),
    "tip_old_addon": (
        "WoW Forever Japanese: your word list was found, but the game's addon is too old to send it to Anki. Update the addon in the game, then /reload once.",
        "WoW Forever Japanese：単語帳は見つかりましたが、ゲームのアドオンが古く、Anki に送れません。ゲームのアドオンを更新して、一度 /reload してください。",
    ),
    "tip_newer": (
        "WoW Forever Japanese: the game's addon is newer than this add-on. Update this add-on (Tools → Add-ons → Check for Updates) to read your word list.",
        "WoW Forever Japanese：ゲームのアドオンのほうが新しいバージョンです。単語帳を読むには、このアドオンを更新してください（ツール → アドオン → アップデートを確認）。",
    ),
    "tip_not_found": (
        "WoW Forever Japanese: no saved word list was found. Choose your World of Warcraft folder in Tools → WoW Forever Japanese → Settings.",
        "WoW Forever Japanese：保存された単語帳が見つかりません。ツール → WoW Forever Japanese → 設定 で World of Warcraft のフォルダを選んでください。",
    ),
    "tip_added": (
        "WoW Forever Japanese: {added} new, {updated} updated",
        "WoW Forever Japanese：新規 {added}、更新 {updated}",
    ),
    "tip_reset": (
        "WoW Forever Japanese: {updated} note(s) reset",
        "WoW Forever Japanese：{updated} 件を戻しました",
    ),
    "failed": (
        "WoW Forever Japanese could not sync: {error}",
        "WoW Forever Japanese の同期に失敗しました：{error}",
    ),
}


def get(key: str, japanese: bool, **values: object) -> str:
    return T[key][1 if japanese else 0].format(**values)


def found(games: list[tuple[str, int, bool]], japanese: bool) -> str:
    """What the folder holds, a game a line."""
    if not games:
        return get("not_found", japanese)
    lines = []
    for game, words, ready in games:
        name = plan.game_label(game) or "World of Warcraft"
        lines.append(get("found_game" if ready else "found_old", japanese, game=name, n=words))
    return "\n".join(lines)


def notice(result: Result, japanese: bool) -> str:
    """What a sync nobody asked for says when it could read no word list, so a player whose cards never come
    learns why without opening the menu. Nothing when the sync could read one."""
    if result.files == 0:
        return get("tip_not_found", japanese)
    if result.newer:
        return get("tip_newer", japanese)
    if result.tables == 0:
        return get("tip_old_addon", japanese)
    return ""


def summary(result: Result | None, japanese: bool) -> str:
    """The last sync in words, one point a line."""
    if result is None:
        return get("never", japanese)
    lines = []
    if result.files == 0:
        lines.append(get("not_found", japanese))
    elif result.newer:
        lines.append(get("newer", japanese))
    elif result.tables == 0:
        lines.append(get("old_addon", japanese))
    elif result.added or result.updated:
        lines.append(get("done", japanese, added=result.added, updated=result.updated, words=result.words))
    else:
        lines.append(get("nothing", japanese, words=result.words))
    if result.deleted:
        lines.append(get("deleted", japanese, n=result.deleted))
    if result.missing_images:
        lines.append(get("missing_images", japanese, n=result.missing_images))
    if result.missing_audio:
        lines.append(get("missing_audio", japanese, n=result.missing_audio))
    return "\n".join(lines)
