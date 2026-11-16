"""The voices the addon offers for the character's error lines (Core/ErrorVoices.lua) are the ones the pipeline
makes: every player race and sex, and every NPC voice of the cast (ADR-093)."""

from __future__ import annotations

import re
from pathlib import Path

from wfj.cmd import voice_make

ROOT = Path(__file__).resolve().parents[2]
LUA = ROOT / "addon" / "WoWForeverJapanese" / "Core" / "ErrorVoices.lua"


def test_the_addon_offers_the_npc_voices_the_pipeline_makes():
    text = LUA.read_text(encoding="utf-8")
    offered = re.findall(r'\{ "(q[a-z0-9]+)", "[mf]", "[a-z]+" \}', text)
    assert len(offered) == len(set(offered))
    cfg = voice_make.load_config(ROOT / "pipeline" / "voice.toml")
    assert sorted(offered) == voice_make.npc_voices(ROOT / "data", cfg)


def test_the_addon_offers_every_player_race():
    text = LUA.read_text(encoding="utf-8")
    assert re.findall(r'\{ player = "([a-z]+)"', text) == list(voice_make.PLAYER_RACES)
