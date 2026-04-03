#!/bin/bash
set -euo pipefail

DB_NAME="${WORKLOG_DB_NAME:-worklog}"
DB_USER="${WORKLOG_DB_USER:-$(whoami)}"
DB_HOST="${WORKLOG_DB_HOST:-localhost}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCHEMA_PATH="$SCRIPT_DIR/../schema.sql"

# ---------------------------------------------------------------------------
# Utilities (aligned with timetrack.sh / expense.sh patterns)
# ---------------------------------------------------------------------------

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
  local result
  if ! result=$(psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -tAc "$1" 2>&1); then
    jq -n --arg error "database error" --arg detail "$result" '{error: $error, detail: $detail}' >&2
    exit 1
  fi
  trim "$(echo "$result" | head -n1)"
}

psql_json() {
  local result
  if ! result=$(psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" --no-align --tuples-only -c "$1" 2>&1); then
    jq -n --arg error "database error" --arg detail "$result" '{error: $error, detail: $detail}' >&2
    exit 1
  fi
  echo "$result" | grep -v '^INSERT \|^UPDATE \|^DELETE ' || true
}

ensure_database() {
  local db_exists
  db_exists=$(psql -h "$DB_HOST" -U "$DB_USER" -d postgres -tAc \
    "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" 2>/dev/null || true)
  if [[ "$db_exists" != "1" ]]; then
    psql -h "$DB_HOST" -U "$DB_USER" -d postgres -c "CREATE DATABASE \"$DB_NAME\";" 2>/dev/null || true
    if ! psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -f "$SCHEMA_PATH" >/dev/null 2>&1; then
      echo '{"error":"failed to initialize worklog database schema"}' >&2
      exit 1
    fi
    echo '{"status":"initialized","message":"worklog database created"}' >&2
  fi
}

escape_sql() {
  local val="$1"
  val="${val//\\/\\\\}"
  val="${val//\'/\'\'}"
  echo "$val"
}

# ---------------------------------------------------------------------------
# Validators
# ---------------------------------------------------------------------------

validate_integer() {
  local value="$1" field="$2"
  if ! [[ "$value" =~ ^[0-9]+$ ]] || [[ "$value" -eq 0 ]]; then
    jq -n --arg error "$field must be a positive integer, got: $value" '{error: $error}' >&2
    exit 1
  fi
}

validate_date() {
  local value="$1"
  if ! [[ "$value" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    jq -n --arg error "date must be YYYY-MM-DD, got: $value" '{error: $error}' >&2
    exit 1
  fi
}

validate_type() {
  local value="$1"
  case "$value" in
    task|note|todo) ;;
    *) die_json "type must be task, note, or todo, got: $value" ;;
  esac
}

validate_status() {
  local value="$1"
  case "$value" in
    open|in_progress|done|cancelled) ;;
    *) die_json "status must be open, in_progress, done, or cancelled, got: $value" ;;
  esac
}

validate_priority() {
  local value="$1"
  case "$value" in
    low|normal|high|urgent) ;;
    *) die_json "priority must be low, normal, high, or urgent, got: $value" ;;
  esac
}

# ---------------------------------------------------------------------------
# cmd_add — Add a work item
# ---------------------------------------------------------------------------

cmd_add() {
  local content="" type="note" project="" priority="normal" due_date="" tags=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --content)  content="$2"; shift 2 ;;
      --type)     type="$2"; shift 2 ;;
      --project)  project="$2"; shift 2 ;;
      --priority) priority="$2"; shift 2 ;;
      --due)      due_date="$2"; shift 2 ;;
      --tags)     tags="$2"; shift 2 ;;
      *) die_json "unknown option: $1" ;;
    esac
  done

  if [[ -z "$content" ]]; then
    die_json "required: --content"
  fi

  validate_type "$type"
  validate_priority "$priority"
  if [[ -n "$due_date" ]]; then
    validate_date "$due_date"
  fi

  local safe_content safe_project
  safe_content=$(escape_sql "$content")
  safe_project=$(escape_sql "$project")

  local project_val
  if [[ -n "$project" ]]; then
    project_val="'$safe_project'"
  else
    project_val="NULL"
  fi

  local due_val
  if [[ -n "$due_date" ]]; then
    due_val="'$due_date'"
  else
    due_val="NULL"
  fi

  local tags_val
  if [[ -n "$tags" ]]; then
    # Convert comma-separated to PostgreSQL array
    local safe_tags
    safe_tags=$(escape_sql "$tags")
    tags_val="ARRAY[$(echo "$safe_tags" | sed "s/,/','/g" | sed "s/^/'/" | sed "s/$/'/" )]"
  else
    tags_val="NULL"
  fi

  psql_json "
    INSERT INTO items (type, content, project, status, priority, due_date, tags)
    VALUES ('$type', '$safe_content', $project_val, 'open', '$priority', $due_val, $tags_val)
    RETURNING json_build_object(
      'status', 'ok',
      'id', id,
      'type', type,
      'content', content,
      'project', project,
      'priority', priority,
      'due_date', due_date,
      'created_at', created_at
    );
  "
}

# ---------------------------------------------------------------------------
# cmd_list — List work items
# ---------------------------------------------------------------------------

cmd_list() {
  local status="" type="" project="" days="7" limit="50"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --status)  status="$2"; shift 2 ;;
      --type)    type="$2"; shift 2 ;;
      --project) project="$2"; shift 2 ;;
      --days)    days="$2"; shift 2 ;;
      --limit)   limit="$2"; shift 2 ;;
      *) die_json "unknown option: $1" ;;
    esac
  done

  if [[ -n "$status" ]]; then validate_status "$status"; fi
  if [[ -n "$type" ]]; then validate_type "$type"; fi

  local filters="WHERE created_at >= NOW() - INTERVAL '$days days'"

  if [[ -n "$status" ]]; then
    local safe_status
    safe_status=$(escape_sql "$status")
    filters="$filters AND status = '$safe_status'"
  fi

  if [[ -n "$type" ]]; then
    local safe_type
    safe_type=$(escape_sql "$type")
    filters="$filters AND type = '$safe_type'"
  fi

  if [[ -n "$project" ]]; then
    local safe_project
    safe_project=$(escape_sql "$project")
    filters="$filters AND project = '$safe_project'"
  fi

  psql_json "
    SELECT json_build_object(
      'status', 'ok',
      'items', COALESCE((
        SELECT json_agg(json_build_object(
          'id', id,
          'type', type,
          'content', content,
          'project', project,
          'status', status,
          'priority', priority,
          'due_date', due_date,
          'tags', tags,
          'created_at', created_at,
          'updated_at', updated_at,
          'completed_at', completed_at
        ) ORDER BY
          CASE priority
            WHEN 'urgent' THEN 1
            WHEN 'high' THEN 2
            WHEN 'normal' THEN 3
            WHEN 'low' THEN 4
          END,
          created_at DESC
        )
        FROM (
          SELECT * FROM items
          $filters
          ORDER BY created_at DESC
          LIMIT $limit
        ) sub
      ), '[]'::json)
    );
  "
}

# ---------------------------------------------------------------------------
# cmd_done — Mark item as done
# ---------------------------------------------------------------------------

cmd_done() {
  local id=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --id) id="$2"; shift 2 ;;
      *) die_json "unknown option: $1" ;;
    esac
  done

  if [[ -z "$id" ]]; then
    die_json "required: --id"
  fi
  validate_integer "$id" "id"

  local result
  result=$(psql_json "
    UPDATE items
    SET status = 'done', completed_at = NOW(), updated_at = NOW()
    WHERE id = $id
    RETURNING json_build_object(
      'status', 'ok',
      'item', json_build_object(
        'id', id,
        'type', type,
        'content', content,
        'completed_at', completed_at
      )
    );
  ")

  if [[ -z "$result" || "$result" == "" ]]; then
    jq -n --arg error "item not found: $id" '{error: $error}'
    exit 1
  fi

  echo "$result"
}

# ---------------------------------------------------------------------------
# cmd_update — Update an existing item
# ---------------------------------------------------------------------------

cmd_update() {
  local id="" content="" status="" priority="" project="" due_date="" tags=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --id)       id="$2"; shift 2 ;;
      --content)  content="$2"; shift 2 ;;
      --status)   status="$2"; shift 2 ;;
      --priority) priority="$2"; shift 2 ;;
      --project)  project="$2"; shift 2 ;;
      --due)      due_date="$2"; shift 2 ;;
      --tags)     tags="$2"; shift 2 ;;
      *) die_json "unknown option: $1" ;;
    esac
  done

  if [[ -z "$id" ]]; then
    die_json "required: --id"
  fi
  validate_integer "$id" "id"

  local set_parts=("updated_at = NOW()")

  if [[ -n "$content" ]]; then
    set_parts+=("content = '$(escape_sql "$content")'")
  fi
  if [[ -n "$status" ]]; then
    validate_status "$status"
    set_parts+=("status = '$status'")
    if [[ "$status" == "done" ]]; then
      set_parts+=("completed_at = NOW()")
    fi
  fi
  if [[ -n "$priority" ]]; then
    validate_priority "$priority"
    set_parts+=("priority = '$priority'")
  fi
  if [[ -n "$project" ]]; then
    set_parts+=("project = '$(escape_sql "$project")'")
  fi
  if [[ -n "$due_date" ]]; then
    validate_date "$due_date"
    set_parts+=("due_date = '$due_date'")
  fi
  if [[ -n "$tags" ]]; then
    local safe_tags
    safe_tags=$(escape_sql "$tags")
    set_parts+=("tags = ARRAY[$(echo "$safe_tags" | sed "s/,/','/g" | sed "s/^/'/" | sed "s/$/'/" )]")
  fi

  if [[ ${#set_parts[@]} -eq 1 ]]; then
    die_json "at least one field to update is required"
  fi

  local set_clause
  set_clause=$(IFS=', '; echo "${set_parts[*]}")

  local result
  result=$(psql_json "
    UPDATE items SET $set_clause
    WHERE id = $id
    RETURNING json_build_object(
      'status', 'ok',
      'item', json_build_object(
        'id', id,
        'type', type,
        'content', content,
        'project', project,
        'status', status,
        'priority', priority,
        'due_date', due_date,
        'tags', tags,
        'updated_at', updated_at
      )
    );
  ")

  if [[ -z "$result" || "$result" == "" ]]; then
    jq -n --arg error "item not found: $id" '{error: $error}'
    exit 1
  fi

  echo "$result"
}

# ---------------------------------------------------------------------------
# cmd_delete — Delete an item
# ---------------------------------------------------------------------------

cmd_delete() {
  local id=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --id) id="$2"; shift 2 ;;
      *) die_json "unknown option: $1" ;;
    esac
  done

  if [[ -z "$id" ]]; then
    die_json "required: --id"
  fi
  validate_integer "$id" "id"

  local result
  result=$(psql_json "
    DELETE FROM items
    WHERE id = $id
    RETURNING json_build_object(
      'status', 'ok',
      'deleted', json_build_object(
        'id', id,
        'type', type,
        'content', content
      )
    );
  ")

  if [[ -z "$result" || "$result" == "" ]]; then
    jq -n --arg error "item not found: $id" '{error: $error}'
    exit 1
  fi

  echo "$result"
}

# ---------------------------------------------------------------------------
# cmd_summary — Status counts and recent activity
# ---------------------------------------------------------------------------

cmd_summary() {
  local days="7"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --days) days="$2"; shift 2 ;;
      *) die_json "unknown option: $1" ;;
    esac
  done

  psql_json "
    SELECT json_build_object(
      'status', 'ok',
      'by_status', (
        SELECT json_object_agg(status, cnt)
        FROM (
          SELECT status, COUNT(*) AS cnt
          FROM items
          GROUP BY status
        ) sub
      ),
      'by_type', (
        SELECT json_object_agg(type, cnt)
        FROM (
          SELECT type, COUNT(*) AS cnt
          FROM items
          WHERE status NOT IN ('done', 'cancelled')
          GROUP BY type
        ) sub
      ),
      'overdue', (
        SELECT COUNT(*)
        FROM items
        WHERE status NOT IN ('done', 'cancelled')
          AND due_date < CURRENT_DATE
      ),
      'recent_completed', (
        SELECT COUNT(*)
        FROM items
        WHERE status = 'done'
          AND completed_at >= NOW() - INTERVAL '$days days'
      ),
      'recent_created', (
        SELECT COUNT(*)
        FROM items
        WHERE created_at >= NOW() - INTERVAL '$days days'
      )
    );
  "
}

# ---------------------------------------------------------------------------
# Main dispatcher
# ---------------------------------------------------------------------------

ensure_database

case "${1:-}" in
  add)     shift; cmd_add "$@" ;;
  list)    shift; cmd_list "$@" ;;
  done)    shift; cmd_done "$@" ;;
  update)  shift; cmd_update "$@" ;;
  delete)  shift; cmd_delete "$@" ;;
  summary) shift; cmd_summary "$@" ;;
  *)
    jq -n --arg error "unknown command: ${1:-}" \
      --arg usage "worklog.sh <add|list|done|update|delete|summary> [options]" \
      '{error: $error, usage: $usage}'
    exit 1 ;;
esac
