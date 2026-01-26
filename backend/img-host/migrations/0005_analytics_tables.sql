-- Analytics tables for tracking usage, engagement, and business metrics

-- Daily aggregated metrics for system-wide analytics
CREATE TABLE IF NOT EXISTS analytics_daily_metrics (
  date TEXT PRIMARY KEY, -- Format: YYYY-MM-DD
  total_uploads INTEGER NOT NULL DEFAULT 0,
  total_bytes_uploaded INTEGER NOT NULL DEFAULT 0,
  total_deletions INTEGER NOT NULL DEFAULT 0,
  new_users INTEGER NOT NULL DEFAULT 0,
  active_users INTEGER NOT NULL DEFAULT 0, -- DAU
  total_api_calls INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL -- Unix timestamp
);

CREATE INDEX IF NOT EXISTS idx_analytics_daily_date ON analytics_daily_metrics(date);

-- Image format analytics
CREATE TABLE IF NOT EXISTS analytics_image_formats (
  id TEXT PRIMARY KEY,
  date TEXT NOT NULL, -- Format: YYYY-MM-DD
  content_type TEXT NOT NULL,
  upload_count INTEGER NOT NULL DEFAULT 0,
  total_bytes INTEGER NOT NULL DEFAULT 0,
  avg_size_bytes INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_analytics_formats_date ON analytics_image_formats(date);
CREATE INDEX IF NOT EXISTS idx_analytics_formats_content_type ON analytics_image_formats(content_type);

-- User engagement tracking
CREATE TABLE IF NOT EXISTS analytics_user_engagement (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  date TEXT NOT NULL, -- Format: YYYY-MM-DD
  uploads_count INTEGER NOT NULL DEFAULT 0,
  deletions_count INTEGER NOT NULL DEFAULT 0,
  api_calls_count INTEGER NOT NULL DEFAULT 0,
  last_activity_timestamp INTEGER NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_analytics_engagement_user ON analytics_user_engagement(user_id);
CREATE INDEX IF NOT EXISTS idx_analytics_engagement_date ON analytics_user_engagement(date);
CREATE UNIQUE INDEX IF NOT EXISTS idx_analytics_engagement_user_date ON analytics_user_engagement(user_id, date);

-- Subscription conversion tracking
CREATE TABLE IF NOT EXISTS analytics_subscription_events (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  event_type TEXT NOT NULL, -- 'signup', 'upgrade', 'downgrade', 'cancel', 'reactivate', 'churn'
  from_tier TEXT, -- Previous tier (NULL for signup)
  to_tier TEXT NOT NULL, -- New tier
  timestamp INTEGER NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_analytics_sub_events_user ON analytics_subscription_events(user_id);
CREATE INDEX IF NOT EXISTS idx_analytics_sub_events_type ON analytics_subscription_events(event_type);
CREATE INDEX IF NOT EXISTS idx_analytics_sub_events_timestamp ON analytics_subscription_events(timestamp);

-- Revenue metrics (aggregated monthly)
CREATE TABLE IF NOT EXISTS analytics_revenue_metrics (
  month TEXT PRIMARY KEY, -- Format: YYYY-MM
  mrr INTEGER NOT NULL DEFAULT 0, -- Monthly Recurring Revenue in cents
  arr INTEGER NOT NULL DEFAULT 0, -- Annual Recurring Revenue in cents
  new_mrr INTEGER NOT NULL DEFAULT 0, -- New MRR from new subscriptions
  expansion_mrr INTEGER NOT NULL DEFAULT 0, -- MRR from upgrades
  contraction_mrr INTEGER NOT NULL DEFAULT 0, -- MRR lost from downgrades
  churned_mrr INTEGER NOT NULL DEFAULT 0, -- MRR lost from cancellations
  active_subscriptions INTEGER NOT NULL DEFAULT 0,
  free_users INTEGER NOT NULL DEFAULT 0,
  pro_users INTEGER NOT NULL DEFAULT 0,
  enterprise_users INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_analytics_revenue_month ON analytics_revenue_metrics(month);

-- Storage growth tracking (daily snapshots)
CREATE TABLE IF NOT EXISTS analytics_storage_snapshots (
  id TEXT PRIMARY KEY,
  date TEXT NOT NULL, -- Format: YYYY-MM-DD
  total_users INTEGER NOT NULL DEFAULT 0,
  total_images INTEGER NOT NULL DEFAULT 0,
  total_bytes_stored INTEGER NOT NULL DEFAULT 0,
  avg_bytes_per_user INTEGER NOT NULL DEFAULT 0,
  avg_images_per_user INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_analytics_storage_date ON analytics_storage_snapshots(date);

-- Feature usage tracking
CREATE TABLE IF NOT EXISTS analytics_feature_usage (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  feature_name TEXT NOT NULL, -- e.g., 'share', 'album', 'tag', 'custom_domain'
  usage_count INTEGER NOT NULL DEFAULT 0,
  first_used_at INTEGER NOT NULL,
  last_used_at INTEGER NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_analytics_feature_user ON analytics_feature_usage(user_id);
CREATE INDEX IF NOT EXISTS idx_analytics_feature_name ON analytics_feature_usage(feature_name);
CREATE UNIQUE INDEX IF NOT EXISTS idx_analytics_feature_user_name ON analytics_feature_usage(user_id, feature_name);

-- User opt-out preferences (GDPR compliance)
CREATE TABLE IF NOT EXISTS analytics_privacy_settings (
  user_id TEXT PRIMARY KEY,
  analytics_enabled INTEGER NOT NULL DEFAULT 1, -- Boolean: 0 or 1
  data_retention_days INTEGER NOT NULL DEFAULT 90,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_analytics_privacy_user ON analytics_privacy_settings(user_id);
