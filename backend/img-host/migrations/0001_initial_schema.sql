-- Migration: 0001_initial_schema
-- Description: Initial database schema for multi-user support
-- Date: 2026-01-26

-- Users table
CREATE TABLE users (
  id TEXT PRIMARY KEY,
  email TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  subscription_tier TEXT NOT NULL DEFAULT 'free',
  api_token TEXT UNIQUE NOT NULL,
  storage_limit_bytes INTEGER NOT NULL DEFAULT 104857600
);

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_api_token ON users(api_token);

-- Images table
CREATE TABLE images (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  r2_key TEXT UNIQUE NOT NULL,
  filename TEXT NOT NULL,
  size_bytes INTEGER NOT NULL,
  content_type TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  delete_token TEXT NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX idx_images_user_id ON images(user_id);
CREATE INDEX idx_images_r2_key ON images(r2_key);
CREATE INDEX idx_images_delete_token ON images(delete_token);
CREATE INDEX idx_images_created_at ON images(created_at);

-- Subscriptions table
CREATE TABLE subscriptions (
  id TEXT PRIMARY KEY,
  user_id TEXT UNIQUE NOT NULL,
  tier TEXT NOT NULL,
  status TEXT NOT NULL,
  stripe_customer_id TEXT,
  stripe_subscription_id TEXT,
  current_period_start INTEGER,
  current_period_end INTEGER,
  cancel_at_period_end INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX idx_subscriptions_user_id ON subscriptions(user_id);
CREATE INDEX idx_subscriptions_stripe_customer_id ON subscriptions(stripe_customer_id);
CREATE INDEX idx_subscriptions_stripe_subscription_id ON subscriptions(stripe_subscription_id);
CREATE INDEX idx_subscriptions_status ON subscriptions(status);

-- Storage usage view
CREATE VIEW storage_usage AS
SELECT
  user_id,
  COUNT(*) as image_count,
  COALESCE(SUM(size_bytes), 0) as total_bytes_used
FROM images
GROUP BY user_id;

-- Tier limits configuration
CREATE TABLE tier_limits (
  tier TEXT PRIMARY KEY,
  storage_limit_bytes INTEGER NOT NULL,
  max_file_size_bytes INTEGER NOT NULL,
  max_images INTEGER,
  features TEXT
);

INSERT INTO tier_limits (tier, storage_limit_bytes, max_file_size_bytes, max_images, features) VALUES
  ('free', 104857600, 10485760, 100, '{"custom_domains":false,"analytics":false,"api_access":true}'),
  ('pro', 10737418240, 52428800, NULL, '{"custom_domains":true,"analytics":true,"api_access":true}'),
  ('enterprise', 107374182400, 104857600, NULL, '{"custom_domains":true,"analytics":true,"api_access":true,"priority_support":true}');

-- API usage tracking
CREATE TABLE api_usage (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  endpoint TEXT NOT NULL,
  method TEXT NOT NULL,
  timestamp INTEGER NOT NULL,
  response_status INTEGER NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX idx_api_usage_user_id ON api_usage(user_id);
CREATE INDEX idx_api_usage_timestamp ON api_usage(timestamp);
