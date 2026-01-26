-- Migration: 0002_export_jobs
-- Description: Add export jobs table for bulk image export feature
-- Date: 2026-01-26

-- Export jobs table
CREATE TABLE export_jobs (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'processing', -- processing, completed, failed
  image_count INTEGER NOT NULL DEFAULT 0,
  archive_size INTEGER NOT NULL DEFAULT 0,
  download_url TEXT,
  expires_at INTEGER,
  error_message TEXT,
  created_at INTEGER NOT NULL,
  completed_at INTEGER,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX idx_export_jobs_user_id ON export_jobs(user_id);
CREATE INDEX idx_export_jobs_status ON export_jobs(status);
CREATE INDEX idx_export_jobs_created_at ON export_jobs(created_at);
CREATE INDEX idx_export_jobs_expires_at ON export_jobs(expires_at);

-- Rate limiting table for exports (1 per hour per user)
CREATE TABLE export_rate_limits (
  user_id TEXT PRIMARY KEY,
  last_export_at INTEGER NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);
