#!/bin/bash
set -euo pipefail

DB_NAME="${TIMETRACK_DB_NAME:-timetrack}"
DB_USER="${TIMETRACK_DB_USER:-$(whoami)}"
DB_HOST="${TIMETRACK_DB_HOST:-localhost}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCHEMA_PATH="$SCRIPT_DIR/../schema.sql"

# ---------------------------------------------------------------------------
# Utilities (aligned with expense.sh patterns)
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
  # Filter out command tags (INSERT 0 1, UPDATE N, DELETE N) from RETURNING output
  echo "$result" | grep -v '^INSERT \|^UPDATE \|^DELETE ' || true
}

ensure_database() {
  local db_exists
  db_exists=$(psql -h "$DB_HOST" -U "$DB_USER" -d postgres -tAc \
    "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" 2>/dev/null || true)
  if [[ "$db_exists" != "1" ]]; then
    psql -h "$DB_HOST" -U "$DB_USER" -d postgres -c "CREATE DATABASE \"$DB_NAME\";" 2>/dev/null || true
    if ! psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -f "$SCHEMA_PATH" >/dev/null 2>&1; then
      echo '{"error":"failed to initialize timetrack database schema"}' >&2
      exit 1
    fi
    echo '{"status":"initialized","message":"timetrack database created"}' >&2
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

validate_positive_numeric() {
  local value="$1" field="$2"
  if ! [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    jq -n --arg error "$field must be a positive number, got: $value" '{error: $error}' >&2
    exit 1
  fi
  # Reject zero
  if [[ "$value" =~ ^0+(\.0+)?$ ]]; then
    jq -n --arg error "$field must be greater than 0, got: $value" '{error: $error}' >&2
    exit 1
  fi
}

validate_non_negative_numeric() {
  local value="$1" field="$2"
  if ! [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    jq -n --arg error "$field must be a non-negative number, got: $value" '{error: $error}' >&2
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

validate_project_exists() {
  local project_id="$1"
  local safe_id
  safe_id=$(escape_sql "$project_id")
  local exists
  exists=$(psql_cmd "SELECT 1 FROM projects WHERE id = '$safe_id'")
  if [[ "$exists" != "1" ]]; then
    jq -n --arg error "project not found: $project_id" '{error: $error}' >&2
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# cmd_log — Record a time entry
# ---------------------------------------------------------------------------

cmd_log() {
  local project="" epic="" task="" subtask="" hours="" internal_hours="" entry_date="" notes=""
  local has_internal_hours=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project)        project="$2"; shift 2 ;;
      --epic)           epic="$2"; shift 2 ;;
      --task)           task="$2"; shift 2 ;;
      --subtask)        subtask="$2"; shift 2 ;;
      --hours)          hours="$2"; shift 2 ;;
      --internal-hours) internal_hours="$2"; has_internal_hours=true; shift 2 ;;
      --date)           entry_date="$2"; shift 2 ;;
      --notes)          notes="$2"; shift 2 ;;
      *) die_json "unknown option: $1" ;;
    esac
  done

  if [[ -z "$project" || -z "$task" || -z "$hours" ]]; then
    die_json "required: --project, --task, --hours"
  fi

  validate_positive_numeric "$hours" "hours"
  if [[ "$has_internal_hours" == true ]]; then
    validate_non_negative_numeric "$internal_hours" "internal-hours"
  fi
  validate_project_exists "$project"
  if [[ -n "$entry_date" ]]; then
    validate_date "$entry_date"
  fi

  local safe_project safe_epic safe_task safe_subtask safe_notes
  safe_project=$(escape_sql "$project")
  safe_epic=$(escape_sql "$epic")
  safe_task=$(escape_sql "$task")
  safe_subtask=$(escape_sql "$subtask")
  safe_notes=$(escape_sql "$notes")

  local date_val
  if [[ -n "$entry_date" ]]; then
    date_val="'$entry_date'"
  else
    date_val="CURRENT_DATE"
  fi

  local epic_val
  if [[ -n "$epic" ]]; then
    epic_val="'$safe_epic'"
  else
    epic_val="NULL"
  fi

  local subtask_val
  if [[ -n "$subtask" ]]; then
    subtask_val="'$safe_subtask'"
  else
    subtask_val="NULL"
  fi

  local notes_val
  if [[ -n "$notes" ]]; then
    notes_val="'$safe_notes'"
  else
    notes_val="NULL"
  fi

  local internal_hours_val
  if [[ "$has_internal_hours" == true ]]; then
    internal_hours_val="$internal_hours"
  else
    internal_hours_val="NULL"
  fi

  psql_json "
    INSERT INTO entries (date, project_id, epic, task, subtask, actual_hours, internal_hours, notes)
    VALUES ($date_val, '$safe_project', $epic_val, '$safe_task', $subtask_val, $hours, $internal_hours_val, $notes_val)
    RETURNING json_build_object(
      'status', 'ok',
      'id', id,
      'date', date,
      'project_id', project_id,
      'epic', epic,
      'task', task,
      'subtask', subtask,
      'actual_hours', actual_hours,
      'internal_hours', internal_hours
    );
  "
}

# ---------------------------------------------------------------------------
# cmd_recap — Show recent work & status
# ---------------------------------------------------------------------------

cmd_recap() {
  local project="" days="7" epic=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project) project="$2"; shift 2 ;;
      --days)    days="$2"; shift 2 ;;
      --epic)    epic="$2"; shift 2 ;;
      *) die_json "unknown option: $1" ;;
    esac
  done

  if [[ -z "$project" ]]; then
    die_json "required: --project"
  fi

  validate_project_exists "$project"
  validate_integer "$days" "days"

  local safe_project safe_epic
  safe_project=$(escape_sql "$project")
  safe_epic=$(escape_sql "$epic")

  local epic_filter=""
  if [[ -n "$epic" ]]; then
    epic_filter="AND epic = '$safe_epic'"
  fi

  psql_json "
    WITH filtered AS (
      SELECT id, date, epic, task, subtask, actual_hours, internal_hours, client_days, notes
      FROM entries
      WHERE project_id = '$safe_project'
        AND date >= CURRENT_DATE - INTERVAL '$days days'
        $epic_filter
      ORDER BY date DESC, created_at DESC
    ),
    by_epic AS (
      SELECT epic,
        SUM(actual_hours) AS total_actual_hours,
        COUNT(*) AS entry_count
      FROM filtered
      GROUP BY epic ORDER BY epic
    ),
    summary AS (
      SELECT
        COALESCE(SUM(actual_hours), 0) AS total_actual_hours,
        COUNT(*) FILTER (WHERE internal_hours IS NULL OR client_days IS NULL) AS missing_ref_count
      FROM filtered
    )
    SELECT json_build_object(
      'status', 'ok',
      'project', '$safe_project',
      'days', $days,
      'total_actual_hours', s.total_actual_hours,
      'missing_ref_count', s.missing_ref_count,
      'by_epic', COALESCE((SELECT json_agg(json_build_object('epic', epic, 'total_actual_hours', total_actual_hours, 'entry_count', entry_count)) FROM by_epic), '[]'::json),
      'entries', COALESCE((SELECT json_agg(json_build_object('id', id, 'date', date, 'epic', epic, 'task', task, 'subtask', subtask, 'actual_hours', actual_hours, 'internal_hours', internal_hours, 'client_days', client_days, 'notes', notes)) FROM filtered), '[]'::json)
    )
    FROM summary s;
  "
}

# ---------------------------------------------------------------------------
# cmd_ref — Batch update internal/client numbers
# ---------------------------------------------------------------------------

cmd_ref() {
  local project="" epic="" start_date="" end_date="" internal_hours="" client_days=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project)        project="$2"; shift 2 ;;
      --epic)           epic="$2"; shift 2 ;;
      --start-date)     start_date="$2"; shift 2 ;;
      --end-date)       end_date="$2"; shift 2 ;;
      --internal-hours) internal_hours="$2"; shift 2 ;;
      --client-days)    client_days="$2"; shift 2 ;;
      *) die_json "unknown option: $1" ;;
    esac
  done

  if [[ -z "$project" || -z "$epic" ]]; then
    die_json "required: --project, --epic"
  fi
  if [[ -z "$internal_hours" && -z "$client_days" ]]; then
    die_json "required: at least one of --internal-hours or --client-days"
  fi

  validate_project_exists "$project"
  if [[ -n "$internal_hours" ]]; then
    validate_positive_numeric "$internal_hours" "internal-hours"
  fi
  if [[ -n "$client_days" ]]; then
    validate_positive_numeric "$client_days" "client-days"
  fi
  if [[ -n "$start_date" ]]; then validate_date "$start_date"; fi
  if [[ -n "$end_date" ]]; then validate_date "$end_date"; fi

  local safe_project safe_epic
  safe_project=$(escape_sql "$project")
  safe_epic=$(escape_sql "$epic")

  # Distribute internal_hours if provided
  if [[ -n "$internal_hours" ]]; then
    local date_filter=""
    if [[ -n "$start_date" ]]; then
      date_filter="$date_filter AND date >= '$start_date'"
    fi
    if [[ -n "$end_date" ]]; then
      date_filter="$date_filter AND date <= '$end_date'"
    fi

    # Check scope count first
    local scope_count_ih
    scope_count_ih=$(psql_cmd "
      SELECT COUNT(*) FROM entries
      WHERE project_id = '$safe_project'
        AND epic = '$safe_epic'
        AND internal_hours IS NULL
        $date_filter;
    ")

    if [[ "$scope_count_ih" -eq 0 ]]; then
      die_json "no entries found to distribute internal_hours (project=$project, epic=$epic)"
    fi

    psql_cmd "
      WITH scope AS (
        SELECT id, actual_hours,
          actual_hours / SUM(actual_hours) OVER () AS ratio,
          ROW_NUMBER() OVER (ORDER BY date, id) AS rn,
          COUNT(*) OVER () AS total_count
        FROM entries
        WHERE project_id = '$safe_project'
          AND epic = '$safe_epic'
          AND internal_hours IS NULL
          $date_filter
      ),
      distributed AS (
        SELECT id,
          CASE
            WHEN rn = total_count THEN
              $internal_hours - COALESCE(SUM(ROUND(ratio * $internal_hours, 2)) OVER (ORDER BY rn ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0)
            ELSE
              ROUND(ratio * $internal_hours, 2)
          END AS alloc
        FROM scope
      )
      UPDATE entries e
      SET internal_hours = d.alloc
      FROM distributed d
      WHERE e.id = d.id;
    " >/dev/null
  fi

  # Distribute client_days if provided
  if [[ -n "$client_days" ]]; then
    local date_filter_cd=""
    if [[ -n "$start_date" ]]; then
      date_filter_cd="$date_filter_cd AND date >= '$start_date'"
    fi
    if [[ -n "$end_date" ]]; then
      date_filter_cd="$date_filter_cd AND date <= '$end_date'"
    fi

    # Check scope count first
    local scope_count_cd
    scope_count_cd=$(psql_cmd "
      SELECT COUNT(*) FROM entries
      WHERE project_id = '$safe_project'
        AND epic = '$safe_epic'
        AND client_days IS NULL
        $date_filter_cd;
    ")

    if [[ "$scope_count_cd" -eq 0 ]]; then
      die_json "no entries found to distribute client_days (project=$project, epic=$epic)"
    fi

    psql_cmd "
      WITH scope AS (
        SELECT id, actual_hours,
          actual_hours / SUM(actual_hours) OVER () AS ratio,
          ROW_NUMBER() OVER (ORDER BY date, id) AS rn,
          COUNT(*) OVER () AS total_count
        FROM entries
        WHERE project_id = '$safe_project'
          AND epic = '$safe_epic'
          AND client_days IS NULL
          $date_filter_cd
      ),
      distributed AS (
        SELECT id,
          CASE
            WHEN rn = total_count THEN
              $client_days - COALESCE(SUM(ROUND(ratio * $client_days, 2)) OVER (ORDER BY rn ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0)
            ELSE
              ROUND(ratio * $client_days, 2)
          END AS alloc
        FROM scope
      )
      UPDATE entries e
      SET client_days = d.alloc
      FROM distributed d
      WHERE e.id = d.id;
    " >/dev/null
  fi

  jq -n \
    --arg status "ok" \
    --arg project "$project" \
    --arg epic "$epic" \
    --arg internal_hours "${internal_hours:-null}" \
    --arg client_days "${client_days:-null}" \
    '{
      status: $status,
      scope: {project: $project, epic: $epic},
      distributed: {
        internal_hours: (if $internal_hours == "null" then null else ($internal_hours | tonumber) end),
        client_days: (if $client_days == "null" then null else ($client_days | tonumber) end)
      }
    }'
}

# ---------------------------------------------------------------------------
# cmd_report — Ratio analysis & classification
# ---------------------------------------------------------------------------

cmd_report() {
  local project="" start_date="" end_date=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project)    project="$2"; shift 2 ;;
      --start-date) start_date="$2"; shift 2 ;;
      --end-date)   end_date="$2"; shift 2 ;;
      *) die_json "unknown option: $1" ;;
    esac
  done

  if [[ -z "$project" ]]; then
    die_json "required: --project"
  fi

  validate_project_exists "$project"
  if [[ -n "$start_date" ]]; then validate_date "$start_date"; fi
  if [[ -n "$end_date" ]]; then validate_date "$end_date"; fi

  local safe_project
  safe_project=$(escape_sql "$project")

  local date_filter=""
  if [[ -n "$start_date" ]]; then
    date_filter="$date_filter AND date >= '$start_date'"
  fi
  if [[ -n "$end_date" ]]; then
    date_filter="$date_filter AND date <= '$end_date'"
  fi

  local raw_json
  raw_json=$(psql_json "
    SELECT json_agg(row_data) FROM (
      SELECT json_build_object(
        'epic', epic,
        'actual_hours', SUM(actual_hours),
        'internal_hours', SUM(internal_hours),
        'client_days', SUM(client_days),
        'credit_ratio', ROUND(SUM(internal_hours) / NULLIF(SUM(actual_hours), 0), 2),
        'revenue_ratio', ROUND(SUM(client_days) / NULLIF(SUM(actual_hours), 0), 2),
        'pricing_leverage', ROUND(SUM(client_days) / NULLIF(SUM(internal_hours), 0), 2),
        'has_incomplete_data', bool_or(internal_hours IS NULL OR client_days IS NULL)
      ) AS row_data
      FROM entries
      WHERE project_id = '$safe_project'
        $date_filter
      GROUP BY epic ORDER BY epic
    ) sub;
  ")

  # Classify each epic using jq based on thresholds from classification.md
  echo "$raw_json" | jq --arg project "$project" '
    if . == null then
      {status: "ok", project: $project, epics: []}
    else
      {
        status: "ok",
        project: $project,
        epics: [.[] | . + {
          classification: (
            if .has_incomplete_data == true then "資料不足"
            elif .credit_ratio == null or .revenue_ratio == null then "資料不足"
            elif .credit_ratio > 2.0 and .revenue_ratio > 0.3 then "黃金工項"
            elif .credit_ratio > 2.0 and .revenue_ratio < 0.15 then "政治型"
            elif .credit_ratio < 1.2 and .revenue_ratio < 0.15 then "苦工型"
            elif .credit_ratio >= 1.2 and .credit_ratio <= 2.0 and .revenue_ratio > 0.3 then "商業槓桿"
            else "未分類"
            end
          )
        }]
      }
    end
  '
}

# ---------------------------------------------------------------------------
# cmd_project — Manage projects
# ---------------------------------------------------------------------------

cmd_project() {
  local subcmd="${1:-}"
  shift 2>/dev/null || true

  case "$subcmd" in
    add)  cmd_project_add "$@" ;;
    list) cmd_project_list ;;
    *)    die_json "usage: timetrack.sh project <add|list>" ;;
  esac
}

cmd_project_add() {
  local id="" name="" client="" hours_per_day=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --id)            id="$2"; shift 2 ;;
      --name)          name="$2"; shift 2 ;;
      --client)        client="$2"; shift 2 ;;
      --hours-per-day) hours_per_day="$2"; shift 2 ;;
      *) die_json "unknown option: $1" ;;
    esac
  done

  if [[ -z "$id" || -z "$name" ]]; then
    die_json "required: --id, --name"
  fi

  if [[ -n "$hours_per_day" ]]; then
    validate_positive_numeric "$hours_per_day" "hours-per-day"
  fi

  local safe_id safe_name safe_client
  safe_id=$(escape_sql "$id")
  safe_name=$(escape_sql "$name")
  safe_client=$(escape_sql "$client")

  local hpd_val
  if [[ -n "$hours_per_day" ]]; then
    hpd_val="$hours_per_day"
  else
    hpd_val="8"
  fi

  local client_val
  if [[ -n "$client" ]]; then
    client_val="'$safe_client'"
  else
    client_val="NULL"
  fi

  psql_json "
    INSERT INTO projects (id, name, client, hours_per_day)
    VALUES ('$safe_id', '$safe_name', $client_val, $hpd_val)
    ON CONFLICT (id) DO UPDATE
      SET name = EXCLUDED.name,
          client = EXCLUDED.client,
          hours_per_day = EXCLUDED.hours_per_day
    RETURNING json_build_object(
      'status', 'ok',
      'id', id,
      'name', name,
      'client', client,
      'hours_per_day', hours_per_day
    );
  "
}

cmd_project_list() {
  psql_json "
    SELECT json_build_object(
      'status', 'ok',
      'projects', COALESCE((
        SELECT json_agg(json_build_object(
          'id', p.id,
          'name', p.name,
          'client', p.client,
          'hours_per_day', p.hours_per_day,
          'entries', COALESCE(e.cnt, 0),
          'total_actual_hours', COALESCE(e.total_h, 0)
        ) ORDER BY p.id)
        FROM projects p
        LEFT JOIN (
          SELECT project_id, COUNT(*) AS cnt, SUM(actual_hours) AS total_h
          FROM entries GROUP BY project_id
        ) e ON e.project_id = p.id
      ), '[]'::json)
    );
  "
}

# ---------------------------------------------------------------------------
# cmd_edit — Edit an existing entry
# ---------------------------------------------------------------------------

cmd_edit() {
  local id="" project="" epic="" task="" subtask="" hours="" internal_hours="" client_days="" entry_date="" notes=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --id)             id="$2"; shift 2 ;;
      --project)        project="$2"; shift 2 ;;
      --epic)           epic="$2"; shift 2 ;;
      --task)           task="$2"; shift 2 ;;
      --subtask)        subtask="$2"; shift 2 ;;
      --hours)          hours="$2"; shift 2 ;;
      --internal-hours) internal_hours="$2"; shift 2 ;;
      --client-days)    client_days="$2"; shift 2 ;;
      --date)           entry_date="$2"; shift 2 ;;
      --notes)          notes="$2"; shift 2 ;;
      *) die_json "unknown option: $1" ;;
    esac
  done

  if [[ -z "$id" ]]; then
    die_json "required: --id"
  fi
  validate_integer "$id" "id"

  local set_parts=()

  if [[ -n "$project" ]]; then
    validate_project_exists "$project"
    set_parts+=("project_id = '$(escape_sql "$project")'")
  fi
  if [[ -n "$epic" ]]; then
    set_parts+=("epic = '$(escape_sql "$epic")'")
  fi
  if [[ -n "$task" ]]; then
    set_parts+=("task = '$(escape_sql "$task")'")
  fi
  if [[ -n "$subtask" ]]; then
    set_parts+=("subtask = '$(escape_sql "$subtask")'")
  fi
  if [[ -n "$hours" ]]; then
    validate_positive_numeric "$hours" "hours"
    set_parts+=("actual_hours = $hours")
  fi
  if [[ -n "$internal_hours" ]]; then
    validate_positive_numeric "$internal_hours" "internal-hours"
    set_parts+=("internal_hours = $internal_hours")
  fi
  if [[ -n "$client_days" ]]; then
    validate_positive_numeric "$client_days" "client-days"
    set_parts+=("client_days = $client_days")
  fi
  if [[ -n "$entry_date" ]]; then
    validate_date "$entry_date"
    set_parts+=("date = '$entry_date'")
  fi
  if [[ -n "$notes" ]]; then
    set_parts+=("notes = '$(escape_sql "$notes")'")
  fi

  if [[ ${#set_parts[@]} -eq 0 ]]; then
    die_json "at least one field to update is required"
  fi

  local set_clause
  set_clause=$(IFS=', '; echo "${set_parts[*]}")

  local result
  result=$(psql_json "
    UPDATE entries SET $set_clause
    WHERE id = $id
    RETURNING json_build_object(
      'status', 'ok',
      'updated', json_build_object(
        'id', id,
        'date', date,
        'project_id', project_id,
        'epic', epic,
        'task', task,
        'subtask', subtask,
        'actual_hours', actual_hours,
        'internal_hours', internal_hours,
        'client_days', client_days,
        'notes', notes
      )
    );
  ")

  if [[ -z "$result" || "$result" == "" ]]; then
    jq -n --arg error "entry not found: $id" '{error: $error}'
    exit 1
  fi

  echo "$result"
}

# ---------------------------------------------------------------------------
# cmd_delete — Delete an entry
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
    DELETE FROM entries
    WHERE id = $id
    RETURNING json_build_object(
      'status', 'ok',
      'deleted', json_build_object(
        'id', id,
        'date', date,
        'project_id', project_id,
        'epic', epic,
        'task', task,
        'actual_hours', actual_hours
      )
    );
  ")

  if [[ -z "$result" || "$result" == "" ]]; then
    jq -n --arg error "entry not found: $id" '{error: $error}'
    exit 1
  fi

  echo "$result"
}

# ---------------------------------------------------------------------------
# Main dispatcher
# ---------------------------------------------------------------------------

ensure_database

case "${1:-}" in
  log)     shift; cmd_log "$@" ;;
  recap)   shift; cmd_recap "$@" ;;
  ref)     shift; cmd_ref "$@" ;;
  report)  shift; cmd_report "$@" ;;
  project) shift; cmd_project "$@" ;;
  edit)    shift; cmd_edit "$@" ;;
  delete)  shift; cmd_delete "$@" ;;
  *)
    jq -n --arg error "unknown command: ${1:-}" \
      --arg usage "timetrack.sh <log|recap|ref|report|project|edit|delete> [options]" \
      '{error: $error, usage: $usage}'
    exit 1 ;;
esac
