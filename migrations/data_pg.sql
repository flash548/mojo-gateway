-- For postgres specifics
-- 1 up
CREATE TABLE users (
  id UUID PRIMARY KEY,
  email VARCHAR UNIQUE,
  first_name VARCHAR(255),
  last_name VARCHAR(255),
  user_id VARCHAR(255),
  is_admin BOOLEAN DEFAULT FALSE,
  last_login TIMESTAMP,
  last_reset TIMESTAMP,
  reset_password BOOLEAN DEFAULT FALSE,
  mfa_secret VARCHAR(4096),
  is_mfa BOOLEAN DEFAULT FALSE,
  locked BOOLEAN DEFAULT FALSE,
  bad_attempts INTEGER,
  password VARCHAR(255)
);
-- 2 up
CREATE TABLE http_logs (
  id bigserial,
  user_id UUID,
  user_email VARCHAR(255),
  response_status INTEGER,
  request_path VARCHAR(255),
  request_query_string VARCHAR(255),
  request_time TIMESTAMP,
  request_method VARCHAR(10),
  request_host VARCHAR(255),
  request_user_agent VARCHAR(255),
  time_taken_ms DECIMAL,
  foreign key(user_email) references users(email)
);
