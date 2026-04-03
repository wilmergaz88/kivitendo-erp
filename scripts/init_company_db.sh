#!/bin/bash
DB_NAME="$1"
[ -z "$DB_NAME" ] && { echo "Usage: $0 <database_name>"; exit 1; }

echo "Initializing Kiviex company database: $DB_NAME"

docker compose exec db psql -U postgres -d "$DB_NAME" << 'SCHEMA_INIT'
CREATE TABLE IF NOT EXISTS chart (
  accno varchar(10) PRIMARY KEY,
  description text
);
CREATE TABLE IF NOT EXISTS user_preferences (
  id SERIAL PRIMARY KEY,
  login varchar(50),
  name varchar(100),
  value text
);
CREATE TABLE IF NOT EXISTS defaults (
  id SERIAL PRIMARY KEY,
  key varchar(100) UNIQUE,
  value text
);
CREATE TABLE IF NOT EXISTS customer (id SERIAL PRIMARY KEY, name varchar(75));
CREATE TABLE IF NOT EXISTS vendor (id SERIAL PRIMARY KEY, name varchar(75));
CREATE TABLE IF NOT EXISTS parts (id SERIAL PRIMARY KEY, partnumber varchar(50));
SCHEMA_INIT

echo "✓ Database $DB_NAME initialized successfully!"
