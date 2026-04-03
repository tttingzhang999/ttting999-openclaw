# Anki Learning DB Schema

Database: `anki_learning` (PostgreSQL, localhost)

## Tables

### decks

| Column | Type | Description |
|--------|------|-------------|
| id | SERIAL PK | Auto-increment ID |
| name | TEXT UNIQUE | 牌組名稱（如 N5, N4） |
| description | TEXT | 牌組描述 |
| source_file | TEXT | 原始 .apkg 檔名 |
| card_count | INTEGER | 卡片總數 |
| created_at | TIMESTAMPTZ | 建立時間 |

### cards

| Column | Type | Description |
|--------|------|-------------|
| id | SERIAL PK | Auto-increment ID |
| deck_id | INTEGER FK→decks | 所屬牌組 |
| expression | TEXT | 單字（漢字或假名） |
| reading | TEXT NULL | 假名讀音 |
| pitch | TEXT NULL | 聲調標記 |
| meaning | TEXT | 中文釋義 |
| example_sentences | TEXT NULL | 例句 |
| related_words | TEXT NULL | 慣用語/相關詞 |
| synonyms | TEXT NULL | 同音/同義詞 |
| audio_ref | TEXT NULL | 音檔參考 |
| created_at | TIMESTAMPTZ | 建立時間 |

### user_progress

| Column | Type | Description |
|--------|------|-------------|
| id | SERIAL PK | Auto-increment ID |
| discord_user_id | TEXT | Discord snowflake ID |
| discord_user_name | TEXT | Discord 顯示名稱 |
| card_id | INTEGER FK→cards | 學過的卡片 |
| deck_id | INTEGER FK→decks | 所屬牌組（方便查詢） |
| times_seen | INTEGER | 看過幾次 |
| last_seen_at | TIMESTAMPTZ | 最後一次看的時間 |

UNIQUE constraint: (discord_user_id, card_id) — 每人每卡片一筆記錄

## Indexes

- `idx_cards_deck` on cards(deck_id)
- `idx_progress_user` on user_progress(discord_user_id)
- `idx_progress_user_deck` on user_progress(discord_user_id, deck_id)
- `idx_progress_card` on user_progress(card_id)
