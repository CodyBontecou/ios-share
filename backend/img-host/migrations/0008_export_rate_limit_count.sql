-- Migration: 0008_export_rate_limit_count
-- Description: Add export count tracking for 5 exports per hour limit
-- Date: 2026-02-01

-- Add export_count and window_start columns to track multiple exports per window
ALTER TABLE export_rate_limits ADD COLUMN export_count INTEGER NOT NULL DEFAULT 1;
ALTER TABLE export_rate_limits ADD COLUMN window_start INTEGER;

-- Update existing rows to set window_start from last_export_at
UPDATE export_rate_limits SET window_start = last_export_at WHERE window_start IS NULL;
