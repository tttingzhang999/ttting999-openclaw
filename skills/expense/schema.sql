CREATE TYPE tx_type AS ENUM ('expense', 'income');
CREATE TYPE category_scope AS ENUM ('expense', 'income', 'both');

CREATE TABLE categories (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    icon TEXT,
    applicable_type category_scope NOT NULL DEFAULT 'both',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO categories (name, icon, applicable_type) VALUES
    ('餐飲', '🍽️', 'expense'),
    ('交通', '🚗', 'expense'),
    ('日用品', '🧴', 'expense'),
    ('娛樂', '🎮', 'expense'),
    ('醫療', '🏥', 'expense'),
    ('教育', '📚', 'both'),
    ('居住', '🏠', 'expense'),
    ('服飾', '👕', 'expense'),
    ('薪資', '💰', 'income'),
    ('投資', '📈', 'both'),
    ('其他', '📦', 'both');

CREATE TABLE transactions (
    id SERIAL PRIMARY KEY,
    type tx_type NOT NULL DEFAULT 'expense',
    amount INTEGER NOT NULL CHECK (amount > 0),
    category_id INTEGER NOT NULL REFERENCES categories(id),
    description TEXT NOT NULL,
    note TEXT,
    discord_user_id TEXT NOT NULL,
    discord_user_name TEXT NOT NULL,
    tx_date DATE NOT NULL DEFAULT CURRENT_DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_tx_date ON transactions(tx_date);
CREATE INDEX idx_tx_category ON transactions(category_id);
CREATE INDEX idx_tx_user ON transactions(discord_user_id);
CREATE INDEX idx_tx_type ON transactions(type);

CREATE TABLE recurring_expenses (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    amount INTEGER NOT NULL CHECK (amount > 0),
    category_id INTEGER NOT NULL REFERENCES categories(id),
    frequency TEXT NOT NULL DEFAULT 'monthly',
    note TEXT,
    discord_user_id TEXT NOT NULL,
    discord_user_name TEXT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_recurring_user ON recurring_expenses(discord_user_id);
CREATE INDEX idx_recurring_active ON recurring_expenses(is_active);
