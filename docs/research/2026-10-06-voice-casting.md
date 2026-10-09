# Research: voice casting from AivisHub

> Every voice model on AivisHub, the model site of the AivisSpeech Engine, read on 2026-10-06: 75 models. 40 can be used (37 under ACML 1.0, 3 under CC0); 35 are out (7 non-commercial, 28 custom licences). Young voices are plentiful; adult and older female voices are almost absent, and no usable voice is labelled a child. Nothing was downloaded; the choice of voices is made by ear later.

- **Date:** 2026-10-06
- **Question:** Which AivisHub voices can the voice-over packs use, and which speaker types (gender and age) can they cover?
- **Sources:** the AivisHub public API (`api.aivis-project.com/v1/aivm-models/search`, 8 pages of 10, sorted by its default order, and single-model records `.../v1/aivm-models/<uuid>`), its OpenAPI description (`api.aivis-project.com/v1/openapi.json`), model pages on `hub.aivis-project.com`, the AivisSpeech Engine README (github.com/Aivis-Project/AivisSpeech-Engine) and the licence text `ACML-1.0.md` (github.com/Aivis-Project/ACML). Anything not settled by those is marked **[unverified]**.

## How the list was read
- The search endpoint reports a total of 75 public models. Pages of 10 (page 1 to 8) returned 75 distinct UUIDs, which matches the total and the earlier count in [2026-10-04-japanese-voice-over.md](2026-10-04-japanese-voice-over.md). The endpoint takes `page`, `limit` and `sort`; the allowed sorts are `download`, `like` and `recent` (OpenAPI). An unknown sort value returns `422`.
- **Age and gender** come from each model's `voice_timbre` field. The OpenAPI lists 14 values; the hub shows them as Japanese labels in the same order. The order match was confirmed on two pages (`YoungFemale` shows 「幼い女性の声」, `MiddleAgedMale` shows 「中年男性の声」); the rest of the mapping follows the order **[unverified per label]**.

| `voice_timbre` | Hub label | Band used here |
|---|---|---|
| YoungMale / YoungFemale | 幼い男性の声 / 幼い女性の声 | child |
| YouthfulMale / YouthfulFemale | 若い男性の声 / 若い女性の声 | young |
| AdultMale / AdultFemale | 壮年男性の声 / 壮年女性の声 | adult |
| MiddleAgedMale / MiddleAgedFemale | 中年男性の声 / 中年女性の声 | middle-aged |
| ElderlyMale / ElderlyFemale | 熟年男性の声 / 熟年女性の声 | elderly |
| Neutral, Baby, Mechanical, Other | 中性的な声, 赤ちゃんの声, 機械音/環境音, その他 | other |

- **Size** is the AIVMX file, the only format the engine loads (README: 「敢えて AIVMX ファイルのみをサポートする設計」). The API lists it as the `ONNX` model file; the hub page shows the same figure (阿井田 茂: 251,137,086 bytes in the API, "251.14MB" on the page). Sizes below are in decimal MB.
- **Licence** is the API's `license_type`. ACML 1.0 (read from `ACML-1.0.md`): any personal, corporate, non-commercial or commercial use that avoids the listed prohibitions (impersonation, harming the speaker, harassment, false information, political or religious advocacy, crime); the model may be passed on with the licence text attached; 「クレジット表記は任意です」; the licence is read in Japanese only. ACML-NC 1.0 is limited to non-commercial use. Custom licence terms below were read from each model's `license_text` through a summarising fetch, not line by line, so their wording is **[unverified]**; the licence class itself is not.
- **Fits** is the model's own description or tags, quoted or briefly glossed. Where only an English gloss is given, the Japanese line was not captured verbatim.
- **Page** for every model is `https://hub.aivis-project.com/aivm-models/<UUID>`. Every row was read on 2026-10-06.

## Usable: ACML 1.0 or CC0 (40)

| Name | UUID | Author | Gender, age | Styles | Size MB | Licence | Fits |
|---|---|---|---|---|---|---|---|
| にせ | 6d11c6c2-f4a4-4435-887e-23dd60f8b8dd | 魔法プログラム (MAHOPROGRAM) | male, young | ノーマル | 250.24 | ACML 1.0 | 「研究開発用の試作音声合成モデル」 (a research prototype) |
| 澤原 玄二郎 | 2e1fdde8-d089-42d7-b64f-cf89952b1bdc | 古山キリヲ (khirio) | male, young | ノーマル, close, close-shout, far, far-shout | 251.27 | ACML 1.0 | 「せっかちでヤンチャな猫ヤロー」 (impatient, rowdy) |
| yukyu | 1f04a608-916c-4d9e-bf6e-b9da5c176f85 | yukyu | male, young | デフォルト | 250.71 | ACML 1.0 | 「男声の音声モデルです」 (no fit stated) |
| Lux | 3dabea2b-cc10-41da-955b-4618ce84e716 | 神瀬来未 (Lami) | male, young | ノーマル | 257.45 | ACML 1.0 | 「Style-Bert-VITS2 JP-Extra対応TTSモデル」 (no fit stated) |
| 宗周定昌 | 00f29eb2-e12b-4f64-a5e8-4188be62de33 | 名無しさん (uUMwsnIgbonmIXc) | male, young | ノーマル | 250.59 | ACML 1.0 | somewhat anime-like voice; tags だる気, やる気のない (listless) |
| 立神ケイ | b2bee8fc-3f65-4c99-9607-a1075a10066b | ニッケル (Nickel570) | male, young | ノーマル | 253.47 | ACML 1.0 | low-pitched, slightly husky |
| kokuren_voice | e40d5b99-8cde-4442-a45b-0ebec9167506 | kokuren | male, young | ノーマル, Disgust, Fear, Surprised, Happy, Sad | 249.61 | ACML 1.0 | the author's own voice |
| はきみて れく(瞭魅推 れく) | 70ad7e84-6a10-48d6-8f9a-8dac4bba3c0b | はきみて れく (hackimitelec) | male, young | ノーマル | 249.79 | ACML 1.0 | a VTuber character (「技術属性モンスター(偽)VTuber」) |
| 結亜ナル | b79c40e4-8a5e-4f20-802c-2c0eba2f0983 | ゆうしゃアシスタント (yuusyaasisutanto) | male, young | ノーマル | 250.66 | CC0 | a joke character (「オナラとケツを叩く音から産まれた」) |
| すきやき馬太郎 | f493ab6c-1ffa-4534-9bbd-2ba398f17cd5 | すきやき馬太郎 (sukiyaki_umataro88) | male, young | ノーマル | 250.04 | CC0 | 「落ち着いた話し方が特徴」 (calm speech) |
| MarkN | f79e73ab-3320-473b-8e3f-713c30c39ed1 | まーくん。(MarkN) | male, young | ノーマル | 250.26 | ACML 1.0 | voice of a creator on Resonite (a real person); optional credit 「AivisSpeech:MarkN」 |
| kokuren_3rd | 3bef4d35-124e-4ddd-93d3-75f292732195 | kokuren | male, young | ノーマル | 250.44 | ACML 1.0 | no description |
| fumifumi | 71e72188-2726-4739-9aa9-39567396fb2a | サガワフミヤ (sagawafumiya) | male, adult | ノーマル | 270.17 | ACML 1.0 | 「落ち着いた青年をイメージして作成したボイスモデル」 (calm young man, though labelled adult) |
| 猩々博士（雑談ボイス） | 70a875a9-feae-41e6-a586-8cf9e47c6c0b | 猩々博士 (5vsNicPQdJX2e_C) | male, adult | ノーマル | 260.74 | ACML 1.0 | made from a VTuber's stream audio, chat voice (a real person) |
| 観測症 | ed47c952-c253-405e-adba-1172399816a1 | 観測症 (hdae) | male, adult | ノーマル | 250.86 | ACML 1.0 | 「滑舌がそんなに良くないので、頑張って出した声」 (author says his articulation is not crisp) |
| 阿井田 茂 | 47e53151-a378-46f3-abee-ce13aa07feb1 | 古山キリヲ (khirio) | male, middle-aged | ノーマル, Calm, Far, Heavy, Mid, Shout, Surprise | 251.14 | ACML 1.0 | 「バリトンボイスの朗らかおじさん」 (cheerful baritone uncle) |
| hinakoyuhara | e5bd2b5e-90a8-4fb3-a69f-2fbd2d3a8a43 | 柚原比奈子 (HinakoYuhara) | male, middle-aged | ノーマル, 普通, 落ち着き, 怒り | 258.07 | ACML 1.0 | 「試しに作った物です」 (a trial) |
| ろてじん（匿名インタビュー風） | 80fe2db4-5891-4550-a3f3-dff9a91c0946 | ろてじん (Rotejin) | male, middle-aged | ノーマル | 250.77 | ACML 1.0 | 「匿名インタビュー風の演技でセリフ収録したボイスモデル」 (anonymous interview delivery) |
| ろてじん（長老ボイス） | 696c98a2-c0b7-4fe7-8cf2-c7e9b8a9bd82 | ろてじん (Rotejin) | male, elderly | ノーマル | 252.93 | ACML 1.0 | 「老人の声を意識した演技でセリフ収録したボイスモデル」 (acted old man) |
| TANAKA | 470a41e2-863f-4bf2-8a20-bf7cde0d8f7b | 田中 (TANAKA) | male, elderly | ノーマル, Anger, Happy, Silly, Surprise | 253.84 | ACML 1.0 | 「YouTubeの自動字幕読上げナレーション用に自作」 (narration); tag 「はい、どーもー。おとんです」 (a dad) |
| morioki | baaae3c0-7b22-4605-8ba5-80c959b41a48 | yuki | female, adult | ノーマル | 251.13 | ACML 1.0 | 「一般的な女性の声として使用できるボイスモデル」 (a general female voice; a real person) |
| まお | a59cb814-0083-4369-8542-f51a29e72af7 | オズチャット -Oz Chat- (ozchat) | female, young | ノーマル, ふつー, あまあま, おちつき, からかい, せつなめ | 258.04 | ACML 1.0 | 「いたずらっ子な小悪魔ボイス」 (mischievous, impish) |
| コハク | 22e8ed77-94fe-4ef2-871f-a86f94e9a579 | オズチャット -Oz Chat- (ozchat) | female, young | ノーマル, あまあま, せつなめ, ねむたい | 255.33 | ACML 1.0 | 「子猫のような甘い声」 (sweet, kitten-like) |
| まい | e9339137-2ae3-4d41-9394-fb757a7e61e6 | 魔法プログラム (MAHOPROGRAM) | female, young | ノーマル | 250.84 | ACML 1.0 | research prototype; tag 妖艶な女性 (alluring woman) |
| 花音 | a670e6b8-0852-45b2-8704-1bc9862f2fe6 | 魔法プログラム (MAHOPROGRAM) | female, young | ノーマル | 252.67 | ACML 1.0 | research prototype |
| 凛音エル | f5017410-fbb5-49e1-97cb-e785f42e15f5 | kokuren | female, young | ノーマル, Angry, Fear, Happy, Sad | 252.77 | ACML 1.0 | an AI character of 電脳天使工業 |
| るな | 4f281e78-eba6-495a-8e50-5c322d02b5b1 | 魔法プログラム (MAHOPROGRAM) | female, young | ノーマル | 254.67 | ACML 1.0 | research prototype |
| 中2 | 9107b8b6-1ed1-43f5-bebe-0de4df4d229d | 魔法プログラム (MAHOPROGRAM) | female, young | ノーマル | 251.40 | ACML 1.0 | research prototype |
| 桜音 | 3328da9a-8124-4619-a853-f7fc2f37889f | 魔法プログラム (MAHOPROGRAM) | female, young | ノーマル | 257.20 | ACML 1.0 | research prototype |
| ほのか | 59f96896-64d2-4378-830a-4d5feb3d81aa | Dopoiro | female, young | ノーマル, kanasimi_kanasimi, uresii_uresii, hutuu_hutuu, odoroki_odoroki | 251.22 | ACML 1.0 | 「現実20代女子」 voice-changer model (a woman in her 20s) |
| かりん(現実20代女子AIボイチェン@リアボVC公式モデル) | 18972473-ca36-4e06-a33a-5cc14adba0c4 | Dopoiro | female, young | ノーマル, kanasimi_kanasimi, uresii_uresii, hutuu_hutuu, odoroki_odoroki | 251.16 | ACML 1.0 | the same (20s woman) |
| わかな(現実20代女子AIボイチェン@リアボVC公式モデル) | f83c385c-829b-40c4-8c11-639027e61636 | Dopoiro | female, young | ノーマル, 悲しい, 嬉しい, 普通, 驚き | 251.17 | ACML 1.0 | the same (20s woman) |
| れな(現実20代女子AIボイチェン@リアボVC公式モデル) | b1b8072f-809f-4c6d-9ba1-2ca94d9c3663 | Dopoiro | female, young | ノーマル, kanasimi_kanasimi, uresii_uresii, hutuu_hutuu, odoroki_odoroki | 251.26 | ACML 1.0 | the same (20s woman) |
| もえ(現実20代女子AIボイチェン@リアボVC公式モデル) | 9a7feb22-b6f3-4f79-92d9-26849e063fa1 | Dopoiro | female, young | ノーマル, kanasimi_kanasimi, uresii_uresii, hutuu_hutuu, odoroki_odoroki | 251.22 | ACML 1.0 | the same (20s woman) |
| さつき(現実20代女子AIボイチェン@リアボVC公式モデル) | 21d8d535-f206-462d-a3bb-05f8252dede7 | Dopoiro | female, young | ノーマル, kanasimi_kanasimi, uresii_uresii, hutuu_hutuu, odoroki_odoroki | 251.28 | ACML 1.0 | the same (20s woman) |
| すみれ | 2ff1c526-27d4-4eeb-b069-4207ae5fe259 | Dopoiro | female, young | ノーマル, kanasimi_kanasimi, uresii_uresii, hutuu_hutuu, odoroki_odoroki | 251.23 | ACML 1.0 | the same (20s woman) |
| みちのくあいり | 1b2830f4-8cf1-4184-a0d9-3a1bace3a844 | こずかた学園プロジェクト (kozukata_gakuen) | female, young | 標準, 悲しみ, 怒り, 嫌悪, 驚き, 恐怖, 喜び | 256.76 | ACML 1.0 | 「落ち着きのあるかわいらしい女性ボイス」 (calm, cute) |
| zonoko | 7fc08a41-b64d-456d-8b22-8e1284674775 | ずごっく (zgock999) | female, young | ノーマル, A, B, C, D | 260.29 | CC0 | made from OpenGameArt CC0 English voices with the Zonos cloning tool |
| らせつん | 9f36ec0d-8dac-42dc-aff4-149c5f99faad | こずかた学園プロジェクト (kozukata_gakuen) | neutral (other) | 標準, 喜び, 嫌悪, 怒り, 恐怖, 悲しみ, 標準２, 驚き | 257.67 | ACML 1.0 | 「親しみやすさのある中性ボイスです」 (friendly, gender-neutral) |
| 六弦エレキ | ed0f793d-786c-4fde-8561-e8bbac7bfe1d | 榊蓮 (len_sakaki) | mechanical (other) | のーまる, はきはき, るんるん, しんけん | 250.51 | ACML 1.0 | 「六弦エレキのAivisSpeech用合成音声モデルです」 (no fit stated) |

The two voices used in the samples so far, 阿井田 茂 and morioki, are both ACML 1.0 and sit in the table above like the rest.

## Out (35)

| Name | UUID | Author | Gender, age | Styles | Size MB | Licence | Reason it is out | Fits |
|---|---|---|---|---|---|---|---|---|
| Shinjou Tomoharu | 098d4e66-2faf-4a00-889c-a1d2f05bde78 | 名無しさん (n2PkZNR860ATafv) | male, middle-aged | ノーマル | 252.33 | ACML-NC 1.0 | non-commercial only | 「落ち着いた中年男性のモデル」 (calm middle-aged man) |
| 天深シノ | 0f6821f4-9f86-4da1-a41a-fbe6fff9ca88 | 天深シノ・亜空マオ (shinomao) | female, young | ノーマル, じょうきげん, ふきげん, ささやき | 258.28 | ACML-NC 1.0 | non-commercial only | 「人の世界で生活をするために人の格好をしている天使。優しい声で話します。」 (gentle) |
| 亜空マオ | 9e9f84bd-05cd-4476-b47e-ad34264b2a03 | 天深シノ・亜空マオ (shinomao) | male, young | ノーマル, ふきげん, じょうきげん | 256.38 | ACML-NC 1.0 | non-commercial only | a fallen angel in human form, gentle voice |
| 様子ヶ丘シイナ | d6bfe943-6903-491f-8d01-454ad8f88c14 | ニッケル (Nickel570) | female, young | !選択しないでください, のーまる, キュートアグレッション | 256.19 | ACML-NC 1.0 | non-commercial only | 「およそ水素の声から生まれた合成音声です」 |
| オレンジ | 6e60c40a-6d0f-4d86-9d97-61c11402058a | オレンジ (orange) | male, young | ノーマル | 251.16 | ACML-NC 1.0 | non-commercial only | a person active on Resonite and VRChat |
| G59 | 83f2930e-4697-4265-822c-04d7337b3047 | オレンジ (orange) | male, young | ノーマル | 252.18 | ACML-NC 1.0 | non-commercial only | 「VRの住人「G59」のボイスモデル」 |
| akiRAM | 1112959e-bb11-4a61-8c07-ebea8ea568cc | オレンジ (orange) | male, young | ノーマル | 250.52 | ACML-NC 1.0 | non-commercial only | 「VRの住人「akiRAM」のボイスモデルです。」 |
| M1 | d7255c2c-ddd0-425a-808c-662cd94c7f41 | 名無しさん (gpt) | male, young | ノーマル, 怒り, 嫌悪, 恐れ, 幸せ, 悲しみ, 驚き | 258.61 | Custom | built on the JVNV corpus, CC BY-SA 4.0; share-alike may reach the audio | Style-Bert-VITS2 default male model 1 |
| M2 | d1a7446f-230d-4077-afdf-923eddabe53c | 名無しさん (gpt) | male, young | ノーマル, 怒り, 嫌悪, 恐れ, 幸せ, 悲しみ, 驚き | 258.05 | Custom | the same (CC BY-SA 4.0) | Style-Bert-VITS2 default male model 2 |
| F1 | 6acf95e8-11a9-414e-aa9c-6dbebf9113ca | 名無しさん (gpt) | female, young | ノーマル, 怒り, 嫌悪, 恐れ, 幸せ, 悲しみ, 驚き | 258.33 | Custom | the same (CC BY-SA 4.0) | Style-Bert-VITS2 default female model 1 |
| F2 | 25b39db7-5757-47ef-9fe4-2b7aff328a18 | 名無しさん (gpt) | female, young | ノーマル, 怒り, 嫌悪, 恐れ, 幸せ, 悲しみ, 驚き | 258.58 | Custom | the same (CC BY-SA 4.0) | Style-Bert-VITS2 default female model 2 |
| 銀芽(ぎんが) | 052bb693-112b-45be-b498-8e05aa9d6e5e | AI声優シリーズ (aiseiyu) | male, adult | ニュートラル, 通常, 呆れ, 感情的 | 252.14 | Custom | credit required; no modification or redistribution; no adult content | built from ITA corpus audio |
| 金苗(かなえ) | 1a322ad9-6b7e-4a6d-8d0b-c4cd264538dc | AI声優シリーズ (aiseiyu) | female, young | ニュートラル, ノーマル, うきうき, ほのぼの, ぷんぷん, 愉悦 | 252.85 | Custom | the same as 銀芽 | built from ITA corpus audio |
| リダ / Lida | 446d2053-14ca-4b68-897c-380faf555b59 | リダ (Lida) | female, young | ノーマル, 落ち着き, クール, デフォルト, 元気, 落ち着き２, 元気２, 悲しみ, キュート, キュート2 | 255.86 | Custom | commercial use with a fixed credit (name and URL); no redistribution; no training use | VTuber Lida's official model |
| 蒼月ハヤテ | eefe1fbd-d15a-49ae-bc83-fc4aaad680e1 | サルドラ (sald_ra) | male, young | ノーマル | 250.13 | Custom | commercial use with credit; no political, religious or misinformation use; needs its own read | a character voice |
| Flow | 76a774e4-cc4d-4d8c-879e-8d2be3d30dad | フロウ (Flow) | male, young | ノーマル, 01_JOY, 02_ANGRY, 03_SAD, 04_FUN, 05_SURPRISE, 06_CONTEMPT, 07_FEAR, 08_CONFUSE, 09_NORMAL, 10_EXPLAIN, 11_ANNOUNCE, 12_WHISPER_ANGRY, 12_WHISPER_CONTEMPT, 12_WHISPER_FEAR, 12_WHISPER_FUN, 12_WHISPER_JOY, 12_WHISPER_SAD, 13_LAZY_ANGRY, 13_LAZY_NORMAL, 13_LAZY_SAD | 251.47 | Custom | commercial use allowed; no redistribution, modification or derivatives | 「フロウの声をStyle-Bert-VITS2で学習させた」 |
| kuroike ai | ebd755af-392e-44ac-a523-53a1b1fa1377 | KUROIKEAI (KOKOROHQ_YUU) | male, young | Neutral, セクシー, あまあま, ツンツン, ノーマル | 250.86 | Custom | non-commercial; no redistribution of the original | a poem as description, no fit stated |
| Amene Lila | ddbea2e2-e51f-48da-ace1-197b2c6a77bb | tyvy (yQIPIAYSW3R6v3y) | female, child (hub label 幼い女性の声) | ノーマル | 249.54 | Custom | 「商用・非商用利用が可能です」 with visible credit; no adult content or misrepresenting the speaker; custom, so not in the usable class | 「ライラは親切で遊び心のある若い女性」 (a kind, playful young woman, despite the child label) |
| RakumaYue | 657f4f16-3cf5-4048-9a98-00987038ebf0 | 楽心の探し場所 (RakushinNoSagashibasyo) | male, young | Standard | 251.10 | Custom | no model redistribution, credit required; commercial terms unclear **[unverified]** | the character 楽間勇笑 |
| 水巻咲_T2モデル | 55696911-05cb-4cd2-bdb9-dbc8bfe6e5c7 | TαkoeProject (TakoeProject) | female, young | ノーマル, Negative, Positive | 250.59 | Custom | TakoeProject terms (below) | the character 水巻咲 |
| 七日週_T2モデル | baa6d55a-d751-49b8-bafb-b3a6555a100c | TαkoeProject (TakoeProject) | female, young | ノーマル, Negative, Positive | 251.30 | Custom | TakoeProject terms | the character 七日週 |
| 大日椛_T2モデル | fb04b883-13cb-40ef-b0ea-fad060a408e8 | TαkoeProject (TakoeProject) | female, young | ノーマル, Negative, Positive | 250.70 | Custom | TakoeProject terms | the character 大日椛 |
| 木角空_T2モデル | d0471c7d-3adc-4c99-b7b7-0e91c4d9d96f | TαkoeProject (TakoeProject) | female, young | ノーマル, Negative, Positive | 250.39 | Custom | TakoeProject terms | the character 木角空 |
| 黄金笑_T2モデル | 734c12b6-eaf2-4dbd-8596-8663c72d2afa | TαkoeProject (TakoeProject) | female, young | ノーマル, Negative, Positive | 250.53 | Custom | TakoeProject terms | the character 黄金笑 |
| 矢月舞_T2モデル | f13c2ec8-1069-403f-a23e-503b3a270c57 | TαkoeProject (TakoeProject) | female, young | ノーマル, Negative, Positive | 249.86 | Custom | TakoeProject terms | the character 矢月舞 |
| 葉土此_T2モデル | d200a39c-7c0f-4e03-a947-b3f0cb8d3d6b | TαkoeProject (TakoeProject) | female, young | ノーマル, Negative, Positive | 250.64 | Custom | TakoeProject terms | the character 葉土此 |
| 火山夢_T2モデル | e4ee047d-3af4-4936-90eb-29a3c9104709 | TαkoeProject (TakoeProject) | female, young | ノーマル, Negative, Positive | 249.90 | Custom | TakoeProject terms | the character 火山夢 |
| 楽町音穏_T3モデル | 0e8ea44c-d904-467d-a0e6-81d52b1db098 | TαkoeProject (TakoeProject) | female, young | ノーマル | 250.62 | Custom | TakoeProject terms | the character 楽町音穏 |
| 地良谷詩_T3モデル | 9badaf1f-f664-47de-9754-51ad6936d693 | TαkoeProject (TakoeProject) | female, young | ノーマル | 250.74 | Custom | TakoeProject terms | the character 地良谷詩 |
| 鰻川叶恵_T3モデル | 33090ea6-7696-491b-afb9-86fdbc4c2e51 | TαkoeProject (TakoeProject) | female, young | ノーマル | 250.76 | Custom | TakoeProject terms | the character 鰻川叶恵 |
| 雪降白華_T3モデル | 37e49039-522f-4608-b8d6-fc6716ada80e | TαkoeProject (TakoeProject) | female, young | ノーマル | 250.62 | Custom | TakoeProject terms | the character 雪降白華 |
| 蝶舞和香_T3モデル | 7ac45cff-1e2f-4545-91bb-e7b2cc67649b | TαkoeProject (TakoeProject) | female, young | ノーマル, 不機嫌, 落ち着き | 252.71 | Custom | TakoeProject terms | the character 蝶舞和香 |
| 騾馬原杏_T3モデル | 9f0d1fba-3acd-439a-8446-ea94e8ca6985 | TαkoeProject (TakoeProject) | female, young | ノーマル | 250.70 | Custom | TakoeProject terms | the character 騾馬原杏 |
| 梅𡵅弓哥_T3モデル | 1f677b65-741e-4ba4-b029-d5525deb82b8 | TαkoeProject (TakoeProject) | female, young | ノーマル | 250.62 | Custom | TakoeProject terms | the character 梅𡵅弓哥 |
| 夢咲舞空_T3モデル | 53c4bdca-992e-4289-8cf7-1338b11eb567 | TαkoeProject (TakoeProject) | female, young | ノーマル | 250.73 | Custom | TakoeProject terms | the character 夢咲舞空 |

TakoeProject terms (16 models, one shared custom text): commercial and non-commercial use allowed; a credit line is required (「著作権表示は、必ず明記してください」); the model may be passed on only when modified; no religious, gambling or inappropriate use, and nothing that harms the character's image. Several custom licences (TakoeProject, Amene Lila, 蒼月ハヤテ) allow commercial use with credit. They are out here only because the usable class is ACML 1.0 or CC0; any of them would need its full text read before it could move in.

## Casting coverage

Usable voices per gender and age band (the whole hub in brackets):

| | child | young | adult | middle-aged | elderly |
|---|---|---|---|---|---|
| male | 0 (0) | 12 (22) | 3 (4) | 3 (4) | 2 (2) |
| female | 0 (1) | 17 (39) | 1 (1) | 0 (0) | 0 (0) |
| other | らせつん (neutral), 六弦エレキ (mechanical) | | | | |

Thin bands:
- **Adult female:** one voice, morioki. The whole hub has no other.
- **Middle-aged and elderly female:** none on the hub at all.
- **Child:** none usable; the only child-labelled model (Amene Lila) is custom, and its own description calls her a young woman.
- **Elderly male:** two (ろてじん（長老ボイス）, TANAKA). Middle-aged and adult male have three each.
- Several male "young" voices are described as calm or low (すきやき馬太郎, 立神ケイ), and fumifumi is labelled adult but described as 「青年」, so the labels are only a first sort.

Candidates for covering a thin band by shifting pitch. This is a list to try by ear, not a choice. The engine accepts `pitchScale`, but its README warns that changing it may lower quality in AivisSpeech (unlike VOICEVOX); a pitch shift after generation is the other route. Neither was tried.

| Thin band | Candidates (lower or raise) | Why these |
|---|---|---|
| adult female | lower: みちのくあいり (calm), まお (おちつき style), すみれ / さつき / わかな / ほのか / かりん / れな / もえ (described as women in their 20s) | the calmest and oldest-sounding of the young female set, by their descriptions |
| middle-aged female | lower: morioki, then the adult-female candidates above | morioki is the only adult female |
| elderly female | lower further: morioki, みちのくあいり | the same; an old woman may need slower `speedScale` too |
| elderly male | lower: 阿井田 茂 (Heavy or Calm style), hinakoyuhara (落ち着き style), ろてじん（匿名インタビュー風） | middle-aged male voices; the last shares a speaker with ろてじん（長老ボイス） |
| child (boy) | raise: yukyu, にせ, Lux, 澤原 玄二郎 | young male voices with no stated low pitch |
| child (girl) | raise: コハク (「子猫のような甘い声」), 中2, らせつん (neutral) | the lightest descriptions; 中2 by its name only |

## Totals
**Usable: 40 models (37 ACML 1.0, 3 CC0), 10,130,853,160 bytes of AIVMX files, about 10.13 GB.** Out: 35 (7 ACML-NC 1.0, 28 custom). Total on the hub: 75.

## Gaps and unconfirmed
- Custom licence key terms come from a summarising read of each `license_text`, not a line-by-line reading. The licence class for every model is from the API field and is reliable; the custom wording is **[unverified]**.
- The timbre-to-label mapping was confirmed on two labels; the rest follow the label order **[unverified per label]**. Age is the uploader's own label, not a measurement.
- Where the Fits column has only an English gloss (宗周定昌, 立神ケイ, kokuren_voice, 亜空マオ, Lida, 蒼月ハヤテ and others), the Japanese description was not captured verbatim.
- One read with 30 results per page returned an extra model (UUID `c3264210-975f-4e3b-8357-54700f8886a8`); its single record answers `404`, so it is treated as a read error, not a model. The pages of 10 gave exactly 75.
- 阿井田 茂 is listed with seven styles in the API; the earlier research note said two. The API value is used here.
- fumifumi's AIVMX file (270.17 MB) is about 18 MB larger than its Safetensors file, unlike every other model (about 1.7 MB smaller). Read as given.
- No model was downloaded or played. Fitness for a role is the description's claim, not a listening check.

## Related
- [2026-10-04-japanese-voice-over.md](2026-10-04-japanese-voice-over.md): the voice-over spike, engine choice and the first licence count.
