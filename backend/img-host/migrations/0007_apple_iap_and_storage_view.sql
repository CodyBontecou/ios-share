-- Migration: 0007_apple_iap_and_storage_view
-- Description: Add Apple In-App Purchase fields to subscriptions and create storage_usage view
-- Date: 2026-02-01

-- Add Apple IAP fields to subscriptions table
ALTER TABLE subscriptions ADD COLUMN apple_original_transaction_id TEXT;
ALTER TABLE subscriptions ADD COLUMN apple_product_id TEXT;
ALTER TABLE subscriptions ADD COLUMN trial_ends_at INTEGER;

-- Create indexes for Apple IAP lookups
CREATE INDEX IF NOT EXISTS idx_subscriptions_apple_transaction_id ON subscriptions(apple_original_transaction_id);

-- Create storage_usage view for efficient storage calculations
-- This aggregates image data per user without needing a separate table
CREATE VIEW IF NOT EXISTS storage_usage AS
SELECT
  user_id,
  COUNT(*) as image_count,
  COALESCE(SUM(size_bytes), 0) as total_bytes_used
FROM images
GROUP BY user_id;
