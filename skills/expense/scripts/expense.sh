#!/bin/bash
set -euo pipefail

DB_NAME="${EXPENSE_DB_NAME:-expense}"
DB_USER="${EXPENSE_DB_USER:-$(whoami)}"
DB_HOST="${EXPENSE_DB_HOST:-localhost}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCHEMA_PATH="$SCRIPT_DIR/../schema.sql"

trim() {
  local var="$1"
  var="${var#"${var%%[![:space:]]*}"}"
  var="${var%"${var##*[![:space:]]}"}"
  echo "$var"
}

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
  # psql -tAc may include command tags (e.g. "INSERT 0 1") on extra lines; take only the first line
  trim "$(echo "$result" | head -n1)"
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
    WITH ins AS (
      INSERT INTO transactions (type, amount, category_id, description, note, discord_user_id, discord_user_name, tx_date)
      VALUES ('$tx_type', $amount, $cat_id, '$safe_desc', $note_clause, '$safe_user_id', '$safe_user_name', $date_clause)
      RETURNING id, tx_date
    )
    SELECT json_build_object('id', id, 'tx_date', tx_date) FROM ins
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

  new_id=$(trim "$new_id")
  expense_total=$(trim "$expense_total")
  income_total=$(trim "$income_total")

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

  local user_filter="" user_filter_t2=""
  if [[ -n "$user_id" ]]; then
    local safe_uid
    safe_uid=$(escape_sql "$user_id")
    user_filter="AND t.discord_user_id = '$safe_uid'"
    user_filter_t2="AND t2.discord_user_id = '$safe_uid'"
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
            $user_filter_t2
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

cmd_delete() {
  local id="" user_id=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --id)      id="$2"; shift 2 ;;
      --user-id) user_id="$2"; shift 2 ;;
      *) jq -n --arg error "unknown option: $1" '{error: $error}'; exit 1 ;;
    esac
  done

  if [[ -z "$id" || -z "$user_id" ]]; then
    jq -n --arg error "required: --id, --user-id" '{error: $error}'
    exit 1
  fi

  validate_integer "$id" "id"

  local safe_uid
  safe_uid=$(escape_sql "$user_id")

  local deleted
  deleted=$(psql_json "
    WITH del AS (
      DELETE FROM transactions
      WHERE id = $id AND discord_user_id = '$safe_uid'
      RETURNING id, type, amount, description, tx_date
    )
    SELECT json_build_object(
      'id', id, 'type', type, 'amount', amount,
      'description', description, 'date', tx_date
    ) FROM del
  ")

  if [[ -z "$deleted" || "$deleted" == "" ]]; then
    jq -n --arg error "record not found or not owned by user" --argjson id "$id" '{error: $error, id: $id}'
    exit 1
  fi

  local del_id del_type del_amount del_desc del_date
  del_id=$(echo "$deleted" | jq -r '.id')
  del_type=$(echo "$deleted" | jq -r '.type')
  del_amount=$(echo "$deleted" | jq -r '.amount')
  del_desc=$(echo "$deleted" | jq -r '.description')
  del_date=$(echo "$deleted" | jq -r '.date')

  jq -n \
    --arg status "ok" \
    --argjson id "$del_id" \
    --arg type "$del_type" \
    --argjson amount "$del_amount" \
    --arg description "$del_desc" \
    --arg date "$del_date" \
    '{status: $status, deleted: {id: $id, type: $type, amount: $amount, description: $description, date: $date}}'
}

cmd_update() {
  local id="" user_id="" amount="" category="" desc="" tx_date="" note="" tx_type=""
  local has_note=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --id)        id="$2"; shift 2 ;;
      --user-id)   user_id="$2"; shift 2 ;;
      --amount)    amount="$2"; shift 2 ;;
      --category)  category="$2"; shift 2 ;;
      --desc)      desc="$2"; shift 2 ;;
      --date)      tx_date="$2"; shift 2 ;;
      --note)      note="$2"; has_note=true; shift 2 ;;
      --type)      tx_type="$2"; shift 2 ;;
      *) jq -n --arg error "unknown option: $1" '{error: $error}'; exit 1 ;;
    esac
  done

  if [[ -z "$id" || -z "$user_id" ]]; then
    jq -n --arg error "required: --id, --user-id" '{error: $error}'
    exit 1
  fi

  validate_integer "$id" "id"

  if [[ -z "$amount" && -z "$category" && -z "$desc" && -z "$tx_date" && "$has_note" == "false" && -z "$tx_type" ]]; then
    jq -n --arg error "at least one field to update is required: --amount, --category, --desc, --date, --note, --type" '{error: $error}'
    exit 1
  fi

  local safe_uid
  safe_uid=$(escape_sql "$user_id")

  # Verify record exists and belongs to user
  local existing
  existing=$(psql_cmd "SELECT id FROM transactions WHERE id = $id AND discord_user_id = '$safe_uid'")
  if [[ -z "$existing" ]]; then
    jq -n --arg error "record not found or not owned by user" --argjson id "$id" '{error: $error, id: $id}'
    exit 1
  fi

  # Build SET clause dynamically
  local set_parts=()

  if [[ -n "$amount" ]]; then
    validate_integer "$amount" "amount"
    set_parts+=("amount = $amount")
  fi

  if [[ -n "$tx_type" ]]; then
    validate_type "$tx_type"
    set_parts+=("type = '$tx_type'")
  fi

  if [[ -n "$category" ]]; then
    local safe_cat cat_id
    safe_cat=$(escape_sql "$category")
    cat_id=$(psql_cmd "SELECT id FROM categories WHERE name = '$safe_cat'")
    if [[ -z "$cat_id" ]]; then
      jq -n --arg error "category not found: $category" --arg hint "use 'categories' command to list available categories" '{error: $error, hint: $hint}'
      exit 1
    fi
    set_parts+=("category_id = $cat_id")
  fi

  if [[ -n "$desc" ]]; then
    local safe_desc
    safe_desc=$(escape_sql "$desc")
    set_parts+=("description = '$safe_desc'")
  fi

  if [[ -n "$tx_date" ]]; then
    validate_date "$tx_date"
    set_parts+=("tx_date = '$tx_date'")
  fi

  if [[ "$has_note" == "true" ]]; then
    if [[ -n "$note" ]]; then
      local safe_note
      safe_note=$(escape_sql "$note")
      set_parts+=("note = '$safe_note'")
    else
      set_parts+=("note = NULL")
    fi
  fi

  local set_clause
  set_clause=$(IFS=', '; echo "${set_parts[*]}")

  local updated
  updated=$(psql_json "
    WITH upd AS (
      UPDATE transactions
      SET $set_clause
      WHERE id = $id AND discord_user_id = '$safe_uid'
      RETURNING id, type, amount, description, note, tx_date, category_id
    )
    SELECT json_build_object(
      'id', u.id, 'type', u.type, 'amount', u.amount,
      'description', u.description, 'note', u.note,
      'date', u.tx_date, 'category', c.name
    )
    FROM upd u
    JOIN categories c ON c.id = u.category_id
  ")

  if [[ -z "$updated" ]]; then
    jq -n --arg error "update failed" '{error: $error}'
    exit 1
  fi

  jq -n --arg status "ok" --argjson updated "$updated" '{status: $status, updated: $updated}'
}

## ── Recurring Expenses ──────────────────────────────────────────

cmd_recurring_add() {
  local name="" amount="" category="" user_id="" user_name="" frequency="monthly" note=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)      name="$2"; shift 2 ;;
      --amount)    amount="$2"; shift 2 ;;
      --category)  category="$2"; shift 2 ;;
      --user-id)   user_id="$2"; shift 2 ;;
      --user-name) user_name="$2"; shift 2 ;;
      --frequency) frequency="$2"; shift 2 ;;
      --note)      note="$2"; shift 2 ;;
      *) jq -n --arg error "unknown option: $1" '{error: $error}'; exit 1 ;;
    esac
  done

  if [[ -z "$name" || -z "$amount" || -z "$category" || -z "$user_id" || -z "$user_name" ]]; then
    jq -n --arg error "required: --name, --amount, --category, --user-id, --user-name" '{error: $error}'
    exit 1
  fi

  validate_integer "$amount" "amount"

  local safe_name safe_category safe_user_id safe_user_name safe_note
  safe_name=$(escape_sql "$name")
  safe_category=$(escape_sql "$category")
  safe_user_id=$(escape_sql "$user_id")
  safe_user_name=$(escape_sql "$user_name")
  safe_note=$(escape_sql "${note:-}")

  local cat_id
  cat_id=$(psql_cmd "SELECT id FROM categories WHERE name = '$safe_category'")
  if [[ -z "$cat_id" ]]; then
    jq -n --arg error "category not found: $category" --arg hint "use 'categories' command to list available categories" '{error: $error, hint: $hint}'
    exit 1
  fi

  local note_clause
  if [[ -n "$note" ]]; then
    note_clause="'$safe_note'"
  else
    note_clause="NULL"
  fi

  local safe_freq
  safe_freq=$(escape_sql "$frequency")

  local raw_result
  raw_result=$(psql_json "
    INSERT INTO recurring_expenses (name, amount, category_id, frequency, note, discord_user_id, discord_user_name)
    VALUES ('$safe_name', $amount, $cat_id, '$safe_freq', $note_clause, '$safe_user_id', '$safe_user_name')
    RETURNING json_build_object(
      'id', id, 'name', name, 'amount', amount,
      'category', (SELECT c.name FROM categories c WHERE c.id = category_id),
      'icon', (SELECT c.icon FROM categories c WHERE c.id = category_id),
      'frequency', frequency, 'note', note, 'is_active', is_active
    )
  ")

  local result
  result=$(echo "$raw_result" | head -n1)

  if [[ -z "$result" ]]; then
    jq -n --arg error "failed to add recurring expense" '{error: $error}'
    exit 1
  fi

  jq -n --arg status "ok" --argjson recurring "$result" '{status: $status, recurring: $recurring}'
}

cmd_recurring_list() {
  local user_id="" active_only=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --user-id)     user_id="$2"; shift 2 ;;
      --active-only) active_only=true; shift ;;
      *) jq -n --arg error "unknown option: $1" '{error: $error}'; exit 1 ;;
    esac
  done

  local where_clause="WHERE 1=1"

  if [[ "$active_only" == "true" ]]; then
    where_clause="$where_clause AND r.is_active = true"
  fi

  if [[ -n "$user_id" ]]; then
    local safe_uid
    safe_uid=$(escape_sql "$user_id")
    where_clause="$where_clause AND r.discord_user_id = '$safe_uid'"
  fi

  local rows
  rows=$(psql_json "
    SELECT COALESCE(json_agg(json_build_object(
      'id', r.id,
      'name', r.name,
      'amount', r.amount,
      'category', c.name,
      'icon', c.icon,
      'frequency', r.frequency,
      'note', r.note,
      'user_name', r.discord_user_name,
      'is_active', r.is_active
    ) ORDER BY r.is_active DESC, r.amount DESC), '[]'::json)
    FROM recurring_expenses r
    JOIN categories c ON c.id = r.category_id
    $where_clause
  ")

  if [[ -z "$rows" ]]; then
    echo "[]"
  else
    echo "$rows"
  fi
}

cmd_recurring_update() {
  local id="" user_id="" name="" amount="" category="" note="" frequency="" active=""
  local has_note=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --id)        id="$2"; shift 2 ;;
      --user-id)   user_id="$2"; shift 2 ;;
      --name)      name="$2"; shift 2 ;;
      --amount)    amount="$2"; shift 2 ;;
      --category)  category="$2"; shift 2 ;;
      --note)      note="$2"; has_note=true; shift 2 ;;
      --frequency) frequency="$2"; shift 2 ;;
      --active)    active="$2"; shift 2 ;;
      *) jq -n --arg error "unknown option: $1" '{error: $error}'; exit 1 ;;
    esac
  done

  if [[ -z "$id" || -z "$user_id" ]]; then
    jq -n --arg error "required: --id, --user-id" '{error: $error}'
    exit 1
  fi

  validate_integer "$id" "id"

  if [[ -z "$name" && -z "$amount" && -z "$category" && "$has_note" == "false" && -z "$frequency" && -z "$active" ]]; then
    jq -n --arg error "at least one field to update is required: --name, --amount, --category, --note, --frequency, --active" '{error: $error}'
    exit 1
  fi

  local safe_uid
  safe_uid=$(escape_sql "$user_id")

  local existing
  existing=$(psql_cmd "SELECT id FROM recurring_expenses WHERE id = $id AND discord_user_id = '$safe_uid'")
  if [[ -z "$existing" ]]; then
    jq -n --arg error "record not found or not owned by user" --argjson id "$id" '{error: $error, id: $id}'
    exit 1
  fi

  local set_parts=()

  if [[ -n "$name" ]]; then
    local safe_name
    safe_name=$(escape_sql "$name")
    set_parts+=("name = '$safe_name'")
  fi

  if [[ -n "$amount" ]]; then
    validate_integer "$amount" "amount"
    set_parts+=("amount = $amount")
  fi

  if [[ -n "$category" ]]; then
    local safe_cat cat_id
    safe_cat=$(escape_sql "$category")
    cat_id=$(psql_cmd "SELECT id FROM categories WHERE name = '$safe_cat'")
    if [[ -z "$cat_id" ]]; then
      jq -n --arg error "category not found: $category" --arg hint "use 'categories' command to list available categories" '{error: $error, hint: $hint}'
      exit 1
    fi
    set_parts+=("category_id = $cat_id")
  fi

  if [[ "$has_note" == "true" ]]; then
    if [[ -n "$note" ]]; then
      local safe_note
      safe_note=$(escape_sql "$note")
      set_parts+=("note = '$safe_note'")
    else
      set_parts+=("note = NULL")
    fi
  fi

  if [[ -n "$frequency" ]]; then
    local safe_freq
    safe_freq=$(escape_sql "$frequency")
    set_parts+=("frequency = '$safe_freq'")
  fi

  if [[ -n "$active" ]]; then
    if [[ "$active" != "true" && "$active" != "false" ]]; then
      jq -n --arg error "active must be 'true' or 'false', got: $active" '{error: $error}'
      exit 1
    fi
    set_parts+=("is_active = $active")
  fi

  local set_clause
  set_clause=$(IFS=', '; echo "${set_parts[*]}")

  local updated
  updated=$(psql_json "
    WITH upd AS (
      UPDATE recurring_expenses
      SET $set_clause
      WHERE id = $id AND discord_user_id = '$safe_uid'
      RETURNING id, name, amount, category_id, frequency, note, is_active
    )
    SELECT json_build_object(
      'id', u.id, 'name', u.name, 'amount', u.amount,
      'category', c.name, 'icon', c.icon,
      'frequency', u.frequency, 'note', u.note, 'is_active', u.is_active
    )
    FROM upd u
    JOIN categories c ON c.id = u.category_id
  ")

  if [[ -z "$updated" ]]; then
    jq -n --arg error "update failed" '{error: $error}'
    exit 1
  fi

  jq -n --arg status "ok" --argjson updated "$updated" '{status: $status, updated: $updated}'
}

cmd_recurring_delete() {
  local id="" user_id=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --id)      id="$2"; shift 2 ;;
      --user-id) user_id="$2"; shift 2 ;;
      *) jq -n --arg error "unknown option: $1" '{error: $error}'; exit 1 ;;
    esac
  done

  if [[ -z "$id" || -z "$user_id" ]]; then
    jq -n --arg error "required: --id, --user-id" '{error: $error}'
    exit 1
  fi

  validate_integer "$id" "id"

  local safe_uid
  safe_uid=$(escape_sql "$user_id")

  local deleted
  deleted=$(psql_json "
    WITH del AS (
      DELETE FROM recurring_expenses
      WHERE id = $id AND discord_user_id = '$safe_uid'
      RETURNING id, name, amount, category_id
    )
    SELECT json_build_object(
      'id', d.id, 'name', d.name, 'amount', d.amount,
      'category', c.name
    )
    FROM del d
    JOIN categories c ON c.id = d.category_id
  ")

  if [[ -z "$deleted" || "$deleted" == "" ]]; then
    jq -n --arg error "record not found or not owned by user" --argjson id "$id" '{error: $error, id: $id}'
    exit 1
  fi

  jq -n --arg status "ok" --argjson deleted "$deleted" '{status: $status, deleted: $deleted}'
}

ensure_database

case "${1:-}" in
  add)              shift; cmd_add "$@" ;;
  categories)       shift; cmd_categories "$@" ;;
  add-category)     shift; cmd_add_category "$@" ;;
  summary)          shift; cmd_summary "$@" ;;
  list)             shift; cmd_list "$@" ;;
  delete)           shift; cmd_delete "$@" ;;
  update)           shift; cmd_update "$@" ;;
  recurring-add)    shift; cmd_recurring_add "$@" ;;
  recurring-list)   shift; cmd_recurring_list "$@" ;;
  recurring-update) shift; cmd_recurring_update "$@" ;;
  recurring-delete) shift; cmd_recurring_delete "$@" ;;
  *)
    jq -n --arg error "unknown command: ${1:-}" --arg usage "expense.sh <add|categories|add-category|summary|list|delete|update|recurring-add|recurring-list|recurring-update|recurring-delete> [options]" '{error: $error, usage: $usage}'
    exit 1
    ;;
esac
