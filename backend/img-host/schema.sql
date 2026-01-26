-- Users table
CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  email TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  created_at INTEGER NOT NULL, -- Unix timestamp
  subscription_tier TEXT NOT NULL DEFAULT 'free', -- 'free', 'pro', 'enterprise'
  api_token TEXT UNIQUE NOT NULL,
  storage_limit_bytes INTEGER NOT NULL DEFAULT 104857600, -- 100MB for free tier
  UNIQUE(email),
  UNIQUE(api_token)
);

CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_api_token ON users(api_token);

-- Images table
CREATE TABLE IF NOT EXISTS images (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  r2_key TEXT UNIQUE NOT NULL,
  filename TEXT NOT NULL,
  size_bytes INTEGER NOT NULL,
  content_type TEXT NOT NULL,
  created_at INTEGER NOT NULL, -- Unix timestamp
  delete_token TEXT NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_images_user_id ON images(user_id);
CREATE INDEX IF NOT EXISTS idx_images_r2_key ON images(r2_key);
CREATE INDEX IF NOT EXISTS idx_images_delete_token ON images(delete_token);
CREATE INDEX IF NOT EXISTS idx_images_created_at ON images(created_at);

-- Subscriptions table
CREATE TABLE IF NOT EXISTS subscriptions (
  id TEXT PRIMARY KEY,
  user_id TEXT UNIQUE NOT NULL,
  tier TEXT NOT NULL, -- 'free', 'pro', 'enterprise'
  status TEXT NOT NULL, -- 'active', 'cancelled', 'past_due', 'trialing'
  stripe_customer_id TEXT,
  stripe_subscription_id TEXT,
  current_period_start INTEGER, -- Unix timestamp
  current_period_end INTEGER, -- Unix timestamp
  cancel_at_period_end INTEGER NOT NULL DEFAULT 0, -- Boolean: 0 or 1
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_subscriptions_user_id ON subscriptions(user_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_stripe_customer_id ON subscriptions(stripe_customer_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_stripe_subscription_id ON subscriptions(stripe_subscription_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_status ON subscriptions(status);

-- Storage usage view (computed from images table)
-- This is a view that aggregates storage usage per user
CREATE VIEW IF NOT EXISTS storage_usage AS
SELECT
  user_id,
  COUNT(*) as image_count,
  COALESCE(SUM(size_bytes), 0) as total_bytes_used
FROM images
GROUP BY user_id;

-- Tier limits configuration table
CREATE TABLE IF NOT EXISTS tier_limits (
  tier TEXT PRIMARY KEY,
  storage_limit_bytes INTEGER NOT NULL,
  max_file_size_bytes INTEGER NOT NULL,
  max_images INTEGER, -- NULL means unlimited
  features TEXT -- JSON string of feature flags
);

-- Insert default tier limits
INSERT OR REPLACE INTO tier_limits (tier, storage_limit_bytes, max_file_size_bytes, max_images, features) VALUES
  ('free', 104857600, 10485760, 100, '{"custom_domains":false,"analytics":false,"api_access":true}'), -- 100MB storage, 10MB per file, 100 images
  ('pro', 10737418240, 52428800, NULL, '{"custom_domains":true,"analytics":true,"api_access":true}'), -- 10GB storage, 50MB per file, unlimited images
  ('enterprise', 107374182400, 104857600, NULL, '{"custom_domains":true,"analytics":true,"api_access":true,"priority_support":true}'); -- 100GB storage, 100MB per file, unlimited images

-- API usage tracking (optional - for rate limiting and analytics)
CREATE TABLE IF NOT EXISTS api_usage (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  endpoint TEXT NOT NULL,
  method TEXT NOT NULL,
  timestamp INTEGER NOT NULL,
  response_status INTEGER NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_api_usage_user_id ON api_usage(user_id);
CREATE INDEX IF NOT EXISTS idx_api_usage_timestamp ON api_usage(timestamp);
