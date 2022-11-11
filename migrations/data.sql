-- 1 up
CREATE TABLE users (
  email VARCHAR UNIQUE PRIMARY KEY,
  dod_id INTEGER,
  is_admin BOOLEAN DEFAULT FALSE,
  password VARCHAR
);
-- 2 up
ALTER TABLE users
ADD COLUMN reset_password BOOLEAN DEFAULT FALSE;
-- 3 up
ALTER TABLE users
ADD COLUMN last_reset TIMESTAMP;
-- 4 up
ALTER TABLE users
ADD COLUMN last_login TIMESTAMP;
-- 5 up
ALTER TABLE users
ADD COLUMN first_name VARCHAR(255);
ALTER TABLE users
ADD COLUMN last_name VARCHAR(255);

-- generify to a more agnostic term
-- this is not a UNIQUE field... only thing unique still
-- is 'email' since its the primary key
ALTER TABLE users
  RENAME COLUMN dod_id TO user_id;