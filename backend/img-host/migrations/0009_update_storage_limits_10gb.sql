-- Migration: Update storage limits to 10GB for all tiers (except enterprise)
-- Also migrate 'free' tier users to 'trial' tier

-- Update all users to 10GB storage limit (10000000000 bytes = 10GB exactly)
-- Enterprise users get 100GB (100000000000 bytes)
UPDATE users
SET storage_limit_bytes = 10000000000
WHERE subscription_tier IN ('trial', 'pro');

UPDATE users
SET storage_limit_bytes = 100000000000
WHERE subscription_tier = 'enterprise';

-- Migrate free tier users to trial
UPDATE users
SET subscription_tier = 'trial'
WHERE subscription_tier = 'free';

-- Update tier_limits table
UPDATE tier_limits
SET storage_limit_bytes = 10000000000
WHERE tier IN ('trial', 'pro');

UPDATE tier_limits
SET storage_limit_bytes = 100000000000
WHERE tier = 'enterprise';
