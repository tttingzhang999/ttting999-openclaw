#!/bin/bash
set -euo pipefail

DB_NAME="${ANKI_DB_NAME:-anki_learning}"
DB_USER="${ANKI_DB_USER:-$(whoami)}"
DB_HOST="${ANKI_DB_HOST:-localhost}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCHEMA_PATH="$SCRIPT_DIR/../schema.sql"

die_json() {
  jq -n --arg error "$1" '{error: $error}' >&2
  exit 1
}

psql_cmd() {
  local result
  if ! result=$(psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -tAc "$1" 2>&1); then
    jq -n --arg error "database error" --arg detail "$result" '{error: $error, detail: $detail}' >&2
    exit 1
  fi
  echo "$result"
}

psql_json() {
  local result
  if ! result=$(psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" --no-align --tuples-only -c "$1" 2>&1); then
    jq -n --arg error "database error" --arg detail "$result" '{error: $error, detail: $detail}' >&2
    exit 1
  fi
  echo "$result"
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

# ─── Commands ───

cmd_list_decks() {
  ensure_database
  psql_json "SELECT json_agg(row_to_json(d)) FROM (
    SELECT id, name, description, card_count, created_at
    FROM decks ORDER BY name
  ) d;"
}

cmd_deck_info() {
  local deck_name=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --deck) deck_name="$2"; shift 2 ;;
      *) die_json "unknown option: $1" ;;
    esac
  done
  [[ -z "$deck_name" ]] && die_json "missing --deck"
  ensure_database

  psql_json "SELECT json_build_object(
    'deck', (SELECT row_to_json(d) FROM (SELECT id, name, description, card_count FROM decks WHERE name = \$\$$deck_name\$\$) d),
    'sample_cards', (SELECT json_agg(row_to_json(c)) FROM (
      SELECT id, expression, reading, meaning FROM cards
      WHERE deck_id = (SELECT id FROM decks WHERE name = \$\$$deck_name\$\$)
      ORDER BY RANDOM() LIMIT 3
    ) c)
  );"
}

cmd_study() {
  local deck_name="" user_id="" user_name="" count=5
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --deck) deck_name="$2"; shift 2 ;;
      --user-id) user_id="$2"; shift 2 ;;
      --user-name) user_name="$2"; shift 2 ;;
      --count) count="$2"; shift 2 ;;
      *) die_json "unknown option: $1" ;;
    esac
  done
  [[ -z "$deck_name" ]] && die_json "missing --deck"
  [[ -z "$user_id" ]] && die_json "missing --user-id"
  [[ -z "$user_name" ]] && die_json "missing --user-name"

  # Validate count is a positive integer
  if ! [[ "$count" =~ ^[1-9][0-9]*$ ]] || [[ "$count" -gt 50 ]]; then
    die_json "count must be 1-50"
  fi

  ensure_database

  # Get deck id
  local deck_id
  deck_id=$(psql_cmd "SELECT id FROM decks WHERE name = \$\$$deck_name\$\$;")
  [[ -z "$deck_id" ]] && die_json "deck not found: $deck_name"

  # Select cards the user has NOT seen yet, random order
  local cards
  cards=$(psql_json "SELECT json_agg(row_to_json(c)) FROM (
    SELECT c.id, c.expression, c.reading, c.pitch, c.meaning,
           c.example_sentences, c.related_words, c.synonyms
    FROM cards c
    WHERE c.deck_id = $deck_id
      AND c.id NOT IN (
        SELECT card_id FROM user_progress
        WHERE discord_user_id = \$\$$user_id\$\$ AND deck_id = $deck_id
      )
    ORDER BY RANDOM()
    LIMIT $count
  ) c;")

  # Record progress for each card
  if [[ "$cards" != "null" && -n "$cards" ]]; then
    local card_ids
    card_ids=$(echo "$cards" | jq -r '.[] | .id' 2>/dev/null)
    for cid in $card_ids; do
      psql_cmd "INSERT INTO user_progress (discord_user_id, discord_user_name, card_id, deck_id)
                VALUES (\$\$$user_id\$\$, \$\$$user_name\$\$, $cid, $deck_id)
                ON CONFLICT (discord_user_id, card_id)
                DO UPDATE SET times_seen = user_progress.times_seen + 1, last_seen_at = NOW();" > /dev/null
    done
  fi

  # Get progress stats
  local total_cards seen_cards
  total_cards=$(psql_cmd "SELECT card_count FROM decks WHERE id = $deck_id;")
  seen_cards=$(psql_cmd "SELECT COUNT(*) FROM user_progress WHERE discord_user_id = \$\$$user_id\$\$ AND deck_id = $deck_id;")

  jq -n \
    --arg deck "$deck_name" \
    --argjson cards "${cards:-null}" \
    --arg total "$total_cards" \
    --arg seen "$seen_cards" \
    '{deck: $deck, cards: $cards, progress: {total: ($total | tonumber), seen: ($seen | tonumber), remaining: (($total | tonumber) - ($seen | tonumber))}}'
}

cmd_progress() {
  local user_id="" deck_name=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --user-id) user_id="$2"; shift 2 ;;
      --deck) deck_name="$2"; shift 2 ;;
      *) die_json "unknown option: $1" ;;
    esac
  done
  [[ -z "$user_id" ]] && die_json "missing --user-id"

  ensure_database

  local where_deck=""
  if [[ -n "$deck_name" ]]; then
    where_deck="AND d.name = \$\$$deck_name\$\$"
  fi

  psql_json "SELECT json_agg(row_to_json(p)) FROM (
    SELECT d.name AS deck_name, d.card_count AS total,
           COUNT(up.id) AS seen,
           d.card_count - COUNT(up.id) AS remaining,
           MAX(up.last_seen_at) AS last_studied
    FROM decks d
    LEFT JOIN user_progress up ON up.deck_id = d.id AND up.discord_user_id = \$\$$user_id\$\$
    WHERE 1=1 $where_deck
    GROUP BY d.id, d.name, d.card_count
    ORDER BY d.name
  ) p;"
}

cmd_reset() {
  local user_id="" deck_name=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --user-id) user_id="$2"; shift 2 ;;
      --deck) deck_name="$2"; shift 2 ;;
      *) die_json "unknown option: $1" ;;
    esac
  done
  [[ -z "$user_id" ]] && die_json "missing --user-id"
  [[ -z "$deck_name" ]] && die_json "missing --deck"

  ensure_database

  local deck_id
  deck_id=$(psql_cmd "SELECT id FROM decks WHERE name = \$\$$deck_name\$\$;")
  [[ -z "$deck_id" ]] && die_json "deck not found: $deck_name"

  local deleted
  deleted=$(psql_cmd "DELETE FROM user_progress WHERE discord_user_id = \$\$$user_id\$\$ AND deck_id = $deck_id RETURNING id;" | wc -l)

  jq -n --arg deck "$deck_name" --arg deleted "$deleted" \
    '{deck: $deck, records_cleared: ($deleted | tonumber)}'
}

cmd_delete_deck() {
  local deck_name=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --deck) deck_name="$2"; shift 2 ;;
      *) die_json "unknown option: $1" ;;
    esac
  done
  [[ -z "$deck_name" ]] && die_json "missing --deck"

  ensure_database

  local deck_id
  deck_id=$(psql_cmd "SELECT id FROM decks WHERE name = \$\$$deck_name\$\$;")
  [[ -z "$deck_id" ]] && die_json "deck not found: $deck_name"

  # CASCADE will delete cards and progress
  psql_cmd "DELETE FROM decks WHERE id = $deck_id;" > /dev/null

  jq -n --arg deck "$deck_name" '{deleted: $deck}'
}

# ─── Main ───

ensure_database

CMD="${1:-help}"
shift || true

case "$CMD" in
  list-decks)    cmd_list_decks "$@" ;;
  deck-info)     cmd_deck_info "$@" ;;
  study)         cmd_study "$@" ;;
  progress)      cmd_progress "$@" ;;
  reset)         cmd_reset "$@" ;;
  delete-deck)   cmd_delete_deck "$@" ;;
  help)
    jq -n '{
      commands: {
        "list-decks": "List all available decks",
        "deck-info --deck <name>": "Show deck details and sample cards",
        "study --deck <name> --user-id <id> --user-name <name> [--count N]": "Get N unseen cards (default 5) and record progress",
        "progress --user-id <id> [--deck <name>]": "Show learning progress per deck",
        "reset --user-id <id> --deck <name>": "Reset progress for a deck",
        "delete-deck --deck <name>": "Delete a deck and all its cards/progress"
      }
    }'
    ;;
  *) die_json "unknown command: $CMD. Use 'help' for usage." ;;
esac
