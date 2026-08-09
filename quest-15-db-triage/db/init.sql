-- レポート基盤の初期状態。ここが「正常な状態」。
\set ON_ERROR_STOP on

-- 保守用のマスターユーザー。運用担当はこれで入る
CREATE ROLE dbadmin LOGIN SUPERUSER PASSWORD 'dbadmin_pw';

CREATE ROLE reportapi LOGIN PASSWORD 'reportapi_pw';
CREATE ROLE batchuser LOGIN PASSWORD 'batchuser_pw';

CREATE DATABASE reportdb OWNER postgres;

\connect reportdb

CREATE SCHEMA app;

CREATE TABLE app.reports (
  id         serial PRIMARY KEY,
  region     text NOT NULL,
  amount     int  NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE app.counters (
  name text PRIMARY KEY,
  n    bigint NOT NULL DEFAULT 0
);

CREATE TABLE app.report_targets (
  region text PRIMARY KEY
);

CREATE TABLE app.reports_archive (
  id         bigserial PRIMARY KEY,
  region     text NOT NULL,
  amount     int  NOT NULL,
  created_at timestamptz NOT NULL
);

INSERT INTO app.counters(name, n) VALUES ('reports', 0);

INSERT INTO app.report_targets(region)
SELECT 'r-' || lpad(i::text, 2, '0') FROM generate_series(1, 40) i;

INSERT INTO app.reports(region, amount)
SELECT 'r-' || lpad(((i % 40) + 1)::text, 2, '0'), (random() * 1000)::int
  FROM generate_series(1, 20) i;

INSERT INTO app.reports_archive(region, amount, created_at)
SELECT 'r-' || lpad(((i % 40) + 1)::text, 2, '0'),
       (random() * 1000)::int,
       now() - ((random() * 365)::int) * interval '1 day'
  FROM generate_series(1, 2000000) i;

CREATE INDEX idx_archive_region_created ON app.reports_archive(region, created_at);

ANALYZE;

-- アプリ用ロールの権限
GRANT USAGE ON SCHEMA app TO reportapi;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA app TO reportapi;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA app TO reportapi;

-- 監査基盤のテーブル。アプリロールには権限を渡していない
CREATE TABLE app.audit_log (
  id   bigserial PRIMARY KEY,
  at   timestamptz NOT NULL DEFAULT now(),
  what text NOT NULL
);

-- 接続時の既定値はロールに持たせてある
ALTER ROLE reportapi SET search_path = app, public;
ALTER ROLE reportapi SET statement_timeout = '3s';

-- 夜間バッチ用ロール
GRANT CONNECT ON DATABASE reportdb TO batchuser;
GRANT USAGE ON SCHEMA app TO batchuser;
GRANT SELECT, UPDATE ON app.counters TO batchuser;
