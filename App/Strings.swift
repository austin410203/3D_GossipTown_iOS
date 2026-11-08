// Text that only the native app needs (the save screen of the web build lives in saveui.js, the lab password is new).
// Everything else comes from data.json (web i18n.js) through T().
import Foundation

private let NATIVE: [String: [String: String]] = [
  "zh": ["saves": "存檔", "slot": "存檔 {n}", "inUse": "使用中", "use": "使用這格", "newGame": "從這格開新遊戲", "export": "匯出", "import": "匯入", "delete": "刪除",
         "empty": "空的存檔欄位", "lastSave": "上次存檔：{d}", "records": "最近的遊玩紀錄", "noRecords": "還沒有紀錄", "confirmDelete": "再按一次刪除",
         "imported": "已匯入存檔 {n}", "importFailed": "這不是八卦小鎮的存檔", "lab": "內部測試密碼", "labHint": "輸入測試密碼就會連上 AI 居民（沒有也能用離線模式玩）",
         "unlock": "連線", "unlocked": "已連上 AI 居民", "wrong": "密碼不對，或連不上網路", "savesHint": "進度會自動存到「使用中」的欄位，也可以匯出 .json 備份或換裝置繼續。",
         "micDenied": "請到「設定」允許麥克風和語音辨識，或直接打字", "aiCost": "AI 用量：{n} 次・US$ {c}"],
  "en": ["saves": "Saves", "slot": "Slot {n}", "inUse": "In use", "use": "Use this slot", "newGame": "New game here", "export": "Export", "import": "Import", "delete": "Delete",
         "empty": "Empty slot", "lastSave": "Last saved: {d}", "records": "Recent results", "noRecords": "No results yet", "confirmDelete": "Tap again to delete",
         "imported": "Imported into slot {n}", "importFailed": "That isn't a Gossip Town save", "lab": "Test password", "labHint": "Enter the test password to talk to the AI residents (offline mode works without it)",
         "unlock": "Connect", "unlocked": "AI residents connected", "wrong": "Wrong password, or no connection", "savesHint": "Progress saves to the slot in use automatically. Export a .json to back it up or continue on another device.",
         "micDenied": "Allow the microphone and speech recognition in Settings, or just type", "aiCost": "AI use: {n} calls · US$ {c}"],
  "ja": ["saves": "セーブ", "slot": "スロット{n}", "inUse": "使用中", "use": "このスロットを使う", "newGame": "ここで新しく始める", "export": "書き出し", "import": "読み込み", "delete": "削除",
         "empty": "空きスロット", "lastSave": "最終セーブ：{d}", "records": "最近の結果", "noRecords": "まだ記録がありません", "confirmDelete": "もう一度押すと削除",
         "imported": "スロット{n}に読み込みました", "importFailed": "うわさの町のセーブではありません", "lab": "テスト用パスワード", "labHint": "テスト用パスワードを入れるとAI住人とつながります（なくてもオフラインで遊べます）",
         "unlock": "接続", "unlocked": "AI住人とつながりました", "wrong": "パスワードが違うか、接続できません", "savesHint": "進行は使用中のスロットに自動セーブ。.json に書き出してバックアップや機種変更にも。",
         "micDenied": "設定でマイクと音声認識を許可するか、入力してください", "aiCost": "AI使用：{n}回・US$ {c}"],
  "ko": ["saves": "저장", "slot": "슬롯 {n}", "inUse": "사용 중", "use": "이 슬롯 사용", "newGame": "여기서 새로 시작", "export": "내보내기", "import": "가져오기", "delete": "삭제",
         "empty": "빈 슬롯", "lastSave": "마지막 저장: {d}", "records": "최근 기록", "noRecords": "아직 기록이 없어요", "confirmDelete": "한 번 더 누르면 삭제",
         "imported": "슬롯 {n}에 가져왔어요", "importFailed": "소문 마을 저장 파일이 아니에요", "lab": "테스트 비밀번호", "labHint": "테스트 비밀번호를 넣으면 AI 주민과 연결돼요 (없어도 오프라인으로 플레이 가능)",
         "unlock": "연결", "unlocked": "AI 주민과 연결됨", "wrong": "비밀번호가 틀렸거나 연결할 수 없어요", "savesHint": "진행은 사용 중인 슬롯에 자동 저장돼요. .json으로 내보내 백업하거나 다른 기기에서 이어 하세요.",
         "micDenied": "설정에서 마이크와 음성 인식을 허용하거나 입력해 주세요", "aiCost": "AI 사용: {n}회 · US$ {c}"],
  "es": ["saves": "Partidas", "slot": "Ranura {n}", "inUse": "En uso", "use": "Usar esta ranura", "newGame": "Nueva partida aquí", "export": "Exportar", "import": "Importar", "delete": "Borrar",
         "empty": "Ranura vacía", "lastSave": "Guardado: {d}", "records": "Resultados recientes", "noRecords": "Aún no hay resultados", "confirmDelete": "Toca otra vez para borrar",
         "imported": "Importado en la ranura {n}", "importFailed": "Eso no es una partida de Pueblo Chismoso", "lab": "Contraseña de prueba", "labHint": "Escribe la contraseña de prueba para hablar con los vecinos IA (sin ella se juega sin conexión)",
         "unlock": "Conectar", "unlocked": "Vecinos IA conectados", "wrong": "Contraseña incorrecta o sin conexión", "savesHint": "El progreso se guarda solo en la ranura en uso. Exporta un .json para copia de seguridad o para seguir en otro dispositivo.",
         "micDenied": "Permite el micrófono y el reconocimiento de voz en Ajustes, o escribe", "aiCost": "Uso de IA: {n} llamadas · US$ {c}"],
]
/// native-only text
func N(_ key: String, _ p: [String: String] = [:]) -> String {
  var s = NATIVE[LANG]?[key] ?? NATIVE["en"]?[key] ?? key
  for (k, v) in p { s = s.replacingOccurrences(of: "{\(k)}", with: v) }
  return s
}
