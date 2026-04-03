CREATE TABLE IF NOT EXISTS projects (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  client TEXT,
  billing_unit TEXT DEFAULT 'person-day',
  hours_per_day NUMERIC DEFAULT 8,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS entries (
  id SERIAL PRIMARY KEY,
  date DATE NOT NULL DEFAULT CURRENT_DATE,
  project_id TEXT REFERENCES projects(id),
  epic TEXT,
  task TEXT NOT NULL,
  subtask TEXT,
  actual_hours NUMERIC NOT NULL,
  internal_hours NUMERIC,
  client_days NUMERIC,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_entries_project_epic_date
  ON entries(project_id, epic, date);
