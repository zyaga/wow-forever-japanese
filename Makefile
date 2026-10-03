# WoW Forever Japanese: build entry points. See docs/operations/local-setup.md.
SHELL := /bin/bash
LUAROCKS_BIN ?= $(HOME)/.luarocks/bin
LUA      ?= luajit
LUAROCKS ?= luarocks
BUSTED   ?= $(shell command -v busted 2>/dev/null || echo $(LUAROCKS_BIN)/busted)
LUACHECK ?= $(shell command -v luacheck 2>/dev/null || echo $(LUAROCKS_BIN)/luacheck)
LUACOV   ?= $(shell command -v luacov 2>/dev/null || echo $(LUAROCKS_BIN)/luacov)
# Python: the repo venv (`.venv` in the main checkout, shared by every worktree) when it exists, else python3.
# The system python is externally managed and refuses `pip install` (docs/operations/local-setup.md).
# Without git (a tarball, say) the common dir is empty and this checkout is the root.
GIT_COMMON := $(shell git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
REPO_ROOT := $(if $(GIT_COMMON),$(abspath $(dir $(GIT_COMMON))),$(CURDIR))
VENV_PY  := $(REPO_ROOT)/.venv/bin/python
PY       ?= $(if $(wildcard $(VENV_PY)),$(VENV_PY),python3)
ADDON    := addon/WoWForeverJapanese

.PHONY: coverage-py coverage-lua lint-public report-intake report-apply coverage forever-table-counts ui-inventory tooltip-line-kinds served-columns level1-spells import-draft wago-fetch tables-extract wdb-copy wdb-preflight client-preflight import-shared-english import-client import-served rebuild-check help test test-py test-lua lint lint-py lint-lua lint-core-gate lint-no-english-in-addon lint-no-private-paths luac vectors toc-check import import-english import-collector check stats generate data validate package release forever-addons forever-titles

help:
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | sed 's/:.*## /: /'

test: test-py test-lua luac ## run every test suite (pytest, busted, luac -p)

test-py: ## pytest over pipeline/ and tests/python
	cd pipeline && $(PY) -m pytest -q ../tests/python

test-lua: ## busted specs under tests/lua (LuaJIT = Lua 5.1 semantics); luarocks path makes the rocks visible to $(LUA)
	eval "$$($(LUAROCKS) --lua-version=5.1 path)"; $(BUSTED) --lua=$(LUA) tests/lua

# Test coverage floors: one point under the measured level, because CI's interpreter and skipped tests can count
# lines differently. Raise them as coverage grows.
COV_PY_MIN  ?= 89
COV_LUA_MIN ?= 98

coverage-py: ## pytest under coverage.py; fails below COV_PY_MIN percent of the pipeline's lines
	cd pipeline && $(PY) -m coverage run -m pytest -q ../tests/python && $(PY) -m coverage report --fail-under=$(COV_PY_MIN)

coverage-lua: ## busted under luacov; fails below COV_LUA_MIN percent of the addon's logic lines (generated Data excluded)
	rm -f luacov.stats.out luacov.report.out
	eval "$$($(LUAROCKS) --lua-version=5.1 path)"; $(BUSTED) --lua=$(LUA) --coverage tests/lua && $(LUACOV)
	@test -s luacov.report.out || { echo "coverage-lua: no report written"; exit 1; }
	@total=$$(awk '/^Total/ {print $$NF}' luacov.report.out | tr -d '%'); \
	echo "coverage-lua: $$total% (floor $(COV_LUA_MIN)%)"; \
	awk -v t="$$total" -v m="$(COV_LUA_MIN)" 'BEGIN { exit (t + 0 < m + 0) }'

luac: ## every addon Lua file parses (works under LuaJIT and PUC Lua 5.1 alike)
	@for f in $$(find $(ADDON) -name '*.lua'); do $(LUA) -e "assert(loadfile('$$f'))" || exit 1; done; echo "luac: ok"

lint: lint-py lint-lua lint-core-gate lint-no-english-in-addon lint-public ## ruff + luacheck + Core/ frame-access gate + no English data in the addon + public-check

lint-py:
	cd pipeline && $(PY) -m ruff check . ../tests/python

lint-lua:
	eval "$$($(LUAROCKS) --lua-version=5.1 path)"; $(LUACHECK) $(ADDON) tests/lua --no-color

lint-core-gate: ## Core/ never touches a frame (docs/architecture/principles.md)
	@test -d $(ADDON)/Core || { echo "lint-core-gate: $(ADDON)/Core missing"; exit 1; }
	@if grep -rEn 'CreateFrame\(|_G\[|GameTooltip|QuestInfo|QuestLog|GossipFrame' $(ADDON)/Core/ ; then echo "lint-core-gate: frame access under Core/ (see docs/architecture/addon-modules.md)"; exit 1; else echo "lint-core-gate: ok"; fi

lint-no-english-in-addon: ## ADR-002: nothing under addon/ may reference data/english
	@if grep -rEn 'data/english' $(ADDON)/ ; then echo "lint-no-english-in-addon: addon references data/english"; exit 1; else echo "lint-no-english-in-addon: ok"; fi

vectors: ## regenerate vectors/{hash,align,report}_vectors.{jsonl,lua} (the Python ↔ Lua contracts)
	cd pipeline && $(PY) -m wfj.dev.gen_vectors ../vectors
	cd pipeline && $(PY) -m wfj.dev.gen_align_vectors ../vectors
	cd pipeline && $(PY) -m wfj.dev.gen_report_vectors ../vectors

lint-no-private-paths: ## no tracked file is a symlink or sits under a path the checkout keeps private
	cd pipeline && $(PY) -m wfj public-check paths

lint-public: ## no path on the author's machine, nothing the private rules name; comments explain, never record history; links resolve
	cd pipeline && $(PY) -m wfj public-check all

toc-check: ## TOC ## Interface matches pipeline/clients.toml
	cd pipeline && $(PY) -m wfj toc-check ../$(ADDON)/WoWForeverJapanese.toc clients.toml

# Inputs for the import (see docs/operations/local-setup.md). Override on the command line.
# Inputs live under <repo>/predecessors/ (gitignored); paths are absolute so the `cd pipeline` in the recipes is harmless.
# A worktree has no predecessors/ of its own: it reads the main checkout's (REPO_ROOT, beside the shared .git).
INPUTS       ?= $(or $(wildcard $(CURDIR)/predecessors),$(REPO_ROOT)/predecessors)
# Absolute even when given relative, so a recipe's `cd pipeline` reads the same files the checks did
override INPUTS := $(abspath $(INPUTS))
PRED_QUEST   ?= $(INPUTS)/classic-wow-quest-japanese-translator
PRED_TOOLTIP ?= $(INPUTS)/classic-wow-tooltips-japanese-translator
PFQUEST      ?= $(INPUTS)/pfquest-quests.lua
PFQUEST_SHA  ?= 7786596
# The clients whose English the import merges, oldest first. Each client's inputs (its table CSVs with
# their tables-source.txt stamp, questcache.wdb, the missing.txt the cache import writes) live in their own folder,
# $(INPUTS)/clients/<client>-<build>/. `import` runs every client's imports once, in this order, under
# MERGE=union: the later client's English wins where it has the line, and a line only the earlier client has keeps
# its src (ADR-020). Adding a client = one entry here + its three variables + its folder.
CLIENTS := classic-era forever
classic-era_BUILD   := 1.15.9.69722
classic-era_SRC     := wago
classic-era_PRODUCT := wow_classic_era
forever_BUILD       := 1.60.1.70170
forever_SRC         := db2
forever_PRODUCT     := wow_classic_beta
client_dir = $(INPUTS)/clients/$(1)-$($(1)_BUILD)
# The client a single-client target acts on (wago-fetch, tables-extract, wdb-copy), and
# the one each per-client step of `import` is re-invoked with. The per-client knobs below derive from it; pass
# them on the command line only to a single-client target; on `import` they would apply to every client.
CLIENT       ?= forever
ifeq ($(filter $(CLIENT),$(CLIENTS)),)
$(error CLIENT=$(CLIENT) is not one of: $(CLIENTS))
endif
CLIENT_DIR   ?= $(call client_dir,$(CLIENT))
# Non-empty when CLIENT_DIR is the client's pinned folder (not a CLIENT_DIR=<elsewhere> cross-check).
OWN_DIR       = $(filter $(call client_dir,$(CLIENT)),$(CLIENT_DIR))
# The per-client knobs given on the command line or in the environment. The targets that run every client
# (`import`, `import-english`, `rebuild-check`) refuse them: a sub-make inherits such a value, so one would pin both
# clients to it.
PER_CLIENT_VARS := CLIENT CLIENT_DIR WAGO_BUILD WDB_BUILD TABLES_SRC MERGE WDB_QUEST WAGO_QUESTV2 WDB_MISSING WAGO_ITEM \
	WAGO_SPELL WAGO_GLOBALSTRINGS WAGO_ITEMSUBCLASS WAGO_ENCHANTMENTS CLIENT_SPELL CLIENT_ITEMEFFECT CLIENT_ITEMXITEMEFFECT
per_client_overrides = $(strip $(foreach v,$(PER_CLIENT_VARS),$(if $(filter command line environment environment override,$(origin $(v))),$(v))))
ONE_CLIENT_GUARD = $(if $(per_client_overrides),{ echo "$@: runs every client in CLIENTS; $(per_client_overrides) given on the command line or in the environment would apply to all of them (set the client's pins in the Makefile; or use a single-client target with CLIENT=)"; exit 2; },true)
WAGO_ITEM    ?= $(CLIENT_DIR)/ItemSparse.csv
WAGO_SPELL   ?= $(CLIENT_DIR)/SpellName.csv
WAGO_BUILD   ?= $($(CLIENT)_BUILD)
# UI strings: the client's GlobalStrings + ItemSubClass tables at WAGO_BUILD, filtered to the curated keys.
WAGO_GLOBALSTRINGS ?= $(CLIENT_DIR)/GlobalStrings.csv
WAGO_ITEMSUBCLASS  ?= $(CLIENT_DIR)/ItemSubClass.csv
# Enchantment stat lines ("+3 Fire Spell Damage") for the `SpellItemEnchantment:*` family in ui_keys.txt.
WAGO_ENCHANTMENTS  ?= $(CLIENT_DIR)/SpellItemEnchantment.csv
UI_KEYS            ?= $(CURDIR)/pipeline/ui_keys.txt
# The client-table text families (Faction, Achievement, EmotesTextData, …; io/wago.TEXT_FAMILIES)
# are read from these clients' folders only (ADR-042). Forever is the only target (ADR-034) and the import-served step drops
# ui English no Forever table stamps, so the other clients are not asked for the tables.
FAMILY_CLIENTS     := forever
FAMILY_TABLES      := Faction Achievement Achievement_Category SkillLine SkillLineCategory EmotesTextData HolidayDescriptions CurrencyTypes CurrencyCategory SpellDispelType CreatureType QuestSort ChrCustomizationCategory ChrCustomizationOption ChrCustomizationChoice ChrCustomizationReq PVPScoreboardColumnHeader GroupFinderCategory GroupFinderActivityGrp GroupFinderActivity UiWidgetStringSource ItemNameDescription CriteriaTree RenownRewards SharedString TradeSkillCategory MailTemplate QuestInfo AreaPOI AreaPOIState PetLoyalty Map Difficulty UiEventToast BroadcastText ItemPetFood Exhaustion ItemSubClassMask RolodexType FriendshipReputation MapDifficulty MapDifficultyXCondition PlayerCondition LockType SpellFlyout ServerMessages TransmogSituation TransmogSituationTrigger TransmogOutfitSlotOption
FAMILY_ARGS         = $(if $(filter $(CLIENT),$(FAMILY_CLIENTS)),--families "$(CLIENT_DIR)/")
FAMILY_CSVS         = $(if $(filter $(CLIENT),$(FAMILY_CLIENTS)),$(foreach t,$(FAMILY_TABLES),"$(CLIENT_DIR)/$(t).csv"))
# Bump only when the inputs change: it is written into every line's provenance.imported, so a
# rerun on another day is byte-identical.
IMPORT_DATE  ?= 2026-09-13
# Lineage sources (ADR-011): the originals the Classic plugin's "CraftJapanizer" layer was cut from.
# Unzip predecessors/lineage/*.zip first (docs/operations/local-setup.md lists the downloads); only human rows are
# imported.
QJP          ?= $(INPUTS)/lineage/qjp/QuestJapanizer/QuestData.lua
QJP_VERSION  ?= 0.5.8
CJQ          ?= $(INPUTS)/lineage/cjq/CraftJapanizer_Quest/CraftJapanizer_QuestData.lua
CJQ_VERSION  ?= 2012031300
# The predecessor tag relabelled at import: "CraftJapanizer" is WoWJapanizer's label for a bulk import of the
# QuestJapanizer wiki, not a translator (ADR-011). The completeness rule rejects its cut descriptions.
RELABEL_TRANSLATOR ?= CraftJapanizer=questjapanizer-wiki
# Quest progress / completion and gossip English from the VMaNGOS world database: the SQLite
# snapshot of vmangos/core release `db_latest`, asset db-sqlite-<sha>.zip (ADR-019).
VMANGOS_DB   ?= $(INPUTS)/vmangos/mangos.sqlite
VMANGOS_SHA  ?= 13b49dc
# Quest progress / turn-in English Forever players recorded with forever-vo's addon (MIT; ADR-055): a clone of
# github.com/quinn-dougherty/forever-vo checked out at FOREVER_VO_SHA (`git -C $(FOREVER_VO) checkout <sha>`).
FOREVER_VO     ?= $(INPUTS)/forever-vo
FOREVER_VO_SHA ?= 025070f
# Blizzard's cached quest title / objectives / description: the client's questcache.wdb after a
# quest scan, copied in with `make wdb-copy`. WDB_BUILD must
# be the build in the file's header (ADR-020). QuestV2 (the client's own table) is the scan plan and the coverage denominator.
WDB_QUEST    ?= $(CLIENT_DIR)/questcache.wdb
WDB_BUILD    ?= $($(CLIENT)_BUILD)
WAGO_QUESTV2 ?= $(CLIENT_DIR)/QuestV2.csv
# The unanswered QuestV2 ids the wdb import writes: the input of a rescan.
WDB_MISSING  ?= $(CLIENT_DIR)/missing.txt
# Tooltip and buff text (Spell) and each item's Use / Equip spells (ItemEffect), for `client-text`.
CLIENT_SPELL      ?= $(CLIENT_DIR)/Spell.csv
CLIENT_ITEMEFFECT ?= $(CLIENT_DIR)/ItemEffect.csv
# The item an effect belongs to on a build whose ItemEffect has no relationship map (Forever). Passed
# when the file is there; Classic Era ships no such table and joins inline.
CLIENT_ITEMXITEMEFFECT ?= $(CLIENT_DIR)/ItemXItemEffect.csv
CLIENT_TEXT_LINK = $(if $(wildcard $(CLIENT_ITEMXITEMEFFECT)),--itemxitemeffect "$(CLIENT_ITEMXITEMEFFECT)")
WAGO_TABLES  := ItemSparse SpellName GlobalStrings ItemSubClass SpellItemEnchantment QuestV2 Spell ItemEffect
# The label the client-table imports write: `wago` for wago.tools CSVs, `db2` for the same
# tables read from an installed client with `make tables-extract`. Pinned per client with its build (ADR-021).
TABLES_SRC   ?= $($(CLIENT)_SRC)
# How an English import treats a line it does not provide. `union` keeps it, at the src that served
# it, which is what two clients need. Forever ships fewer item / spell ids than Classic Era and its server
# answers under a third of the quest ids, so `replace` would delete English for everything the newer client
# does not have. `replace` is the single-client behaviour: with two clients the later one would drop the
# earlier one's lines, so `import` / `import-english` refuse MERGE= on the command line. See ADR-020's amendments.
MERGE        ?= union
# The game client folder that holds Cache/ (e.g. .../World of Warcraft/_classic_era_). Read and copied from only,
# nothing here writes into the game folder.
WOW_DIR      ?=
# The hotfix cache `tables-extract` applies (read only); HOTFIXES= extracts the archive rows only.
HOTFIXES     ?= $(WOW_DIR)/Cache/ADB/enUS/DBCache.bin
# The .build.info product of the client in WOW_DIR (Classic Era: wow_classic_era, Forever: wow_classic_beta; a
# wrong one lists the products the install has). Follows CLIENT.
PRODUCT      ?= $($(CLIENT)_PRODUCT)

import: ## data/ from the pinned inputs (one rebuild pass: every client preflighted; predecessor repos with the wiki tag relabelled + the lineage sources; then pfQuest, VMaNGOS incl. books; then per client in CLIENTS order the quest cache, client tables incl. tooltip text and UI strings; last, drop the English for ids Forever does not serve)
	@$(ONE_CLIENT_GUARD)
	@$(MAKE) -s wdb-preflight
	cd pipeline && $(PY) -m wfj import predecessor --quest-repo $(PRED_QUEST) --tooltip-repo $(PRED_TOOLTIP) --date $(IMPORT_DATE) --relabel-translator $(RELABEL_TRANSLATOR) \
		--questjapanizer $(QJP) --qjp-version $(QJP_VERSION) --craftjapanizer-quest $(CJQ) --cjq-version $(CJQ_VERSION)
	@$(MAKE) -s import-shared-english
	@for c in $(CLIENTS); do $(MAKE) -s import-client CLIENT=$$c || exit 1; done
	@$(MAKE) -s import-served

import-english: ## refresh only data/english/ (keeps data/ lines, rulings and prior hashes → `make check` can derive stale); every client, in CLIENTS order, then the served step
	@$(ONE_CLIENT_GUARD)
	@$(MAKE) -s wdb-preflight
	@$(MAKE) -s import-shared-english
	@for c in $(CLIENTS); do $(MAKE) -s import-client CLIENT=$$c || exit 1; done
	@$(MAKE) -s import-served

# Forever is the only target (ADR-034); the other clients are inputs. After every client is merged, drop
# the English for ids Forever's own tables and quest cache do not list (quest + objective: QuestV2 and the cached ids;
# item: ItemSparse; spell: SpellName; ui: keys still stamped by another client). Forever's folder is named, not "the
# last client". The other clients' caches are read only to map an objective id to its quest. The Japanese stays in
# data/; `check` makes it no_english_id until a later harvest lists the id again.
SERVED_DIR = $(call client_dir,forever)
import-served: ## drop the English for ids the Forever tables do not list (ADR-033; run last by import / import-english)
	cd pipeline && $(PY) -m wfj import english served "$(SERVED_DIR)/QuestV2.csv" "$(SERVED_DIR)/questcache.wdb" "$(SERVED_DIR)/ItemSparse.csv" "$(SERVED_DIR)/SpellName.csv" --keys "$(UI_KEYS)" $(foreach c,$(filter-out forever,$(CLIENTS)),--map-cache "$(call client_dir,$(c))/questcache.wdb")

# The English no client serves: pfQuest, then VMaNGOS. Before every client's quest cache, which outranks pfQuest.
import-shared-english:
	cd pipeline && $(PY) -m wfj import english pfquest $(PFQUEST) --commit $(PFQUEST_SHA)
	cd pipeline && $(PY) -m wfj import english vmangos $(VMANGOS_DB) --commit $(VMANGOS_SHA)
	@test "$$(git -C "$(FOREVER_VO)" rev-parse --short=7 HEAD)" = "$(FOREVER_VO_SHA)" || { echo "import: $(FOREVER_VO) is not at FOREVER_VO_SHA $(FOREVER_VO_SHA)"; exit 1; }
	cd pipeline && $(PY) -m wfj import english forever-vo $(FOREVER_VO) --commit $(FOREVER_VO_SHA) --skip forever_vo_skipped.txt

# One client's English (CLIENT=<client>): its quest cache, then its tables (names, tooltip text, UI strings).
import-client:
	@echo "import: $(CLIENT) $(WAGO_BUILD) ($(TABLES_SRC)) from $(CLIENT_DIR)"
	cd pipeline && $(PY) -m wfj import english wdb "$(WDB_QUEST)" --build $(WDB_BUILD) --questv2 "$(WAGO_QUESTV2)" --missing "$(WDB_MISSING)" --merge $(MERGE)
	cd pipeline && $(PY) -m wfj import english wago-ids "$(WAGO_ITEM)" "$(WAGO_SPELL)" --build $(WAGO_BUILD) --src $(TABLES_SRC) --merge $(MERGE)
	cd pipeline && $(PY) -m wfj import english client-text "$(WAGO_ITEM)" "$(CLIENT_SPELL)" "$(CLIENT_ITEMEFFECT)" $(CLIENT_TEXT_LINK) --build $(WAGO_BUILD) --src $(TABLES_SRC) --merge $(MERGE)
	cd pipeline && $(PY) -m wfj import english wago-ui "$(WAGO_GLOBALSTRINGS)" "$(WAGO_ITEMSUBCLASS)" --enchantments "$(WAGO_ENCHANTMENTS)" --subtexts "$(CLIENT_SPELL)" $(FAMILY_ARGS) --keys $(UI_KEYS) --build $(WAGO_BUILD) --src $(TABLES_SRC) --merge $(MERGE)

# Before any import step writes, for every client in CLIENTS: the quest cache and QuestV2 exist, and the wdb import
# passes every check (build, layout) as a dry run. (Its shrink guard only fires for one build under
# `replace`; under union, which the two-client import always runs, a smaller cache deletes nothing.) A failing cache then stops the target before pfQuest
# replaces the wdb lines. Every client-table CSV the imports read must carry the stamp
# <src>@<build> of its client, so a stamp refusal also stops the target before any import step writes. Every
# client is checked before the first one is imported, so a broken second client cannot leave a half rebuild.
wdb-preflight:
	@for c in $(CLIENTS); do $(MAKE) -s client-preflight CLIENT=$$c || exit 1; done

client-preflight:
	@test -f "$(WDB_QUEST)" || { echo "import: $(CLIENT): no quest cache at $(WDB_QUEST) (make wdb-copy CLIENT=$(CLIENT) WOW_DIR=…)"; exit 1; }
	@test -f "$(WAGO_QUESTV2)" || { echo "import: $(CLIENT): no QuestV2 at $(WAGO_QUESTV2) (make tables-extract or make wago-fetch, CLIENT=$(CLIENT))"; exit 1; }
	@test -f "$(CLIENT_SPELL)" -a -f "$(CLIENT_ITEMEFFECT)" || { echo "import: $(CLIENT): no Spell / ItemEffect CSV in $(CLIENT_DIR) (make tables-extract or make wago-fetch, CLIENT=$(CLIENT))"; exit 1; }
	@cd pipeline && $(PY) -m wfj import english wdb "$(WDB_QUEST)" --build $(WDB_BUILD) --questv2 "$(WAGO_QUESTV2)" --merge $(MERGE) --dry-run > /dev/null
	@cd pipeline && $(PY) -m wfj.dev.tables_stamp check --src $(TABLES_SRC) --build $(WAGO_BUILD) "$(WAGO_QUESTV2)" "$(WAGO_ITEM)" "$(WAGO_SPELL)" "$(CLIENT_SPELL)" "$(CLIENT_ITEMEFFECT)" $(if $(wildcard $(CLIENT_ITEMXITEMEFFECT)),"$(CLIENT_ITEMXITEMEFFECT)") "$(WAGO_GLOBALSTRINGS)" "$(WAGO_ITEMSUBCLASS)" "$(WAGO_ENCHANTMENTS)" $(FAMILY_CSVS)
	@# The item-effect join is read in full before any import step writes, so a Forever build
	@# without its ItemXItemEffect.csv stops here instead of half-way through the import
	@cd pipeline && $(PY) -m wfj import english client-text "$(WAGO_ITEM)" "$(CLIENT_SPELL)" "$(CLIENT_ITEMEFFECT)" $(CLIENT_TEXT_LINK) --build $(WAGO_BUILD) --src $(TABLES_SRC) --merge $(MERGE) --dry-run > /dev/null
	@# wago-ui reads the spell subtexts (NameSubtext_lang) last; a Spell.csv extracted by an older tables-extract
	@# lacks the column and must stop the import here, before any step writes
	@head -1 "$(CLIENT_SPELL)" | tr -d '\r' | tr ',' '\n' | grep -qx NameSubtext_lang || { echo "import: $(CLIENT): $(CLIENT_SPELL) has no NameSubtext_lang column (re-run make tables-extract)"; exit 1; }

wago-fetch: ## download the wago.tools CSVs the imports and the scan need, at the client's build, into its folder (CLIENT=classic-era); all or nothing, then stamp them wago@WAGO_BUILD
	@$(if $(and $(OWN_DIR),$(filter-out wago,$($(CLIENT)_SRC))),{ echo "wago-fetch: CLIENT=$(CLIENT) is pinned to $($(CLIENT)_SRC) tables and not wago; its folder is not replaced (make tables-extract CLIENT=$(CLIENT); or CLIENT_DIR=<elsewhere> for a cross-check)"; exit 2; },true)
	@mkdir -p "$(CLIENT_DIR)"
	@for t in $(WAGO_TABLES); do rm -f "$(CLIENT_DIR)/$$t.csv.part"; done
	@for t in $(WAGO_TABLES); do \
		tmp="$(CLIENT_DIR)/$$t.csv.part"; \
		curl -fsSL -o "$$tmp" "https://wago.tools/db2/$$t/csv?build=$(WAGO_BUILD)&locale=enUS" || { rm -f "$(CLIENT_DIR)"/*.csv.part; echo "wago-fetch: $$t failed at $(WAGO_BUILD); no CSV replaced"; exit 1; }; \
		if [ ! -s "$$tmp" ] || head -c 200 "$$tmp" | grep -qi '<html\|<!doctype'; then rm -f "$(CLIENT_DIR)"/*.csv.part; echo "wago-fetch: $$t at $(WAGO_BUILD) is empty or not a CSV (build not on wago.tools?); no CSV replaced"; exit 1; fi; \
	done
	@cd pipeline && $(PY) -m wfj.dev.tables_stamp clear --dir "$(CLIENT_DIR)" $(WAGO_TABLES)
	@for t in $(WAGO_TABLES); do \
		mv "$(CLIENT_DIR)/$$t.csv.part" "$(CLIENT_DIR)/$$t.csv"; echo "wago-fetch: $$t.csv ($$(wc -l < "$(CLIENT_DIR)/$$t.csv" | tr -d " ") lines)"; \
	done
	@cd pipeline && $(PY) -m wfj.dev.tables_stamp write --dir "$(CLIENT_DIR)" --src wago --build $(WAGO_BUILD) $(WAGO_TABLES)

tables-extract: ## read the client tables from the installed game into the client's folder (read-only, no network; all or nothing): WOW_DIR=<client folder> [CLIENT=forever] [HOTFIXES=]
	@test -n "$(WOW_DIR)" || { echo "usage: make tables-extract WOW_DIR=<client folder, e.g. .../World of Warcraft/_classic_beta_> [CLIENT=forever]"; exit 2; }
	@test -d "$(WOW_DIR)" || { echo "tables-extract: no folder $(WOW_DIR)"; exit 1; }
	@$(if $(and $(OWN_DIR),$(filter-out db2,$($(CLIENT)_SRC))),{ echo "tables-extract: CLIENT=$(CLIENT) is pinned to $($(CLIENT)_SRC) tables and not db2; its folder is not replaced (make wago-fetch CLIENT=$(CLIENT); or CLIENT_DIR=<elsewhere> for a cross-check)"; exit 2; },true)
	@mkdir -p "$(CLIENT_DIR)"
	W="$$(cd "$(WOW_DIR)/.." && pwd)" && H="$(HOTFIXES)" && case "$$H" in ""|/*) ;; *) H="$$PWD/$$H";; esac && \
		cd pipeline && $(PY) -m wfj.dev.client_tables --wow "$$W" --product "$(PRODUCT)" --out "$(CLIENT_DIR)" --expect-build $(WAGO_BUILD) $${H:+--hotfixes "$$H"}

forever-table-counts: ## row counts of the no-content windows' client tables and TraitSubTree, from the installed client (read-only; re-run per build): WOW_DIR=<client folder> [HOTFIXES=]
	@test -n "$(WOW_DIR)" || { echo "usage: make forever-table-counts WOW_DIR=<client folder, e.g. .../World of Warcraft/_classic_beta_>"; exit 2; }
	@test -d "$(WOW_DIR)" || { echo "forever-table-counts: no folder $(WOW_DIR)"; exit 1; }
	W="$$(cd "$(WOW_DIR)/.." && pwd)" && H="$(HOTFIXES)" && case "$$H" in ""|/*) ;; *) H="$$PWD/$$H";; esac && \
		cd pipeline && $(PY) -m wfj.dev.table_counts --wow "$$W" --product "$(forever_PRODUCT)" $${H:+--hotfixes "$$H"}

wdb-copy: ## copy the client's quest cache into WDB_QUEST, its client folder (read-only on the game folder): WOW_DIR=<client folder> [CLIENT=forever]
	@test -n "$(WOW_DIR)" || { echo "usage: make wdb-copy WOW_DIR=<client folder holding Cache/, e.g. .../World of Warcraft/_classic_beta_> [CLIENT=forever]"; exit 2; }
	@test -f "$(WOW_DIR)/Cache/WDB/enUS/questcache.wdb" || { echo "wdb-copy: no Cache/WDB/enUS/questcache.wdb under $(WOW_DIR) (did the client Exit Game?)"; exit 1; }
	@# The folder is pinned to one build; a cache of another build (the client patched) is never copied over it
	@W="$$(cd "$(WOW_DIR)" && pwd)/Cache/WDB/enUS/questcache.wdb" && cd pipeline && $(PY) -c 'import sys; from pathlib import Path; from wfj.io.wdb import read_ids; b = read_ids(Path(sys.argv[1]))[0]; sys.exit(None if str(b) == sys.argv[2].rsplit(".", 1)[-1] else "wdb-copy: the cache is build %s, CLIENT=%s is pinned to %s; nothing copied (a new build gets its own pin and folder)" % (b, sys.argv[3], sys.argv[2]))' "$$W" $(WDB_BUILD) $(CLIENT)
	@mkdir -p "$$(dirname "$(WDB_QUEST)")"
	@if [ -f "$(WDB_QUEST)" ]; then cp "$(WDB_QUEST)" "$(WDB_QUEST).prev"; echo "wdb-copy: previous copy kept as $(WDB_QUEST).prev"; fi
	cp "$(WOW_DIR)/Cache/WDB/enUS/questcache.wdb" "$(WDB_QUEST)"

level1-spells: ## regenerate pipeline/level1_spells.txt (the spells a fresh level-1 character has) from the installed Forever client: WOW_DIR=<client folder> [PRODUCT=wow_classic_beta]
	@test -n "$(WOW_DIR)" || { echo "usage: make level1-spells WOW_DIR=<client folder, e.g. .../World of Warcraft/_classic_beta_> [PRODUCT=wow_classic_beta]"; exit 2; }
	@test -d "$(WOW_DIR)" || { echo "level1-spells: no folder $(WOW_DIR)"; exit 1; }
	@W="$$(cd "$(WOW_DIR)/.." && pwd)" && cd pipeline && \
		$(PY) -m wfj.dev.level1_spells --wow "$$W" --product "$(PRODUCT)" > level1_spells.txt.part && \
		mv level1_spells.txt.part level1_spells.txt
	@head -1 pipeline/level1_spells.txt

# Every text column of every client table the Forever install ships, and the rows its hotfix cache adds
# (pipeline/served_columns.txt; tests/python/test_served_inventory.py needs a disposition for each in
# pipeline/served_dispositions.txt). The archive root names no files, so the community listfile names the
# tables: refresh it per build like the UI extract's (docs/operations/beta-day-harvest.md). Prints what the
# build added, dropped or changed against the committed file.
LISTFILE ?= $(INPUTS)/community-listfile.csv

served-columns: ## regenerate pipeline/served_columns.txt from the installed client (commit the result; read-only, no network): WOW_DIR=<client folder> [LISTFILE=<community listfile>] [HOTFIXES=]
	@test -n "$(WOW_DIR)" || { echo "usage: make served-columns WOW_DIR=<client folder, e.g. .../World of Warcraft/_classic_beta_> [LISTFILE=<csv>] [HOTFIXES=<DBCache.bin>]"; exit 2; }
	@test -d "$(WOW_DIR)" || { echo "served-columns: no folder $(WOW_DIR)"; exit 1; }
	@test -f "$(LISTFILE)" || { echo "served-columns: no listfile at $(LISTFILE) (LISTFILE=<community listfile>)"; exit 1; }
	@W="$$(cd "$(WOW_DIR)/.." && pwd)" && H="$(HOTFIXES)" && case "$$H" in "") H="$$(cd "$(WOW_DIR)" && pwd)/Cache/ADB/enUS/DBCache.bin"; test -f "$$H" || H="";; /*) ;; *) H="$$PWD/$$H";; esac && \
		L="$(LISTFILE)" && C="$$(cd "$(WOW_DIR)" && pwd)" && cd pipeline && \
		$(PY) -m wfj.dev.served_columns --wow "$$W" --product "$(forever_PRODUCT)" --listfile "$$L" \
			$${H:+--hotfixes "$$H"} --wdb "$$C/Cache/WDB/enUS" --previous served_columns.txt > served_columns.txt.part && \
		mv served_columns.txt.part served_columns.txt
	@sed -n 3,5p pipeline/served_columns.txt

# The Forever (camelot) inventory, the only one (Forever is the only target). FOREVER_UI is a UI extract of the Forever client (`python -m wfj.dev.client_ui
# --product wow_classic_beta --out <dir>`, lowercased paths are fine) and FOREVER_GLOBALSTRINGS its GlobalStrings table
# (`make tables-extract` against the Forever install); both default under INPUTS.
FOREVER_UI            ?= $(INPUTS)/forever-ui-$(forever_BUILD)/interface/addons
FOREVER_GLOBALSTRINGS ?= $(call client_dir,forever)/GlobalStrings.csv

ui-inventory: ## regenerate pipeline/ui_inventory.txt from a Forever UI extract + its GlobalStrings (commit the result): [FOREVER_UI=<Interface/AddOns>] [FOREVER_GLOBALSTRINGS=<csv>]
	@test -d "$(FOREVER_UI)" || { echo "ui-inventory: no UI extract at $(FOREVER_UI) (FOREVER_UI=<extract>/interface/addons)"; exit 1; }
	@test -f "$(FOREVER_GLOBALSTRINGS)" || { echo "ui-inventory: no GlobalStrings at $(FOREVER_GLOBALSTRINGS) (FOREVER_GLOBALSTRINGS=<csv>)"; exit 1; }
	cd pipeline && $(PY) -m wfj.dev.ui_inventory "$(FOREVER_UI)" "$(FOREVER_GLOBALSTRINGS)" > ui_inventory.txt.tmp && mv ui_inventory.txt.tmp ui_inventory.txt
	cd pipeline && $(PY) -m wfj.dev.ui_loadset "$(FOREVER_UI)" "$(FOREVER_GLOBALSTRINGS)" > ui_loadset.txt.tmp && mv ui_loadset.txt.tmp ui_loadset.txt

tooltip-line-kinds: ## regenerate pipeline/tooltip_line_kinds_inventory.txt and tooltip_data_types_inventory.txt from a Forever UI extract (commit the result): [FOREVER_UI=<Interface/AddOns>]
	@test -d "$(FOREVER_UI)" || { echo "tooltip-line-kinds: no UI extract at $(FOREVER_UI) (FOREVER_UI=<extract>/interface/addons)"; exit 1; }
	cd pipeline && $(PY) -m wfj.dev.tooltip_line_kinds "$(FOREVER_UI)" > tooltip_line_kinds_inventory.txt.tmp && mv tooltip_line_kinds_inventory.txt.tmp tooltip_line_kinds_inventory.txt
	cd pipeline && $(PY) -m wfj.dev.tooltip_line_kinds --types "$(FOREVER_UI)" > tooltip_data_types_inventory.txt.tmp && mv tooltip_data_types_inventory.txt.tmp tooltip_data_types_inventory.txt

# Every Blizzard addon the Forever (camelot) client loads, resolved from the TOCs in the same FOREVER_UI extract
# (its client_ui path list must include the addons' .toc files). pipeline/forever_addon_dispositions.txt gives each
# in-game addon a disposition; tests/python/test_forever_windows.py holds the two together.
forever-addons: ## regenerate pipeline/forever_addons.txt from the Forever UI extract's TOCs (commit the result): [FOREVER_UI=<Interface/AddOns>]
	@test -d "$(FOREVER_UI)" || { echo "forever-addons: no UI extract at $(FOREVER_UI) (FOREVER_UI=<extract>/interface/addons)"; exit 1; }
	cd pipeline && $(PY) -m wfj.dev.client_addons "$(FOREVER_UI)" > forever_addons.txt.tmp && mv forever_addons.txt.tmp forever_addons.txt

forever-titles: ## list every SetTitle( call site in the camelot load sets (the input of pipeline/forever_titles.txt): [FOREVER_UI=<Interface/AddOns>]
	@test -d "$(FOREVER_UI)" || { echo "forever-titles: no UI extract at $(FOREVER_UI) (FOREVER_UI=<extract>/interface/addons)"; exit 1; }
	@cd pipeline && $(PY) -m wfj.dev.client_addons --titles "$(FOREVER_UI)"

# A player's SavedVariables file (WoWForeverJapanese.lua) handed off through the collector-dump issue template.
DUMP ?=

import-collector: ## add one collector dump to data/english/ (replaces stand-in lines, keeps the client's own files): DUMP=<file>
	@test -n "$(DUMP)" || { echo "usage: make import-collector DUMP=<path to WoWForeverJapanese.lua>"; exit 2; }
	@D="$(DUMP)"; case "$$D" in /*) ;; *) D="$$PWD/$$D";; esac; \
		cd pipeline && $(PY) -m wfj import english collector "$$D"

# A machine draft (ADR-014): DRAFT=<file.jsonl> TYPE=<type> NAME=<draft name> MODEL=<model id> [CRITIC=<id>] DATE=<YYYY-MM-DD>
# [REVERIFY=1] (ui, quest, objective, item, spell): every named line records the current English, so a stale line is judged fresh.
import-draft: ## merge machine-drafted text into data/ as `machine` variants (never edits hand-written text)
	@test -n "$(DRAFT)" -a -n "$(TYPE)" -a -n "$(NAME)" -a -n "$(MODEL)" -a -n "$(DATE)" || { echo "usage: make import-draft DRAFT=<file> TYPE=<type> NAME=<name> MODEL=<id> [CRITIC=<id>] DATE=<YYYY-MM-DD> [REVERIFY=1]"; exit 2; }
	cd pipeline && $(PY) -m wfj import draft $(TYPE) $(abspath $(DRAFT)) --model $(MODEL) $(if $(CRITIC),--critic $(CRITIC)) --date $(DATE) --name $(NAME) $(if $(REVERIFY),--reverify)

check: ## assign statuses to every data/ line (pure rules); --report prints the yield
	cd pipeline && $(PY) -m wfj check --report

stats: ## coverage report over data/ (no writes)
	cd pipeline && $(PY) -m wfj stats

coverage: ## how much of the game ships in Japanese → docs/operations/coverage.md (run before every data pull request)
	cd pipeline && $(PY) -m wfj.dev.coverage --out ../docs/operations/coverage.md --build $(forever_BUILD)

report-intake: ## a player's fix report (GitHub issue ISSUE=N, or a saved body REPORT=<file> ISSUE=N) → batches/reports/issue-N/triage.jsonl
	@test -n "$(ISSUE)" || { echo "usage: make report-intake ISSUE=<n> [REPORT=<saved issue body>] [CREDIT=<name>] [FORCE=1]"; exit 2; }
	cd pipeline && $(PY) -m wfj report intake $(if $(REPORT),--file $(abspath $(REPORT)) --number $(ISSUE),--issue $(ISSUE)) $(if $(CREDIT),--credit "$(CREDIT)") $(if $(FORCE),--force)

report-apply: ## batches/reports/issue-N/decisions.jsonl → data/ + readings + ATTRIBUTION.md + reply.md, then check / generate / validate / coverage
	@test -n "$(ISSUE)" -a -n "$(MODEL)" || { echo "usage: make report-apply ISSUE=<n> MODEL=<id> [DATE=YYYY-MM-DD]"; exit 2; }
	cd pipeline && $(PY) -m wfj report apply --issue $(ISSUE) --model $(MODEL) $(if $(DATE),--date $(DATE))
	$(MAKE) -s check generate validate coverage

generate: ## data/ → addon Data/*.lua + the TOC's generated block (deterministic; validate diffs it)
	cd pipeline && $(PY) -m wfj generate

data: import check generate ## import → check → generate. Rebuilds imported text from the pinned inputs; corrections, rulings (ADR-012) and prior english hashes are carried, so a changed English is `stale`
	cd pipeline && $(PY) -m wfj generate

# The rebuild proof. From an empty data/english, `make data` over every client's pinned inputs must give back
# the committed data/ and the addon's generated files. Refuses a dirty data/ or addon (nothing is deleted then);
# otherwise the tree is what HEAD has again after a pass, and any difference is printed and fails the target.
rebuild-check: ## empty data/english (collector lines kept), run `make data` from the pinned inputs of every client, fail on any difference from HEAD (needs a clean data/ + addon)
	@$(ONE_CLIENT_GUARD)
	@test -z "$$(git status --porcelain -- data $(ADDON) pipeline Makefile)" || { echo "rebuild-check: data/, $(ADDON), pipeline/ or the Makefile has uncommitted changes; commit or restore them first"; git status --short -- data $(ADDON) pipeline Makefile | head; exit 1; }
	@$(MAKE) -s wdb-preflight
	@for f in "$(PRED_QUEST)" "$(PRED_TOOLTIP)" "$(QJP)" "$(CJQ)" "$(PFQUEST)" "$(VMANGOS_DB)" "$(FOREVER_VO)" "$(UI_KEYS)"; do test -e "$$f" || { echo "rebuild-check: shared input missing: $$f; nothing deleted"; exit 1; }; done
	@# the collector's lines (English a client recorded in game) are no pinned input's: kept, ADR-053
	cd pipeline && $(PY) -m wfj.dev.reset_english ../data/english
	@# one job, stop at the first error: `data` is import → check → generate over the files just deleted
	@$(MAKE) -s -j1 -S data || { echo "rebuild-check: the rebuild failed part-way; restore the tree with: git checkout -- data $(ADDON) && git clean -fd -- data $(ADDON)"; exit 1; }
	@if [ -n "$$(git status --porcelain -- data $(ADDON))" ]; then git status --short -- data $(ADDON) | head -40; git diff --stat -- data $(ADDON) | tail -1; echo "rebuild-check: the rebuild differs from HEAD"; exit 1; fi
	@echo "rebuild-check: data/ and $(ADDON) rebuilt byte for byte"

# VALIDATE_FLAGS="--base origin/main" adds the human-never-overwritten check against that ref (CI does on PRs).
validate: ## the CI gate: schema, provenance rule, key collisions, referential integrity, regenerate-and-diff, then luac
	cd pipeline && $(PY) -m wfj validate $(VALIDATE_FLAGS)
	$(MAKE) -s luac

# The BigWigsMods packager, pinned to the commit the Release workflow uses (v2.6.1). It needs bash 4 or newer.
PACKAGER_SHA  := e50a250f8705041e40f2fa1ddcb280a686d65aa0
PACKAGER      := build/packager-$(PACKAGER_SHA)/release.sh
PACKAGER_BASH ?= $(if $(wildcard /opt/homebrew/bin/bash),/opt/homebrew/bin/bash,bash)

$(PACKAGER):
	@mkdir -p $(dir $@)
	curl -fsSL -o $@.part https://raw.githubusercontent.com/BigWigsMods/packager/$(PACKAGER_SHA)/release.sh && mv $@.part $@

GIT_ID := -c user.name=package -c user.email=package@localhost

package: $(PACKAGER) ## rehearse the next release locally: build + check its zip from the committed tree (nothing is pushed or uploaded)
	@$(PACKAGER_BASH) -c '[ "$${BASH_VERSINFO[0]}" -ge 4 ]' || { echo "package: the packager needs bash 4+ (macOS: brew install bash)"; exit 1; }
	rm -rf build/package-src build/WoWForeverJapanese-*.zip
	git clone --quiet --no-local . build/package-src
	git -C build/package-src checkout --quiet $$(git rev-parse HEAD)
	cd build/package-src && export PYTHONPATH="$$PWD/pipeline" && version=$$($(PY) -m wfj release next-version | sed -n 's/^version=//p') && [ -n "$$version" ] \
	  && $(PY) -m wfj release changelog --version "$$version" --date "$$(date -u +%F)" --notes .release-notes.md \
	  && git $(GIT_ID) commit --quiet -m "Release $$version" -- CHANGELOG.md \
	  && git $(GIT_ID) tag -a "v$$version" -m "Release $$version" \
	  && { $(PACKAGER_BASH) $(abspath $(PACKAGER)) -d > ../package.log 2>&1 || { echo "package: the packager failed, see build/package.log"; exit 1; }; } \
	  && $(PY) -m wfj package-check .release/*.zip --version "$$version" \
	  && cp .release/*.zip .. && echo "package: build/$$(basename .release/*.zip) (packager log: build/package.log)"

# VERSION is taken from the command line only (`make release VERSION=1.0.0`), never from the environment.
RELEASE_VERSION := $(if $(filter command line,$(origin VERSION)),$(VERSION))

release: ## start the Release workflow on GitHub and follow it to the end: [VERSION=x.y.z] (needs the GitHub CLI)
	@command -v gh >/dev/null || { echo "release: needs the GitHub CLI (gh), signed in"; exit 1; }
	@last=$$(gh run list --workflow release.yml --limit 1 --json databaseId --jq '.[0].databaseId // 0') || exit 1; \
	out=$$(gh workflow run release.yml --ref main $(if $(RELEASE_VERSION),-f version=$(RELEASE_VERSION)) 2>&1) || { echo "$$out"; exit 1; }; \
	id=$$(printf '%s\n' "$$out" | grep -o 'https://[^ ]*/actions/runs/[0-9]*' | head -1 | sed 's#.*/##'); \
	for _ in $$(seq 30); do \
	  [ -n "$$id" ] && break; sleep 2; \
	  id=$$(gh run list --workflow release.yml --event workflow_dispatch --limit 1 --json databaseId \
	    --jq "[.[] | select(.databaseId > $$last)][0].databaseId // empty"); \
	done; \
	[ -n "$$id" ] || { echo "release: the run did not appear; see the Actions tab"; exit 1; }; \
	echo "release: run $$id"; gh run watch "$$id" --exit-status

# Targets kept outside the repository (the quest scan); absent in a public checkout.
-include Makefile.private
