#!/bin/bash
set -euo pipefail

# Import an Anki .apkg file into the anki_learning PostgreSQL database.
# Usage: import-deck.sh <apkg-file> [deck-name]

DB_NAME="${ANKI_DB_NAME:-anki_learning}"
DB_USER="${ANKI_DB_USER:-$(whoami)}"
DB_HOST="${ANKI_DB_HOST:-localhost}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCHEMA_PATH="$SCRIPT_DIR/../schema.sql"

die_json() {
  jq -n --arg error "$1" '{error: $error}' >&2
  exit 1
}

ensure_database() {
  local db_exists
  db_exists=$(psql -h "$DB_HOST" -U "$DB_USER" -d postgres -tAc \
    "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" 2>/dev/null || true)
  if [[ "$db_exists" != "1" ]]; then
    psql -h "$DB_HOST" -U "$DB_USER" -d postgres -c "CREATE DATABASE \"$DB_NAME\";" 2>/dev/null || true
    if ! psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -f "$SCHEMA_PATH" >/dev/null 2>&1; then
      die_json "failed to initialize anki_learning database schema"
    fi
  fi
}

if [[ $# -lt 1 ]]; then
  die_json "usage: import-deck.sh <apkg-file> [deck-name]"
fi

APKG_FILE="$1"
DECK_NAME="${2:-$(basename "$APKG_FILE" .apkg)}"

if [[ ! -f "$APKG_FILE" ]]; then
  die_json "file not found: $APKG_FILE"
fi

ensure_database

# Check if deck already exists
existing=$(psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -tAc \
  "SELECT id FROM decks WHERE name = '${DECK_NAME}';" 2>/dev/null | tr -d '[:space:]')

if [[ -n "$existing" ]]; then
  die_json "deck '$DECK_NAME' already exists (id=$existing). Delete it first or use a different name."
fi

# Extract apkg to temp dir
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

unzip -o "$APKG_FILE" -d "$TMPDIR" > /dev/null 2>&1

# Find the SQLite database
SQLITE_DB=""
for candidate in collection.anki21 collection.anki2; do
  if [[ -f "$TMPDIR/$candidate" ]]; then
    ftype=$(file -b "$TMPDIR/$candidate")
    if [[ "$ftype" == *"SQLite"* ]]; then
      SQLITE_DB="$TMPDIR/$candidate"
      break
    fi
  fi
done

if [[ -z "$SQLITE_DB" ]]; then
  die_json "no valid SQLite database found in apkg"
fi

# Use Python to reliably extract and insert data
export DB_NAME DB_USER DB_HOST SQLITE_DB DECK_NAME APKG_FILE
UV="${UV_BIN:-$HOME/.local/bin/uv}"
"$UV" run --no-project --python 3 --with psycopg2-binary python3 << 'PYEOF'
import sqlite3
import psycopg2
import re
import os
import json
import sys

db_name = os.environ.get("DB_NAME", "anki_learning")
db_user = os.environ.get("DB_USER", os.getlogin())
db_host = os.environ.get("DB_HOST", "localhost")
sqlite_path = os.environ["SQLITE_DB"]
deck_name = os.environ["DECK_NAME"]
apkg_file = os.environ["APKG_FILE"]

def strip_html(text):
    if not text:
        return ""
    return re.sub(r'<[^>]+>', '', text).strip()

def nullif_empty(text):
    s = strip_html(text)
    return s if s else None

conn = psycopg2.connect(dbname=db_name, user=db_user, host=db_host)
conn.autocommit = False
cur = conn.cursor()

try:
    sconn = sqlite3.connect(sqlite_path)
    scur = sconn.cursor()

    note_count = scur.execute("SELECT COUNT(*) FROM notes").fetchone()[0]

    cur.execute(
        "INSERT INTO decks (name, description, source_file, card_count) VALUES (%s, %s, %s, %s) RETURNING id",
        (deck_name, f"Imported from {deck_name}.apkg", os.path.basename(apkg_file), note_count)
    )
    deck_id = cur.fetchone()[0]

    imported = 0
    for (flds,) in scur.execute("SELECT flds FROM notes"):
        fields = flds.split('\x1f')
        expression = strip_html(fields[0]) if len(fields) > 0 else ""
        reading = nullif_empty(fields[1]) if len(fields) > 1 else None
        pitch = nullif_empty(fields[2]) if len(fields) > 2 else None
        meaning = strip_html(fields[3]) if len(fields) > 3 else ""
        examples = nullif_empty(fields[4]) if len(fields) > 4 else None
        related = nullif_empty(fields[5]) if len(fields) > 5 else None
        synonyms = nullif_empty(fields[6]) if len(fields) > 6 else None
        audio = nullif_empty(fields[10]) if len(fields) > 10 else None

        if not expression or not meaning:
            continue

        cur.execute(
            """INSERT INTO cards (deck_id, expression, reading, pitch, meaning, example_sentences, related_words, synonyms, audio_ref)
               VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)""",
            (deck_id, expression, reading, pitch, meaning, examples, related, synonyms, audio)
        )
        imported += 1

    cur.execute("UPDATE decks SET card_count = %s WHERE id = %s", (imported, deck_id))
    conn.commit()

    print(json.dumps({"deck_id": deck_id, "deck_name": deck_name, "cards_imported": imported}))

except Exception as e:
    conn.rollback()
    print(json.dumps({"error": str(e)}), file=sys.stderr)
    sys.exit(1)
finally:
    cur.close()
    conn.close()
    sconn.close()
PYEOF
