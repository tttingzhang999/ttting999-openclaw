#!/bin/bash
set -euo pipefail

DB_NAME="expense"
DB_USER="postgres"
DB_HOST="localhost"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCHEMA_PATH="$SCRIPT_DIR/../schema.sql"

die_json() {
  jq -n --arg error "$1" '{error: $error}' >&2
  exit 1
}

psql_cmd() {
  local result err
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
  db_exists=$(psql -h "$DB_HOST" -U "$DB_USER" -tAc \
    "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" 2>/dev/null || true)
  if [[ "$db_exists" != "1" ]]; then
    psql -h "$DB_HOST" -U "$DB_USER" -c "CREATE DATABASE \"$DB_NAME\";" 2>/dev/null || true
    if ! psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -f "$SCHEMA_PATH" >/dev/null 2>&1; then
      echo '{"error":"failed to initialize expense database schema"}' >&2
      exit 1
    fi
    echo '{"status":"initialized","message":"expense database created"}' >&2
  fi
}

validate_integer() {
  local value="$1" field="$2"
  if ! [[ "$value" =~ ^[0-9]+$ ]] || [[ "$value" -eq 0 ]]; then
    jq -n --arg error "$field must be a positive integer, got: $value" '{error: $error}'
    exit 1
  fi
}

validate_type() {
  local value="$1"
  if [[ "$value" != "expense" && "$value" != "income" ]]; then
    jq -n --arg error "type must be 'expense' or 'income', got: $value" '{error: $error}'
    exit 1
  fi
}

validate_scope() {
  local value="$1"
  if [[ "$value" != "expense" && "$value" != "income" && "$value" != "both" ]]; then
    jq -n --arg error "scope must be 'expense', 'income', or 'both', got: $value" '{error: $error}'
    exit 1
  fi
}

validate_date() {
  local value="$1"
  if ! [[ "$value" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    jq -n --arg error "date must be YYYY-MM-DD, got: $value" '{error: $error}'
    exit 1
  fi
}

validate_month() {
  local value="$1"
  if ! [[ "$value" =~ ^[0-9]{4}-[0-9]{2}$ ]]; then
    jq -n --arg error "month must be YYYY-MM, got: $value" '{error: $error}'
    exit 1
  fi
}

escape_sql() {
  local val="$1"
  val="${val//\\/\\\\}"
  val="${val//\'/\'\'}"
  echo "$val"
}

cmd_add() {
  local tx_type="expense" amount="" category="" desc="" user_id="" user_name="" tx_date="" note=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --type)      tx_type="$2"; shift 2 ;;
      --amount)    amount="$2"; shift 2 ;;
      --category)  category="$2"; shift 2 ;;
      --desc)      desc="$2"; shift 2 ;;
      --user-id)   user_id="$2"; shift 2 ;;
      --user-name) user_name="$2"; shift 2 ;;
      --date)      tx_date="$2"; shift 2 ;;
      --note)      note="$2"; shift 2 ;;
      *) jq -n --arg error "unknown option: $1" '{error: $error}'; exit 1 ;;
    esac
  done

  if [[ -z "$amount" || -z "$category" || -z "$desc" || -z "$user_id" || -z "$user_name" ]]; then
    jq -n --arg error "required: --amount, --category, --desc, --user-id, --user-name" '{error: $error}'
    exit 1
  fi

  validate_integer "$amount" "amount"
  validate_type "$tx_type"
  if [[ -n "$tx_date" ]]; then
    validate_date "$tx_date"
  fi

  local safe_category safe_desc safe_user_id safe_user_name safe_note
  safe_category=$(escape_sql "$category")
  safe_desc=$(escape_sql "$desc")
  safe_user_id=$(escape_sql "$user_id")
  safe_user_name=$(escape_sql "$user_name")
  safe_note=$(escape_sql "${note:-}")

  local cat_id
  cat_id=$(psql_cmd "SELECT id FROM categories WHERE name = '$safe_category'")
  if [[ -z "$cat_id" ]]; then
    jq -n --arg error "category not found: $category" --arg hint "use 'categories' command to list available categories" '{error: $error, hint: $hint}'
    exit 1
  fi

  local date_clause
  if [[ -n "$tx_date" ]]; then
    date_clause="'$tx_date'"
  else
    date_clause="CURRENT_DATE"
  fi

  local note_clause
  if [[ -n "$note" ]]; then
    note_clause="'$safe_note'"
  else
    note_clause="NULL"
  fi

  local insert_json
  insert_json=$(psql_json "
    SELECT json_build_object('id', id, 'tx_date', tx_date)
    FROM (
      INSERT INTO transactions (type, amount, category_id, description, note, discord_user_id, discord_user_name, tx_date)
      VALUES ('$tx_type', $amount, $cat_id, '$safe_desc', $note_clause, '$safe_user_id', '$safe_user_name', $date_clause)
      RETURNING id, tx_date
    ) ins
  ")

  local new_id new_date
  new_id=$(echo "$insert_json" | jq -r '.id')
  new_date=$(echo "$insert_json" | jq -r '.tx_date')

  local totals_json
  totals_json=$(psql_json "
    SELECT json_build_object(
      'expense_total', COALESCE(SUM(CASE WHEN type='expense' THEN amount ELSE 0 END), 0),
      'income_total', COALESCE(SUM(CASE WHEN type='income' THEN amount ELSE 0 END), 0)
    )
    FROM transactions
    WHERE discord_user_id = '$safe_user_id'
      AND date_trunc('month', tx_date) = date_trunc('month', '$new_date'::date)
  ")

  local expense_total income_total
  expense_total=$(echo "$totals_json" | jq -r '.expense_total')
  income_total=$(echo "$totals_json" | jq -r '.income_total')

  jq -n \
    --arg status "ok" \
    --argjson id "$new_id" \
    --arg type "$tx_type" \
    --argjson amount "$amount" \
    --arg category "$category" \
    --arg description "$desc" \
    --arg date "$new_date" \
    --argjson month_expense_total "$expense_total" \
    --argjson month_income_total "$income_total" \
    '{status: $status, id: $id, type: $type, amount: $amount, category: $category, description: $description, date: $date, month_expense_total: $month_expense_total, month_income_total: $month_income_total}'
}

cmd_categories() {
  local filter_type=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --type) filter_type="$2"; shift 2 ;;
      *) jq -n --arg error "unknown option: $1" '{error: $error}'; exit 1 ;;
    esac
  done

  if [[ -n "$filter_type" ]]; then
    validate_scope "$filter_type"
  fi

  local where_clause=""
  if [[ -n "$filter_type" ]]; then
    where_clause="WHERE applicable_type = '$filter_type' OR applicable_type = 'both'"
  fi

  local rows
  rows=$(psql_json "SELECT COALESCE(json_agg(json_build_object('id', id, 'name', name, 'icon', icon, 'applicable_type', applicable_type)), '[]'::json) FROM categories $where_clause")

  if [[ -z "$rows" ]]; then
    echo "[]"
  else
    echo "$rows"
  fi
}

cmd_add_category() {
  local name="" icon="" scope="both"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)  name="$2"; shift 2 ;;
      --icon)  icon="$2"; shift 2 ;;
      --scope) scope="$2"; shift 2 ;;
      *) jq -n --arg error "unknown option: $1" '{error: $error}'; exit 1 ;;
    esac
  done

  if [[ -z "$name" ]]; then
    jq -n --arg error "required: --name" '{error: $error}'
    exit 1
  fi

  validate_scope "$scope"

  local safe_name safe_icon
  safe_name=$(escape_sql "$name")
  safe_icon=$(escape_sql "${icon:-}")

  local icon_clause
  if [[ -n "$icon" ]]; then
    icon_clause="'$safe_icon'"
  else
    icon_clause="NULL"
  fi

  local result
  result=$(psql_cmd "
    INSERT INTO categories (name, icon, applicable_type)
    VALUES ('$safe_name', $icon_clause, '$scope')
    ON CONFLICT (name) DO NOTHING
    RETURNING id
  ")

  if [[ -z "$result" ]]; then
    jq -n --arg error "category already exists: $name" '{error: $error}'
    exit 1
  fi

  jq -n \
    --arg status "ok" \
    --argjson id "$result" \
    --arg name "$name" \
    --arg icon "${icon:-}" \
    --arg scope "$scope" \
    '{status: $status, id: $id, name: $name, icon: $icon, scope: $scope}'
}

cmd_summary() {
  local month="" user_id=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --month)   month="$2"; shift 2 ;;
      --user-id) user_id="$2"; shift 2 ;;
      *) jq -n --arg error "unknown option: $1" '{error: $error}'; exit 1 ;;
    esac
  done

  if [[ -z "$month" ]]; then
    month=$(date +%Y-%m)
  fi

  validate_month "$month"

  local user_filter=""
  if [[ -n "$user_id" ]]; then
    local safe_uid
    safe_uid=$(escape_sql "$user_id")
    user_filter="AND t.discord_user_id = '$safe_uid'"
  fi

  local summary
  summary=$(psql_json "
    SELECT json_build_object(
      'month', '$month',
      'expense_total', COALESCE(SUM(CASE WHEN t.type='expense' THEN t.amount ELSE 0 END), 0),
      'income_total', COALESCE(SUM(CASE WHEN t.type='income' THEN t.amount ELSE 0 END), 0),
      'transaction_count', COUNT(*),
      'by_category', (
        SELECT COALESCE(json_agg(json_build_object(
          'category', sub.cat_name,
          'icon', sub.cat_icon,
          'type', sub.tx_type,
          'total', sub.total,
          'count', sub.cnt
        )), '[]'::json)
        FROM (
          SELECT c.name AS cat_name, c.icon AS cat_icon, t2.type AS tx_type,
                 SUM(t2.amount) AS total, COUNT(*) AS cnt
          FROM transactions t2
          JOIN categories c ON c.id = t2.category_id
          WHERE date_trunc('month', t2.tx_date) = '$month-01'::date
            $user_filter
          GROUP BY c.name, c.icon, t2.type
          ORDER BY total DESC
        ) sub
      )
    )
    FROM transactions t
    WHERE date_trunc('month', t.tx_date) = '$month-01'::date
      $user_filter
  ")

  if [[ -z "$summary" ]]; then
    jq -n --arg month "$month" '{month: $month, expense_total: 0, income_total: 0, transaction_count: 0, by_category: []}'
  else
    echo "$summary"
  fi
}

cmd_list() {
  local days=7 user_id=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --days)    days="$2"; shift 2 ;;
      --user-id) user_id="$2"; shift 2 ;;
      *) jq -n --arg error "unknown option: $1" '{error: $error}'; exit 1 ;;
    esac
  done

  validate_integer "$days" "days"

  local user_filter=""
  if [[ -n "$user_id" ]]; then
    local safe_uid
    safe_uid=$(escape_sql "$user_id")
    user_filter="AND t.discord_user_id = '$safe_uid'"
  fi

  local rows
  rows=$(psql_json "
    SELECT COALESCE(json_agg(json_build_object(
      'id', t.id,
      'type', t.type,
      'amount', t.amount,
      'category', c.name,
      'icon', c.icon,
      'description', t.description,
      'note', t.note,
      'user_name', t.discord_user_name,
      'date', t.tx_date
    ) ORDER BY t.tx_date DESC, t.id DESC), '[]'::json)
    FROM transactions t
    JOIN categories c ON c.id = t.category_id
    WHERE t.tx_date >= CURRENT_DATE - INTERVAL '$days days'
      $user_filter
  ")

  if [[ -z "$rows" ]]; then
    echo "[]"
  else
    echo "$rows"
  fi
}

ensure_database

case "${1:-}" in
  add)          shift; cmd_add "$@" ;;
  categories)   shift; cmd_categories "$@" ;;
  add-category) shift; cmd_add_category "$@" ;;
  summary)      shift; cmd_summary "$@" ;;
  list)         shift; cmd_list "$@" ;;
  *)
    jq -n --arg error "unknown command: ${1:-}" --arg usage "expense.sh <add|categories|add-category|summary|list> [options]" '{error: $error, usage: $usage}'
    exit 1
    ;;
esac
