---
name: anki-learning
description: Anki-like vocabulary learning system. Presents flashcards from imported decks, tracks per-user progress via Discord, and ensures no repeats. Use when users mention studying, vocabulary, flashcards, 單字, 學習, or ask for word quizzes.
---

# Anki Learning System

## 觸發條件

當使用者提到學習、單字、背單字、複習、flashcard、vocabulary 等相關請求時觸發。

## 指令

### Step 1: 識別用戶

從對話 context 取得發訊者的 Discord 顯示名稱和唯一 ID。作為 `--user-id` 和 `--user-name` 傳入指令。

### Step 2: 理解意圖

判斷用戶想做什麼：
- **瀏覽目錄**: 想看有哪些學習牌組 → `list-decks`
- **開始學習**: 想從某個牌組抽單字 → `study`
- **查看進度**: 想知道學了多少 → `progress`
- **重置進度**: 想重新開始 → `reset`（需確認）

### Step 3: 執行對應指令

所有指令透過 `{baseDir}/scripts/anki-learning.sh` 執行。

#### 瀏覽牌組

```bash
{baseDir}/scripts/anki-learning.sh list-decks
```

回覆格式（以目錄呈現）：
> 📚 目前有以下牌組：
> 1. **N5** — 926 個單字
> 2. **N4** — 1107 個單字
> ...
> 你想學哪一個？

#### 開始學習

```bash
{baseDir}/scripts/anki-learning.sh study --deck <name> --user-id <id> --user-name <name> --count 5
```

系統會自動排除該用戶已學過的單字，隨機抽取 5 張新卡片。

**回覆格式**（每張卡片都要包含以下內容，LLM 應補足缺漏的部分）：

對每張卡片，呈現：

1. **單字**（expression）+ 假名（reading）+ 聲調（pitch）
2. **中文意思**（meaning）
3. **例句**：取自 `example_sentences`，若資料不足則 LLM 自行補充 1-2 個自然的例句，附中文翻譯
4. **相關詞/同義詞**：若有 `related_words` 或 `synonyms` 則列出
5. **記憶提示**（LLM 補充）：簡短的助記法或語境提示，幫助記憶

卡片之間用分隔線區隔。

最後附上進度：
> 📊 {deck_name} 進度：已學 {seen}/{total}，剩餘 {remaining}

#### 查看進度

```bash
{baseDir}/scripts/anki-learning.sh progress --user-id <id>
# 或指定牌組
{baseDir}/scripts/anki-learning.sh progress --user-id <id> --deck <name>
```

#### 重置進度

需先確認後才執行：
```bash
{baseDir}/scripts/anki-learning.sh reset --user-id <id> --deck <name>
```

### Step 4: 互動引導

- 學完一組後，問用戶「要繼續下一組嗎？」
- 用戶沒指定數量時，預設 5 張
- 若牌組內所有卡片都學完，恭喜用戶並建議換下一個牌組或重置

## 匯入新牌組

管理員可透過 `import-deck.sh` 匯入 Anki `.apkg` 檔：

```bash
{baseDir}/scripts/import-deck.sh <apkg-file> [deck-name]
```

牌組原始檔案放在 `{baseDir}/decks/` 目錄。

## 規則

- 回應使用繁體中文
- **禁止直接執行 psql 或任何 raw SQL，只能透過 anki-learning.sh 操作資料庫**
- 每次學習自動記錄進度，下次抽卡不會重複已見過的單字
- LLM 應主動補足卡片資料中缺少的例句、語境說明，讓學習體驗更豐富
- 數量上限 50，預設 5
