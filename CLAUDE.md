# 八卦小鎮 GOSSIP TOWN — iOS 原生版（Swift，UIKit＋Core Graphics）

網頁版 `Gaming/GossipTown`（gossip.emptyoffice.app）的原生移植，沒有 WebView。傳話引擎是純 Swift（`Sources/GossipCore`，Linux 也能編），
畫面是 UIKit（地圖用 Core Graphics 每格重畫，跟網頁 render.js 一樣的座標），AI 對話走同一個 Cloudflare Worker（金鑰只在 Worker secret）。
Bundle ID `com.austin410203.gossiptown`。repo `austin410203/3D_GossipTown_iOS`（私人；跑 CI 時暫時公開，跑完改回私人：`python -I tools/gh.py visibility public|private`）。
commit 作者一律 Empty Office <hello@emptyoffice.app>。

## 結構
| 路徑 | 內容 |
|---|---|
| `Sources/GossipCore/Sim.swift` | sim.js 逐行移植（誰在哪、誰講給誰、變形、信不信、關係、事件、星星）。跟網頁**逐行相同**（golden 測試） |
| `Sources/GossipCore/Rng.swift` | mulberry32、`v8RandomSort`（V8 的 TimSort：先找第一段遞增／嚴格遞減的 run，再二分插入；n=2…12 對 Node 22 各 199/199）、穩定排序、Math.round |
| `Sources/GossipCore/Data.swift` | 讀 `GameData/data.json`（網頁 `node tools/export_native.mjs` 匯出：居民、地點、作息、八卦、五語文字、離線台詞、解析規則） |
| `Sources/GossipCore/Lines.swift` | lines.js：離線台詞、離線解析（NSRegularExpression，UTF-16 索引跟 JS 一樣）、離線聊天 |
| `Sources/coretest` | `golden`（對照網頁 `tools/golden_native.mjs` 產生的 `Tests/golden.txt`，10 個種子 × 4 天）、`smoke`（300 鎮 × 6 天 × 五語） |
| `App/GameVC.swift` | game.js 流程：標題 → 拜託 → 每段開話題（建議話題、打字、語音）→ 播放 → 進度卡 → 結算（星星、晚報、傳話樹）→ 下一天／重來；設定、存檔 |
| `App/TownView.swift` | render.js：地圖（cover、拖曳、鏡頭跟著講話的人）、頭像、泡泡、弧線、徽章、特效、地圖小物件 |
| `App/Net.swift` | llm.js：`/api/status`、`/api/llm`（quest／scene／chat／lines）；失敗就用 Lines 離線版。內部測試密碼門：設定頁輸入密碼 → POST `/__unlock` 拿 cookie（跟網頁一樣） |
| `App/Voice.swift` | 語音辨識（Speech，能在裝置上就只在裝置上；**說完文字進輸入框，不自動送出**）＋居民聲音（`/api/tts` Google 聲音，不行就系統語音），一句一句排隊 |
| `App/Prefs.swift` `Strings.swift` | 設定、五語（依手機語言，zh→繁中、ja/ko/es、其他→英文）、3 個存檔欄位＋匯出入 .json＋最近紀錄 |
| `App/Autopilot.swift` | CI 用：`-autotest tour -mock`（離線）走完一天並截圖；`-fold` 是 iPhone Duo 半摺版面（上半地圖、下半固定一半高的工作區） |
| `GameData/` | `data.json`（網頁匯出）、`img/town.webp`、`img/faces.webp`、`img/ui/*.png`（Gemini 圖示），都從網頁 repo 複製 |

## 改網頁之後
1. 網頁 repo：`node tools/export_native.mjs`（寫 GameData/data.json）＋ `node tools/golden_native.mjs`（寫 Tests/golden.txt）。
2. 這裡：`sh tools/swift.sh golden GameData/data.json Tests/golden.txt`（Docker swift:6.2-noble）必須 10/10 PASS。
3. 圖片有改就重新複製 `public/img/{town,faces}.webp`、`public/img/ui/*.png`。

## CI
- 只能在雲端 Mac 編：repo 公開 → push → `.github/workflows/ios.yml`（core test、模擬器 build、autopilot 截圖：zh、zh+fold、en，以及 ja/ko/es 標題）→ 結果在 `ci` 分支（`sh tools/ci_fetch.sh` → `.work/ci`）→ 改回私人。
- TestFlight：commit 訊息含 `[testflight]` 或 `python -I tools/gh.py dispatch testflight`（要先有 App Store Connect 的 App 記錄和 secrets）。
