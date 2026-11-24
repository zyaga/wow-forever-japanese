-- Data/Chat/ChatSlang.lua: TRIAL. Chat words the game's own text never uses, written by hand for the trial.
-- slangJa: Japanese chat word -> "reading=meaning". slangEn: English chat word (lower case) -> Japanese.
-- phrases: the phrase book, one fixed English and one fixed Japanese line each.
local _, WFJ = ...
local ja, en, phrases = WFJ.ChatData.slangJa, WFJ.ChatData.slangEn, WFJ.ChatData.phrases

ja["よろ"] = "よろ=short for よろしく: nice to meet you / thanks in advance"
ja["よろしく"] = "よろしく=nice to meet you / please treat me well"
ja["よろしくお願いします"] = "よろしくおねがいします=nice to meet you / thanks in advance (polite)"
ja["おつ"] = "おつ=short for お疲れ様: good work / thanks for the run"
ja["おつかれ"] = "おつかれ=good work / thanks for the run"
ja["お疲れ"] = "おつかれ=good work / thanks for the run"
ja["お疲れ様"] = "おつかれさま=good work / thanks for the run"
ja["お疲れ様でした"] = "おつかれさまでした=good work / thanks for the run (polite, said at the end)"
ja["おつかれさまでした"] = "おつかれさまでした=good work / thanks for the run (polite, said at the end)"
ja["あり"] = "あり=short for ありがとう: thanks"
ja["ありです"] = "ありです=thanks (casual polite)"
ja["あざす"] = "あざす=thanks (very casual)"
ja["おめ"] = "おめ=short for おめでとう: congrats"
ja["おめでとう"] = "おめでとう=congratulations"
ja["おか"] = "おか=short for おかえり: welcome back"
ja["おかえり"] = "おかえり=welcome back"
ja["ただいま"] = "ただいま=I'm back"
ja["こん"] = "こん=short for こんにちは / こんばんは: hi"
ja["こんちゃ"] = "こんちゃ=hi (casual)"
ja["こんばんは"] = "こんばんは=good evening"
ja["こんにちは"] = "こんにちは=hello"
ja["おは"] = "おは=short for おはよう: morning"
ja["おやすみ"] = "おやすみ=good night"
ja["おち"] = "おち=logging off"
ja["落ちます"] = "おちます=I'm logging off"
ja["落ち"] = "おち=logging off"
ja["りょ"] = "りょ=short for 了解: got it"
ja["了解"] = "りょうかい=understood / got it"
ja["りょうかい"] = "りょうかい=understood / got it"
ja["おけ"] = "おけ=OK"
ja["草"] = "くさ=lol (from w looking like grass)"
ja["乙"] = "おつ=short for お疲れ様: good work"
ja["離席"] = "りせき=away from keyboard"
ja["ごめん"] = "ごめん=sorry"
ja["すみません"] = "すみません=excuse me / sorry"
ja["どんまい"] = "どんまい=don't worry about it"
ja["ドンマイ"] = "ドンマイ=don't worry about it"
ja["ないす"] = "ないす=nice"
ja["ナイス"] = "ナイス=nice"
ja["募集"] = "ぼしゅう=recruiting / looking for members"
ja["募集中"] = "ぼしゅうちゅう=now recruiting"
ja["参加"] = "さんか=joining / taking part"
ja["初見"] = "しょけん=first time (seeing this dungeon or boss)"
ja["野良"] = "のら=a pickup group / a player not in your guild"
ja["周回"] = "しゅうかい=running it repeatedly / farming"
ja["狩り"] = "かり=hunting / grinding mobs"
ja["死に戻り"] = "しにもどり=dying on purpose to get back fast"
ja["全滅"] = "ぜんめつ=a wipe"
ja["釣る"] = "つる=to pull (a mob)"
ja["釣り"] = "つり=pulling / fishing"
ja["盾"] = "たて=tank"
ja["火力"] = "かりょく=damage dealer / DPS"
ja["回復"] = "かいふく=healing / healer"
ja["ヒラ"] = "ヒラ=healer"
ja["タゲ"] = "タゲ=target / aggro"
ja["ヘイト"] = "ヘイト=aggro / threat"
ja["バフ"] = "バフ=buff"
ja["デバフ"] = "デバフ=debuff"
ja["蘇生"] = "そせい=resurrect"
ja["売ります"] = "うります=selling (WTS)"
ja["買います"] = "かいます=buying (WTB)"
ja["誰か"] = "だれか=someone / anyone"
ja["いますか"] = "いますか=is (anyone) there?"

en["lfg"] = "パーティを探しています（Looking For Group）"
en["lfm"] = "メンバー募集中（Looking For More）"
en["lf"] = "〜を探しています（Looking For）"
en["lf1m"] = "あと1人募集（Looking For 1 More）"
en["lf2m"] = "あと2人募集（Looking For 2 More）"
en["lf3m"] = "あと3人募集（Looking For 3 More）"
en["wts"] = "売ります（Want To Sell）"
en["wtb"] = "買います（Want To Buy）"
en["wtt"] = "交換したい（Want To Trade）"
en["oom"] = "マナ切れ（Out Of Mana）"
en["afk"] = "離席中（Away From Keyboard）"
en["brb"] = "すぐ戻ります（Be Right Back）"
en["bbl"] = "あとで戻ります（Be Back Later）"
en["omw"] = "向かっています（On My Way）"
en["inc"] = "敵が来る（Incoming）"
en["inv"] = "パーティに招待して（Invite）"
en["ty"] = "ありがとう（Thank You）"
en["thx"] = "ありがとう（Thanks）"
en["tyvm"] = "本当にありがとう（Thank You Very Much）"
en["np"] = "どういたしまして／問題ない（No Problem）"
en["yw"] = "どういたしまして（You're Welcome）"
en["gg"] = "お疲れ様／いい試合（Good Game）"
en["gj"] = "よくやった（Good Job）"
en["gl"] = "がんばって（Good Luck）"
en["gz"] = "おめでとう（Congratulations）"
en["grats"] = "おめでとう（Congratulations）"
en["wb"] = "おかえり（Welcome Back）"
en["sry"] = "ごめん（Sorry）"
en["plz"] = "お願い（Please）"
en["pls"] = "お願い（Please）"
en["rdy"] = "準備OK（Ready）"
en["r"] = "準備OK（Ready）"
en["rez"] = "蘇生して（Resurrect）"
en["res"] = "蘇生して（Resurrect）"
en["buff"] = "バフ（強化魔法）"
en["nerf"] = "弱体化"
en["aggro"] = "ヘイト／敵の注意"
en["pull"] = "敵を釣る"
en["wipe"] = "全滅"
en["tank"] = "タンク（盾役）"
en["heals"] = "ヒーラー（回復役）"
en["healer"] = "ヒーラー（回復役）"
en["dps"] = "アタッカー（火力役）"
en["cc"] = "行動阻害（Crowd Control）"
en["aoe"] = "範囲攻撃（Area Of Effect）"
en["dot"] = "継続ダメージ（Damage Over Time）"
en["hot"] = "継続回復（Heal Over Time）"
en["cd"] = "クールダウン（再使用待ち）"
en["mob"] = "敵モンスター"
en["mobs"] = "敵モンスター"
en["add"] = "追加で来た敵"
en["adds"] = "追加で来た敵"
en["bis"] = "その部位で最強の装備（Best In Slot）"
en["boe"] = "装備すると譲渡不可になるアイテム（Bind On Equip）"
en["bop"] = "拾うと譲渡不可になるアイテム（Bind On Pickup）"
en["ah"] = "オークションハウス"
en["fp"] = "フライトポイント（飛行場）"
en["hs"] = "ハースストーン（帰還石）"
en["gy"] = "墓地（Graveyard）"
en["xp"] = "経験値"
en["exp"] = "経験値"
en["lvl"] = "レベル"
en["ding"] = "レベルアップした！"
en["mats"] = "素材（Materials）"
en["pst"] = "ささやきで連絡して（Please Send Tell）"
en["dm"] = "ささやき／デッドマインズ"
en["irl"] = "現実世界で（In Real Life）"
en["idk"] = "わからない（I Don't Know）"
en["imo"] = "私の意見では（In My Opinion）"
en["lol"] = "笑（Laughing Out Loud）"
en["rofl"] = "爆笑"
en["nvm"] = "気にしないで（Never Mind）"
en["ofc"] = "もちろん（Of Course）"
en["tbh"] = "正直に言うと（To Be Honest）"
en["atm"] = "今のところ（At The Moment）"
en["ninja"] = "横取りする人"
en["noob"] = "初心者（軽い悪口）"
en["twink"] = "低レベル帯で装備を極めたキャラ"
en["alt"] = "サブキャラ"
en["main"] = "メインキャラ"
en["summon"] = "召喚して"
en["summ"] = "召喚して"
en["port"] = "ポータルを出して"
en["mage"] = "メイジ"

local function p(cat, jaText, enText) phrases[#phrases + 1] = { cat = cat, ja = jaText, en = enText } end
p("挨拶 / Greetings", "こんにちは！", "Hello!")
p("挨拶 / Greetings", "よろしくお願いします！", "Nice to meet you, glad to be here!")
p("挨拶 / Greetings", "ありがとうございます！", "Thank you very much!")
p("挨拶 / Greetings", "お疲れ様でした！", "Good work everyone, thanks for the run!")
p("挨拶 / Greetings", "ごめんなさい。", "I'm sorry.")
p("挨拶 / Greetings", "おめでとう！", "Congratulations!")
p("挨拶 / Greetings", "おやすみなさい。落ちます。", "Good night, I'm logging off.")
p("挨拶 / Greetings", "英語はあまり話せません。", "I don't speak much English.")
p("挨拶 / Greetings", "日本語はあまり話せません。", "I don't speak much Japanese.")
p("パーティ / Group", "パーティに入れてください。", "Please invite me to the group.")
p("パーティ / Group", "一緒にクエストをしませんか？", "Would you like to do this quest together?")
p("パーティ / Group", "タンクを募集しています。", "Looking for a tank.")
p("パーティ / Group", "ヒーラーを募集しています。", "Looking for a healer.")
p("パーティ / Group", "アタッカーを募集しています。", "Looking for damage dealers.")
p("パーティ / Group", "準備できました。", "I'm ready.")
p("パーティ / Group", "少し待ってください。", "Please wait a moment.")
p("パーティ / Group", "すぐ戻ります。", "I'll be right back.")
p("パーティ / Group", "戻りました。", "I'm back.")
p("パーティ / Group", "このダンジョンは初めてです。", "This is my first time in this dungeon.")
p("パーティ / Group", "抜けます。ありがとうございました。", "I have to leave now. Thank you!")
p("戦闘 / Combat", "マナがありません。", "I'm out of mana.")
p("戦闘 / Combat", "回復をお願いします。", "Please heal me.")
p("戦闘 / Combat", "蘇生をお願いします。", "Please resurrect me.")
p("戦闘 / Combat", "ついてきてください。", "Please follow me.")
p("戦闘 / Combat", "敵が来ます！", "Enemies incoming!")
p("戦闘 / Combat", "逃げて！", "Run away!")
p("戦闘 / Combat", "助けてください！", "Please help me!")
p("取引 / Trade", "これを売りたいです。", "I want to sell this.")
p("取引 / Trade", "これを買いたいです。", "I want to buy this.")
p("取引 / Trade", "いくらですか？", "How much is it?")
p("取引 / Trade", "それはニードしてもいいですか？", "May I roll need on that?")
p("ギルド / Guild", "ギルドに入りたいです。", "I would like to join the guild.")
p("ギルド / Guild", "誰か手伝ってくれませんか？", "Could someone help me?")
p("ギルド / Guild", "今、手伝えますよ。", "I can help now.")
p("ギルド / Guild", "どこにいますか？", "Where are you?")
