-- anki-learning skill schema
-- Database: anki_learning

CREATE TABLE decks (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    description TEXT,
    source_file TEXT,
    card_count INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE cards (
    id SERIAL PRIMARY KEY,
    deck_id INTEGER NOT NULL REFERENCES decks(id) ON DELETE CASCADE,
    expression TEXT NOT NULL,
    reading TEXT,
    pitch TEXT,
    meaning TEXT NOT NULL,
    example_sentences TEXT,
    related_words TEXT,
    synonyms TEXT,
    audio_ref TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE user_progress (
    id SERIAL PRIMARY KEY,
    discord_user_id TEXT NOT NULL,
    discord_user_name TEXT NOT NULL,
    card_id INTEGER NOT NULL REFERENCES cards(id) ON DELETE CASCADE,
    deck_id INTEGER NOT NULL REFERENCES decks(id) ON DELETE CASCADE,
    times_seen INTEGER NOT NULL DEFAULT 1,
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(discord_user_id, card_id)
);

CREATE INDEX idx_cards_deck ON cards(deck_id);
CREATE INDEX idx_progress_user ON user_progress(discord_user_id);
CREATE INDEX idx_progress_user_deck ON user_progress(discord_user_id, deck_id);
CREATE INDEX idx_progress_card ON user_progress(card_id);
