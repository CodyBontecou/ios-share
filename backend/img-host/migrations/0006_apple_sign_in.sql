-- Migration: 0006_apple_sign_in
-- Description: Add Apple Sign-In support with account linking
-- Date: 2026-01-26

-- Add Apple user ID to users table for account linking
-- This is the stable identifier from Apple (the "sub" claim in the identity token)
-- Note: Cannot add UNIQUE constraint directly in SQLite ALTER TABLE, so we add column first
ALTER TABLE users ADD COLUMN apple_user_id TEXT;

-- Create unique index for fast Apple user lookups and ensure uniqueness
CREATE UNIQUE INDEX idx_users_apple_user_id ON users(apple_user_id);
