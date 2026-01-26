-- Rate limiting tables and abuse prevention schema

-- Rate limit tracking table (for user-based rate limiting)
CREATE TABLE IF NOT EXISTS rate_limits (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  endpoint TEXT NOT NULL,
  window_start INTEGER NOT NULL, -- Unix timestamp for the start of the current window
  request_count INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  UNIQUE(user_id, endpoint, window_start)
);

CREATE INDEX IF NOT EXISTS idx_rate_limits_user_endpoint ON rate_limits(user_id, endpoint, window_start);
CREATE INDEX IF NOT EXISTS idx_rate_limits_window_start ON rate_limits(window_start);

-- IP-based rate limiting (for unauthenticated requests)
CREATE TABLE IF NOT EXISTS ip_rate_limits (
  id TEXT PRIMARY KEY,
  ip_address TEXT NOT NULL,
  endpoint TEXT NOT NULL,
  window_start INTEGER NOT NULL,
  request_count INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  UNIQUE(ip_address, endpoint, window_start)
);

CREATE INDEX IF NOT EXISTS idx_ip_rate_limits_ip_endpoint ON ip_rate_limits(ip_address, endpoint, window_start);
CREATE INDEX IF NOT EXISTS idx_ip_rate_limits_window_start ON ip_rate_limits(window_start);

-- Failed login attempts tracking (for exponential backoff and CAPTCHA triggers)
CREATE TABLE IF NOT EXISTS failed_attempts (
  id TEXT PRIMARY KEY,
  identifier TEXT NOT NULL, -- email or IP address
  attempt_type TEXT NOT NULL, -- 'login' or 'register'
  attempt_count INTEGER NOT NULL DEFAULT 1,
  last_attempt_at INTEGER NOT NULL,
  locked_until INTEGER, -- NULL if not locked, timestamp if locked
  created_at INTEGER NOT NULL,
  UNIQUE(identifier, attempt_type)
);

CREATE INDEX IF NOT EXISTS idx_failed_attempts_identifier ON failed_attempts(identifier, attempt_type);
CREATE INDEX IF NOT EXISTS idx_failed_attempts_locked_until ON failed_attempts(locked_until);

-- Abuse reports table
CREATE TABLE IF NOT EXISTS abuse_reports (
  id TEXT PRIMARY KEY,
  reported_image_id TEXT NOT NULL,
  reported_user_id TEXT NOT NULL,
  reporter_user_id TEXT, -- NULL if reported by anonymous user
  reporter_ip TEXT,
  reason TEXT NOT NULL, -- 'nsfw', 'copyright', 'malware', 'other'
  description TEXT,
  status TEXT NOT NULL DEFAULT 'pending', -- 'pending', 'reviewing', 'resolved', 'dismissed'
  created_at INTEGER NOT NULL,
  reviewed_at INTEGER,
  reviewed_by TEXT, -- admin user ID
  resolution_notes TEXT,
  FOREIGN KEY (reported_image_id) REFERENCES images(id) ON DELETE CASCADE,
  FOREIGN KEY (reported_user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (reporter_user_id) REFERENCES users(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_abuse_reports_image_id ON abuse_reports(reported_image_id);
CREATE INDEX IF NOT EXISTS idx_abuse_reports_user_id ON abuse_reports(reported_user_id);
CREATE INDEX IF NOT EXISTS idx_abuse_reports_status ON abuse_reports(status);
CREATE INDEX IF NOT EXISTS idx_abuse_reports_created_at ON abuse_reports(created_at);

-- Content moderation flags table
CREATE TABLE IF NOT EXISTS content_flags (
  id TEXT PRIMARY KEY,
  image_id TEXT NOT NULL,
  flag_type TEXT NOT NULL, -- 'nsfw', 'copyright', 'malware', 'suspicious'
  confidence_score REAL, -- 0.0 to 1.0 for automated detection
  flagged_by TEXT, -- 'system' or user_id if manually flagged
  metadata TEXT, -- JSON string with additional details
  created_at INTEGER NOT NULL,
  FOREIGN KEY (image_id) REFERENCES images(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_content_flags_image_id ON content_flags(image_id);
CREATE INDEX IF NOT EXISTS idx_content_flags_flag_type ON content_flags(flag_type);
CREATE INDEX IF NOT EXISTS idx_content_flags_created_at ON content_flags(created_at);

-- User suspensions table
CREATE TABLE IF NOT EXISTS user_suspensions (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  reason TEXT NOT NULL,
  suspended_at INTEGER NOT NULL,
  suspended_until INTEGER, -- NULL for permanent suspension
  suspended_by TEXT, -- 'system' or admin user ID
  notes TEXT,
  is_active INTEGER NOT NULL DEFAULT 1, -- Boolean: 0 or 1
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_user_suspensions_user_id ON user_suspensions(user_id);
CREATE INDEX IF NOT EXISTS idx_user_suspensions_active ON user_suspensions(is_active);
CREATE INDEX IF NOT EXISTS idx_user_suspensions_until ON user_suspensions(suspended_until);

-- Update tier_limits table to include daily rate limits
ALTER TABLE tier_limits ADD COLUMN daily_upload_limit INTEGER;
ALTER TABLE tier_limits ADD COLUMN daily_api_limit INTEGER;

-- Update tier limits with rate limit values
UPDATE tier_limits SET daily_upload_limit = 100, daily_api_limit = 1000 WHERE tier = 'free';
UPDATE tier_limits SET daily_upload_limit = 1000, daily_api_limit = 10000 WHERE tier = 'pro';
UPDATE tier_limits SET daily_upload_limit = NULL, daily_api_limit = NULL WHERE tier = 'enterprise'; -- NULL means unlimited
