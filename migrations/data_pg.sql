-- For postgres specifics
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
-- 6 up
CREATE TABLE http_logs (
  id bigserial,
  user_email VARCHAR(255),
  response_status INTEGER,
  request_path VARCHAR(255),
  request_query_string VARCHAR(255),
  request_time TIMESTAMP,
  request_method VARCHAR(10),
  request_host VARCHAR(255),
  request_user_agent VARCHAR(255),
  time_taken_ms DECIMAL
);
-- 7 up
ALTER TABLE users
ADD COLUMN mfa_secret VARCHAR;
ALTER TABLE users
ADD COLUMN is_mfa BOOLEAN DEFAULT FALSE;
-- 8 up
ALTER TABLE users
ADD COLUMN locked BOOLEAN DEFAULT FALSE;
ALTER TABLE users
ADD COLUMN bad_attempts INTEGER;
-- 9 up
-- convert user_id to text type... SQLite wont need it because of type affinity/flexibility
ALTER TABLE users
ALTER COLUMN user_id TYPE VARCHAR(255);