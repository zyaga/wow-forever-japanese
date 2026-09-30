# CurseForge description

The text of the addon's CurseForge project page. It is the README condensed; when one changes, change the other.
Paste everything under "Description" into the project's description with the editor set to Markdown. The
`<span style="color:…">` tags are the editor's own colour syntax. The images load from the repository's `main`
branch; leave them out until the repository is public.

- **Project name:** WoW Forever Japanese (日本語化)
- **Summary:** Play WoW Forever in Japanese: quests, NPC dialogue, tooltips and menus, with the English one
  key away.
- **Categories:** Quests & Leveling; also Tooltip, Chat & Communication, Miscellaneous.

## Description

![The quest window in Japanese](https://raw.githubusercontent.com/zyaga/wow-forever-japanese/main/docs/images/hero.jpg)

<span style="color:#E8C77E;">**日本語の説明は下にあります。**</span>

**WoW Forever Japanese** shows World of Warcraft: Forever in Japanese. The game's own <span style="color:#8CB8E8;">English</span> is always one key away: hold <span style="color:#E0605A;">**Alt**</span> and it comes back, let go and the Japanese returns. It is for players who read Japanese, and for learners who want to play in it.

### <span style="color:#E8C77E;">What it translates</span>

- **Quests:** the quest window, the quest log and the objective lines in the tracker.
- **NPC dialogue:** the talk window, speech bubbles, NPC lines in chat and boss emotes.
- **Books, letters and plaques.**
- **Item and spell tooltips**, and buff and debuff text, with the game's live numbers filled in.
- **The interface:** windows, labels, menus, popups and messages.

Names of people, places, creatures, items and spells stay in <span style="color:#8CB8E8;">English</span> everywhere, so you can still talk with other players, read guides and search by name.

### <span style="color:#E8C77E;">Popup dictionary</span>

Point at a Japanese word in quest text, NPC dialogue, a book page or a window label, and a small popup shows its reading, its dictionary form and a short English meaning of the word as that sentence uses it. Nothing is drawn until the pointer is on a word.

![The popup dictionary showing a word's reading and meaning](https://raw.githubusercontent.com/zyaga/wow-forever-japanese/main/docs/images/word-card.jpg)

### <span style="color:#E8C77E;">Settings</span>

**Esc > Options > AddOns**, or type **/wfj config**. Turn translation on or off, for everything or per area; change the key you hold for English; set a key that switches translation on and off; turn the markers (<span style="color:#FFD100;">**[未翻訳 / Not Translated]**</span>, <span style="color:#FFD100;">**[要更新 / English Changed]**</span>), the popup dictionary and the minimap button on or off.

### <span style="color:#E8C77E;">What the addon records</span>

When the game shows English the addon has no translation for, the addon notes that English in its saved settings file, so it can be translated later. Your character's name is stored as a placeholder; no account, realm or location is stored. Nothing is sent anywhere: the file stays on your computer unless you choose to attach it to an issue. You can turn it off under **English Collector** in the settings.

### <span style="color:#E8C77E;">Install</span>

Install it with the CurseForge app (make sure your **Forever** install is selected), or unzip the download into your Forever client's `Interface/AddOns` folder. World of Warcraft: Forever only; no other addons or libraries needed.

### <span style="color:#E8C77E;">Report a translation problem</span>

Click the <span style="color:#E0605A;">**字**</span> minimap button (or type **/wfj fix**), pick the line you just read, choose what is wrong, and paste the report into the form on GitHub: https://github.com/zyaga/wow-forever-japanese/issues

### <span style="color:#E8C77E;">Credits</span>

The hand-written translations are the work of the Japanese translators of WoWJapanizer, QuestJapanizer and CraftJapanizer_Quest, listed by name in `ATTRIBUTION.md`, which ships inside the addon. Lines those projects did not cover are machine-drafted and marked as such in the project's data.

### <span style="color:#E8C77E;">License</span>

GPL-2.0-or-later. Website: https://foreverjapanese.com. Source and translation data: https://github.com/zyaga/wow-forever-japanese. The bundled font is IPA UI Gothic, under the IPA Font License v1.0.

This addon is made by fans. It is not affiliated with or endorsed by Blizzard Entertainment. Game screenshots: ©2004 Blizzard Entertainment, Inc. All rights reserved. World of Warcraft, Warcraft and Blizzard Entertainment are trademarks or registered trademarks of Blizzard Entertainment, Inc. in the U.S. and/or other countries.

---

## <span style="color:#E8C77E;">日本語</span>

**WoW Forever Japanese** は、World of Warcraft: Forever を日本語で遊べるようにするアドオンです。<span style="color:#E0605A;">**Alt**</span> キーを押している間だけゲーム本来の<span style="color:#8CB8E8;">英語</span>が表示され、離すと日本語に戻ります。日本語で遊びたい方にも、日本語を勉強中の方にもおすすめです。

### <span style="color:#E8C77E;">翻訳される内容</span>

- **クエスト:** クエストウィンドウ、クエストログ、トラッカーの目標
- **NPC の会話:** 会話ウィンドウ、吹き出し、チャットに流れる NPC のセリフ、ボスのエモート
- **本・手紙・銘板**
- **アイテムと呪文のツールチップ**、バフ・デバフの説明（数値はゲームの実際の値が入ります）
- **インターフェース:** ウィンドウ、ラベル、メニュー、ポップアップ、メッセージ

人物・地名・モンスター・アイテム・呪文の名前はすべて<span style="color:#8CB8E8;">英語</span>のままです。ほかのプレイヤーとの会話や、攻略情報の検索にそのまま使えます。

### <span style="color:#E8C77E;">ポップアップ辞書</span>

クエスト本文、NPC の会話、本のページ、ウィンドウのラベルで日本語の単語にマウスを合わせると、読み方・辞書形・その文脈での短い英語の意味が小さなポップアップに表示されます。マウスを合わせるまでは何も表示されません。

### <span style="color:#E8C77E;">設定</span>

**Esc > オプション > AddOns**、または **/wfj config** で開きます。翻訳のオン・オフ（全体または項目ごと）、英語を表示するキーの変更、翻訳を切り替えるキーの設定、マーカー（<span style="color:#FFD100;">**[未翻訳 / Not Translated]**</span>、<span style="color:#FFD100;">**[要更新 / English Changed]**</span>）・ポップアップ辞書・ミニマップボタンの表示を切り替えられます。

### <span style="color:#E8C77E;">アドオンが記録するもの</span>

ゲームに表示された英語のうち、アドオンに日本語訳がないものは、あとで翻訳できるようにアドオンの設定ファイルに記録されます。キャラクター名はプレースホルダーに置き換えて保存し、アカウント・レルム・位置は保存しません。どこにも送信されません。自分で Issue に添付しない限り、ファイルはあなたのパソコンの中にあります。設定の **英語テキスト収集** でオフにできます。

### <span style="color:#E8C77E;">インストール</span>

CurseForge アプリでインストールしてください（**Forever** のインストール先が選ばれていることを確認）。手動の場合は、ダウンロードした zip を Forever クライアントの `Interface/AddOns` フォルダに展開します。World of Warcraft: Forever 専用です。ほかのアドオンやライブラリは不要です。

### <span style="color:#E8C77E;">翻訳の問題を報告する</span>

ミニマップの <span style="color:#E0605A;">**字**</span> ボタン（または **/wfj fix**）を押し、直前に読んだ行を選んで何が問題かを選び、表示された報告文を GitHub のフォームに貼り付けてください: https://github.com/zyaga/wow-forever-japanese/issues

### <span style="color:#E8C77E;">クレジット</span>

手書きの翻訳は、WoWJapanizer、QuestJapanizer、CraftJapanizer_Quest の翻訳者の皆さんによるものです。翻訳者の名前はアドオンに同梱の `ATTRIBUTION.md` に記載しています。これらのプロジェクトが扱っていない行は機械で下訳したもので、データ上でその旨を記録しています。

### <span style="color:#E8C77E;">ライセンス</span>

GPL-2.0-or-later。ウェブサイト: https://foreverjapanese.com 。ソースコードと翻訳データ: https://github.com/zyaga/wow-forever-japanese 。同梱のフォントは IPA UI ゴシック（IPA フォントライセンス v1.0）です。

このアドオンはファンが制作したものです。Blizzard Entertainment とは関係がなく、承認も受けていません。ゲーム画面: ©2004 Blizzard Entertainment, Inc. All rights reserved. World of Warcraft、Warcraft、Blizzard Entertainment は、米国およびその他の国における Blizzard Entertainment, Inc. の商標または登録商標です。
