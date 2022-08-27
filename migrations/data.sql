-- 1 up
CREATE TABLE users (
  email VARCHAR UNIQUE PRIMARY KEY,
  dod_id INTEGER,
  is_admin BOOLEAN DEFAULT FALSE,
  password VARCHAR
);
-- 2 up
ALTER TABLE users ADD COLUMN reset_password BOOLEAN DEFAULT FALSE;
-- 3 up
ALTER TABLE users ADD COLUMN last_reset TIMESTAMP;
-- 4 up
ALTER TABLE users ADD COLUMN last_login TIMESTAMP;