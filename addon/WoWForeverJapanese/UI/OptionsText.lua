-- UI/OptionsText.lua: the settings pages' own copy, English + Japanese. Setting labels live on their
-- definitions (`label` / `ja`); everything else the pages say lives here. Addon interface text, not game text: no
-- data/ entry, no provenance. `%s` placeholders appear the same number of times, in the same order, in both. Longer
-- help copy breaks between sentences with "\n" (the same break in both languages) rather than wrapping mid-sentence.
local _, WFJ = ...
local Text = {}
WFJ.OptionsText = Text

Text.T = {
  ["page.main"] = { en = "WoW Forever Japanese (日本語化)", ja = "WoW Forever Japanese (日本語化)" },
  ["page.collector"] = { en = "English Collector", ja = "英語テキスト収集" },
  ["page.about"] = { en = "About & Help", ja = "情報とヘルプ" },
  ["page.voice"] = { en = "Voice", ja = "音声" },
  ["tagline"] = {
    en = "Japanese quest, NPC and tooltip text. Hold a key for the game's English.",
    ja = "クエスト・NPC・ツールチップを日本語で。キーを押している間は英語で表示します。",
  },

  ["section.translation"] = { en = "Translation", ja = "翻訳" },
  ["section.areas"] = { en = "What to translate", ja = "翻訳する範囲" },
  ["section.markers"] = { en = "Markers", ja = "マーカー" },
  ["section.voice"] = { en = "Japanese voice", ja = "日本語の音声" },
  ["section.voiceKinds"] = { en = "What to read aloud", ja = "読み上げる内容" },
  ["section.collector"] = { en = "Collector", ja = "収集" },
  ["section.files"] = { en = "Sending it in", ja = "送り方" },
  ["section.help"] = { en = "How it works", ja = "使い方" },
  ["section.slash"] = { en = "Slash commands", ja = "スラッシュコマンド" },

  ["toggleKey"] = { en = "Turn translation on / off", ja = "翻訳のオン・オフ切り替え" },
  ["key.notSet"] = { en = "Not set", ja = "未設定" },

  ["button.capture"] = { en = "Change", ja = "変更" },
  ["button.capturing"] = { en = "Press a key", ja = "キーを押す" },
  ["button.setKey"] = { en = "Set key", ja = "キーを設定" },
  ["button.unbind"] = { en = "Unbind", ja = "解除" },
  ["button.replace"] = { en = "Replace", ja = "置き換える" },
  ["button.settings"] = { en = "Settings", ja = "設定" },

  ["warn.takeover"] = {
    en = "%s is used for \"%s\". While this addon is loaded, %s shows English instead.",
    ja = "%s は「%s」に割り当てられています。このアドオンが有効な間は、%s で英語が表示されます。",
  },
  ["warn.toggleConflict"] = {
    en = "%s is already the key for turning translation on / off.",
    ja = "%s はすでに翻訳のオン・オフ切り替えに使われています。",
  },
  ["warn.revealConflict"] = {
    en = "%s is already the key for showing English.",
    ja = "%s はすでに英語表示のキーに使われています。",
  },
  ["warn.bindReplace"] = { en = "%s is used for \"%s\". Replace it?", ja = "%s は「%s」に割り当てられています。置き換えますか？" },
  ["warn.combat"] = { en = "Keys can't be changed in combat.", ja = "戦闘中はキーを変更できません。" },
  ["warn.afterCombat"] = { en = "%s takes effect after combat.", ja = "%s は戦闘終了後に有効になります。" },
  ["warn.addonChanges"] = {
    en = "Apply or cancel your AddOn changes first.",
    ja = "先にアドオンの変更を適用またはキャンセルしてください。",
  },

  ["collector.explain"] = {
    en = "The addon notes English it has no translation for.\n"
      .. "Nothing is sent anywhere unless you send it yourself with the steps below.",
    ja = "翻訳がない英語テキストを記録します。\n"
      .. "下の手順で自分で送らない限り、どこにも送信されることはありません。",
  },
  ["collector.status"] = { en = "Status", ja = "状態" },
  -- the status line in the page's language (the slash command keeps Collector.describe's English)
  ["collector.statusLine"] = { en = "%s · %s entries · %s of %s", ja = "%s・%s件・%s / %s" },
  ["collector.on"] = { en = "on", ja = "オン" },
  ["collector.off"] = { en = "off", ja = "オフ" },
  ["collector.full"] = { en = "full", ja = "上限に達しました" },
  ["collector.paused"] = { en = "paused (file from a newer version)", ja = "一時停止（新しいバージョンのファイル）" },
  ["collector.errors"] = { en = "%s errors", ja = "エラー%s件" },
  ["collector.path"] = {
    en = "Too long to paste? Zip this file and attach it to the same issue:",
    ja = "貼り付けられない長さなら、このファイルを zip にして同じ Issue に添付：",
  },
  ["collector.steps"] = {
    en = "1. Click Send English.\n"
      .. "2. Copy the link in the window (click it, then Ctrl+C) and open it in your web browser.\n"
      .. "3. If the window shows a second box, copy that text into the form's box too.\n"
      .. "4. Submit the issue on GitHub, then click I sent it.",
    ja = "1.「英語を送る」をクリックします。\n"
      .. "2. ウィンドウのリンクをコピーして（クリックして Ctrl+C）、ブラウザで開きます。\n"
      .. "3. ウィンドウに2つ目の欄があれば、その文字列もフォームの欄に貼り付けます。\n"
      .. "4. GitHub で Issue を送信してから「送信しました」をクリックします。",
  },
  ["collector.send"] = { en = "Send English", ja = "英語を送る" },
  ["send.title"] = { en = "Send collected English", ja = "記録した英語を送る" },
  ["send.summary.empty"] = {
    en = "Nothing new to send. /wfj collector send all sends every line again.",
    ja = "新しく送るものはありません。/wfj collector send all ですべての行をもう一度送れます。",
  },
  ["send.summary.unavailable"] = {
    en = "This game client cannot pack the text, so the saved file goes with the issue instead.",
    ja = "このゲームクライアントでは文字列にまとめられないため、代わりに保存ファイルを Issue に添付します。",
  },
  ["send.summary.readonly"] = {
    en = "The saved file is from a newer version of the addon. Update the addon to send it.",
    ja = "保存ファイルは新しいバージョンのアドオンのものです。送るにはアドオンを更新してください。",
  },
  ["send.summary"] = {
    en = "%s lines to send in one issue (%s already in Japanese, left out).",
    ja = "1つの Issue で %s 行を送ります（日本語訳がある %s 行は除きます）。",
  },
  ["send.step1"] = {
    en = "1. Copy this link (click it, then Ctrl+C) and open it in your web browser:",
    ja = "1. このリンクをコピーして（クリックして Ctrl+C）、ブラウザで開きます：",
  },
  ["send.step2.link"] = { en = "2. The form opens filled in.", ja = "2. 入力済みのフォームが開きます。" },
  ["send.step2.paste"] = {
    en = "2. Copy this text too (click it, then Ctrl+C) and paste it into the form:",
    ja = "2. この文字列もコピーして（クリックして Ctrl+C）、フォームに貼り付けます：",
  },
  ["send.step2.file"] = {
    en = "2. Zip this file and drag it into the form (/reload first saves it):",
    ja = "2. このファイルを zip にしてフォームにドラッグします（先に /reload で保存）：",
  },
  ["send.step3"] = { en = "3. Submit the issue on GitHub.", ja = "3. GitHub で Issue を送信します。" },
  ["send.step4"] = { en = "4. Then click:", ja = "4. 送信したらクリック：" },
  ["send.sent"] = { en = "I sent it", ja = "送信しました" },
  ["send.later"] = {
    en = "%s new lines are not in the file yet: /reload, then open this again.",
    ja = "新しい %s 行はまだファイルにありません。/reload してから開き直してください。",
  },
  ["send.markedFull"] = {
    en = "%s lines marked as sent. Full: Clear collected English makes room.",
    ja = "%s 行を送信済みにしました。上限です。「記録した英語を消去」で空きを作れます。",
  },
  ["send.marked"] = {
    en = "%s lines marked as sent. The next send holds only new lines.",
    ja = "%s 行を送信済みにしました。次回は新しい行だけを送ります。",
  },
  -- the report window (UI/ReportWindow): a bug or an idea; its link and I sent it reuse send.step1 / step4 / sent
  ["report.title"] = { en = "Report a bug or an idea", ja = "不具合・提案を送る" },
  ["report.bug"] = { en = "Bug", ja = "不具合" },
  ["report.idea"] = { en = "Idea", ja = "提案" },
  ["report.summary.errors"] = {
    en = "%s new Lua errors from this addon go with the report.",
    ja = "このアドオンの新しい Lua エラー %s 件を報告に含めます。",
  },
  ["report.summary.none"] = {
    en = "No new Lua errors from this addon. Build and version go with it.",
    ja = "新しい Lua エラーはありません。ビルドとバージョンを送ります。",
  },
  ["report.summary.other"] = {
    en = "Another addon (BugSack or similar) catches Lua errors: paste ours from it.",
    ja = "別のアドオン（BugSack など）がエラーを取得中。そこから貼り付けてください。",
  },
  ["report.summary.idea"] = {
    en = "Ideas and code changes go to GitHub.",
    ja = "提案やコードの変更は GitHub に送ります。",
  },
  ["report.step2.link"] = {
    en = "2. The form opens with build, version and errors filled in.",
    ja = "2. ビルド・バージョン・エラーが入力済みのフォームが開きます。",
  },
  ["report.step2.paste"] = {
    en = "2. Copy this text (click, Ctrl+C) into the form's Lua errors box:",
    ja = "2. この文字列をコピーして、フォームの Lua エラー欄に貼り付けます：",
  },
  ["report.step3"] = {
    en = "3. Write what happened, then submit the issue on GitHub.",
    ja = "3. 起きたことを書いて、GitHub で Issue を送信します。",
  },
  ["report.idea.step2"] = {
    en = "2. Write your idea, then submit the issue on GitHub.",
    ja = "2. 提案を書いて、GitHub で Issue を送信します。",
  },
  ["report.marked"] = {
    en = "%s errors marked as sent. The next report holds only new ones.",
    ja = "%s 件を送信済みにしました。次回は新しいエラーだけを送ります。",
  },
  ["about.bug"] = {
    en = "Something not working, or an idea? Send it from here.",
    ja = "不具合や提案は、ここから送れます。",
  },
  ["button.reportBug"] = { en = "Report a bug or idea", ja = "不具合・提案を報告" },
  ["collector.clear"] = { en = "Clear collected English", ja = "記録した英語を消去" },
  ["collector.confirm"] = { en = "Click again to clear %s entries", ja = "もう一度クリックで%s件を消去" },
  ["collector.cleared"] = { en = "Cleared %s entries", ja = "%s件を消去しました" },

  ["about.open"] = {
    en = "Open settings: Esc > Options > AddOns  /  the AddOn List's \"Settings\"  /  /wfj config",
    ja = "設定の開き方：Esc → オプション → アドオン　／　アドオン一覧の「設定」　／　/wfj config",
  },
  -- %s: the reveal key's name ("Alt", "Mouse Button 4")
  ["about.hold"] = {
    en = "Hold %s to see the game's own English; let go to return to Japanese.",
    ja = "%sを押している間はゲーム本来の英語を表示し、離すと日本語に戻ります。",
  },
  ["about.readings"] = {
    en = "Point at a Japanese word in a quest or NPC window to see its reading.",
    ja = "クエストやNPCの画面で日本語の単語にカーソルを合わせると、読み方が表示されます。",
  },
  -- the About page's voice line (UI/Options aboutVoice); %s: the packs that loaded, in the line's language
  ["about.voice.none"] = {
    en = "Japanese voice: not installed. Add \"WoW Forever Japanese Voice\" in the CurseForge app, or copy its page:",
    ja = "日本語音声：未インストール。CurseForge アプリで「WoW Forever Japanese Voice」を追加するか、ページをコピー：",
  },
  ["about.voice.loaded"] = { en = "Japanese voice: %s", ja = "日本語音声：%s" },
  -- %s, %s: the two markers as they show (WFJ.MARKER.stale, .missing)
  ["about.markers"] = {
    en = "%s  the English changed after translation.\n%s  this line has no translation yet.",
    ja = "%s　翻訳後に英語が変わった行です。\n%s　まだ翻訳がない行です。",
  },
  -- the line under a page title: version, memory, how much data ships
  ["header.data"] = { en = "data: %s quests · %s items · %s spells · %s UI strings",
    ja = "データ：クエスト %s・アイテム %s・呪文 %s・UI文字列 %s" },
  ["header.noData"] = { en = "data: none", ja = "データ：なし" },
  ["header.noMemory"] = { en = "memory n/a", ja = "メモリ不明" },

  -- the fix window (UI/FixWindow) and the About page's way into it
  ["about.fix"] = {
    en = "Spotted a wrong or awkward line? Pick it from the lines you just saw.",
    ja = "翻訳の間違いや不自然な文を見つけたら、表示された行から選んで報告できます。",
  },
  ["button.reportLine"] = { en = "Report a line", ja = "翻訳を報告" },
  ["fix.title"] = { en = "Report a translation", ja = "翻訳の報告" },
  ["fix.tab.recent"] = { en = "Translations", ja = "翻訳" },
  ["fix.tab.pending"] = { en = "Pending (%s)", ja = "送信待ち（%s）" },
  ["fix.tab.copy"] = { en = "Send report", ja = "報告を送る" },
  ["fix.recent.explain"] = {
    en = "Lines shown this session, newest first. Click the one to report.",
    ja = "このセッションで表示された行（新しい順）。報告する行をクリックしてください。",
  },
  ["fix.filter.story"] = { en = "Quests & NPCs", ja = "クエスト・会話" },
  ["fix.filter.tooltips"] = { en = "Tooltips", ja = "ツールチップ" },
  ["fix.filter.windows"] = { en = "Windows", ja = "画面の文字" },
  ["fix.filter.all"] = { en = "All", ja = "すべて" },
  ["fix.recent.empty"] = {
    en = "Nothing yet. Read some quest or NPC text, then open this again.",
    ja = "まだありません。クエストやNPCの文章を読んでから、もう一度開いてください。",
  },
  ["fix.edit.reason"] = { en = "What is wrong?", ja = "どこがおかしいですか？" },
  ["fix.edit.note"] = { en = "Note (optional)", ja = "メモ（任意）" },
  ["fix.edit.ja"] = { en = "The line. Rewrite it if you like (optional)", ja = "この文です。直せる場合は書き換えてください（任意）" },
  ["reason.wrong"] = { en = "Wrong meaning", ja = "意味が違う" },
  ["reason.awkward"] = { en = "Awkward / unnatural", ja = "不自然な日本語" },
  ["reason.typo"] = { en = "Typo / broken text", ja = "誤字・表示の崩れ" },
  ["reason.name"] = { en = "A name was changed", ja = "名前が変えられている" },
  ["reason.other"] = { en = "Other", ja = "その他" },
  ["button.saveFix"] = { en = "Save", ja = "保存" },
  ["button.back"] = { en = "Back", ja = "戻る" },
  ["button.delete"] = { en = "Delete", ja = "削除" },
  ["button.clearSent"] = { en = "Clear sent reports", ja = "送信済みの報告を消去" },
  ["fix.saved"] = { en = "Saved. Send it from Send report.", ja = "保存しました。「報告を送る」から送れます。" },
  ["fix.unavailable"] = {
    en = "Saving is unavailable: the addon's saved settings did not load. Try /reload.",
    ja = "保存できません：アドオンの保存設定が読み込まれていません。/reload をお試しください。",
  },
  ["fix.noReason"] = { en = "Pick what is wrong first.", ja = "先に、どこがおかしいかを選んでください。" },
  ["fix.exists"] = {
    en = "This line is already saved. Click again to replace it.",
    ja = "この行は保存済みです。もう一度クリックすると置き換えます。",
  },
  ["fix.full"] = {
    en = "%s reports are waiting. Send them and clear them first.",
    ja = "%s件の報告が送信待ちです。先に送って消去してください。",
  },
  ["fix.tooLong"] = { en = "The note or your version is too long.", ja = "メモまたは書き換えた文が長すぎます。" },
  ["fix.deleted"] = { en = "Deleted.", ja = "削除しました。" },
  ["fix.pending.explain"] = {
    en = "Saved reports, kept until you clear them. Click one to change or delete it.",
    ja = "保存した報告（消去するまで残ります）。クリックすると変更・削除できます。",
  },
  ["fix.pending.empty"] = { en = "Nothing saved yet.", ja = "保存された報告はありません。" },
  ["fix.copy.step1"] = {
    en = "1. Open the report form: click the address, Ctrl+C, paste it into your browser.",
    ja = "1. 報告フォームを開く：アドレスをクリックしてCtrl+C、ブラウザに貼り付けます。",
  },
  ["fix.copy.step2"] = {
    en = "2. Copy the report: click it (it selects itself), then Ctrl+C.",
    ja = "2. 報告をコピー：クリックすると全体が選択されます。Ctrl+Cでコピーします。",
  },
  ["fix.copy.step3"] = {
    en = "3. Paste the report into the form's Report box and submit it.",
    ja = "3. フォームの「Report」欄に貼り付けて送信します。",
  },
  ["fix.copy.step4"] = {
    en = "4. Sent? Clear the reports you sent:",
    ja = "4. 送信したら、送った報告を消去します：",
  },
  ["fix.copy.empty"] = {
    en = "Nothing to send yet. In Translations, click a line, choose what is wrong and click Save.",
    ja = "まだ送る報告がありません。「翻訳」で行をクリックし、どこがおかしいかを選んで「保存」を押してください。",
  },
  ["fix.clear.confirm"] = { en = "Click again to clear %s reports", ja = "もう一度クリックで%s件を消去" },
  ["fix.cleared"] = { en = "Cleared %s reports", ja = "%s件を消去しました" },
  ["type.quest"] = { en = "Quest", ja = "クエスト" },
  ["type.gossip"] = { en = "NPC talk", ja = "NPCの会話" },
  ["type.item"] = { en = "Item", ja = "アイテム" },
  ["type.spell"] = { en = "Spell", ja = "呪文" },
  ["type.book"] = { en = "Book", ja = "本" },
  ["type.ui"] = { en = "Window text", ja = "画面の文字" },
  ["type.objective"] = { en = "Objective", ja = "目標" },
  ["type.area"] = { en = "Area objective", ja = "地域の目標" },
  ["minimap.tip"] = {
    en = "Left-click: report a line · Right-click: menu",
    ja = "左クリック：翻訳を報告 ・ 右クリック：メニュー",
  },
  ["minimap.enabled"] = { en = "Translation on", ja = "翻訳オン" },
  ["minimap.hide"] = { en = "Hide this button", ja = "このボタンを隠す" },
}

-- Slash reference on the About page (English: it is the literal grammar, like the chat output).
-- Every top-level verb of UI/Slash and every debug sub-verb (options_spec checks the list).
Text.SLASH = {
  "/wfj  (status)  ·  /wfj on | off | toggle  ·  /wfj version",
  "/wfj modifier <key>  (alt, lalt, button4, q …)",
  "/wfj togglekey [<key> | none]  (f5, ctrl-j …)",
  "/wfj area quests off  ·  /wfj marker missing on",
  "/wfj readings [on | off]  ·  /wfj glosses [on | off]",
  "/wfj config [collector | about]  ·  /wfj fix  (report a line)",
  "/wfj bug  (report a bug or an idea)",
  "/wfj collector [on | off | status | path | clear | send [all]]",
  "/wfj log [<n>]  (the problem log)  ·  /wfj taint  (action-bar taint scan)",
  "/wfj debug [hash | quest <id> | item <id> | spell <id>]",
  "/wfj debug [gossip | book | objective | fonts | ui [scan]]",
  "/wfj debug tooltip [on | off]  (record spell / item tooltip passes)",
}

-- the translation-report issue form the fix window's report is pasted into
Text.FIX_URL = "https://github.com/zyaga/wow-forever-japanese/issues/new?template=translation-report.yml"

-- → en, ja; a missing key raises (a typo must fail the spec, not ship a blank).
function Text.get(key, ...)
  local t = Text.T[key]
  assert(t, "OptionsText: no copy for " .. tostring(key))
  if select("#", ...) == 0 then return t.en, t.ja end
  return t.en:format(...), t.ja:format(...)
end
