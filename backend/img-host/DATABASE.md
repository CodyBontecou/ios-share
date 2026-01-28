# Database Setup Guide

This guide covers setting up Cloudflare D1 database for multi-user support in the imghost backend.

## Overview

The database schema includes:
- **users**: User accounts with authentication and API tokens
- **images**: Image metadata and ownership tracking
- **subscriptions**: Subscription tier and Stripe integration
- **tier_limits**: Configuration for storage and feature limits
- **storage_usage**: View for tracking per-user storage consumption
- **api_usage**: API call logging for analytics and rate limiting

## Initial Setup

### 1. Create D1 Database

```bash
cd backend/img-host
wrangler d1 create imghost
```

This will output a database ID. Update `wrangler.toml` with the actual database ID:

```toml
[[d1_databases]]
binding = "DB"
database_name = "imghost"
database_id = "your-database-id-here"
```

### 2. Run Initial Migration

```bash
wrangler d1 execute imghost --file=./migrations/0001_initial_schema.sql
```

Or for local development:

```bash
wrangler d1 execute imghost --local --file=./migrations/0001_initial_schema.sql
```

### 3. Verify Schema

```bash
# List all tables
wrangler d1 execute imghost --command="SELECT name FROM sqlite_master WHERE type='table';"

# Check users table schema
wrangler d1 execute imghost --command="PRAGMA table_info(users);"
```

## Database Schema

### Users Table

```sql
CREATE TABLE users (
  id TEXT PRIMARY KEY,                          -- UUID
  email TEXT UNIQUE NOT NULL,                   -- User email (unique)
  password_hash TEXT NOT NULL,                  -- SHA-256 hashed password
  created_at INTEGER NOT NULL,                  -- Unix timestamp
  subscription_tier TEXT NOT NULL DEFAULT 'free', -- 'free', 'pro', 'enterprise'
  api_token TEXT UNIQUE NOT NULL,               -- UUID for API authentication
  storage_limit_bytes INTEGER NOT NULL DEFAULT 104857600 -- 100MB for free
);
```

### Images Table

```sql
CREATE TABLE images (
  id TEXT PRIMARY KEY,                          -- Short UUID (8 chars)
  user_id TEXT NOT NULL,                        -- Foreign key to users.id
  r2_key TEXT UNIQUE NOT NULL,                  -- R2 object key (id.ext)
  filename TEXT NOT NULL,                       -- Original filename
  size_bytes INTEGER NOT NULL,                  -- File size in bytes
  content_type TEXT NOT NULL,                   -- MIME type
  created_at INTEGER NOT NULL,                  -- Unix timestamp
  delete_token TEXT NOT NULL,                   -- UUID for deletion
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);
```

### Subscriptions Table

```sql
CREATE TABLE subscriptions (
  id TEXT PRIMARY KEY,                          -- UUID
  user_id TEXT UNIQUE NOT NULL,                 -- Foreign key to users.id
  tier TEXT NOT NULL,                           -- 'free', 'pro', 'enterprise'
  status TEXT NOT NULL,                         -- 'active', 'cancelled', 'past_due', 'trialing'
  stripe_customer_id TEXT,                      -- Stripe customer ID
  stripe_subscription_id TEXT,                  -- Stripe subscription ID
  current_period_start INTEGER,                 -- Unix timestamp
  current_period_end INTEGER,                   -- Unix timestamp
  cancel_at_period_end INTEGER NOT NULL DEFAULT 0, -- Boolean
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);
```

### Tier Limits Table

```sql
CREATE TABLE tier_limits (
  tier TEXT PRIMARY KEY,                        -- 'free', 'pro', 'enterprise'
  storage_limit_bytes INTEGER NOT NULL,         -- Total storage limit
  max_file_size_bytes INTEGER NOT NULL,         -- Max single file size
  max_images INTEGER,                           -- Max image count (NULL = unlimited)
  features TEXT                                 -- JSON string of features
);
```

Default tier limits:
- **free**: 100MB storage, 10MB per file, 100 images
- **pro**: 10GB storage, 50MB per file, unlimited images
- **enterprise**: 100GB storage, 100MB per file, unlimited images

### Storage Usage View

```sql
CREATE VIEW storage_usage AS
SELECT
  user_id,
  COUNT(*) as image_count,
  COALESCE(SUM(size_bytes), 0) as total_bytes_used
FROM images
GROUP BY user_id;
```

### API Usage Table

```sql
CREATE TABLE api_usage (
  id TEXT PRIMARY KEY,                          -- UUID
  user_id TEXT NOT NULL,                        -- Foreign key to users.id
  endpoint TEXT NOT NULL,                       -- API endpoint called
  method TEXT NOT NULL,                         -- HTTP method
  timestamp INTEGER NOT NULL,                   -- Unix timestamp
  response_status INTEGER NOT NULL,             -- HTTP status code
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);
```

## API Endpoints

### Authentication

#### Register User
```bash
POST /auth/register
Content-Type: application/json

{
  "email": "user@example.com",
  "password": "secure-password"
}

Response:
{
  "user_id": "uuid",
  "email": "user@example.com",
  "api_token": "uuid",
  "subscription_tier": "free"
}
```

#### Login
```bash
POST /auth/login
Content-Type: application/json

{
  "email": "user@example.com",
  "password": "secure-password"
}

Response:
{
  "user_id": "uuid",
  "email": "user@example.com",
  "api_token": "uuid",
  "subscription_tier": "free"
}
```

### User Management

#### Get User Info
```bash
GET /user
Authorization: Bearer <api_token>

Response:
{
  "user_id": "uuid",
  "email": "user@example.com",
  "subscription_tier": "free",
  "storage_limit_bytes": 104857600,
  "storage_used_bytes": 12345678,
  "image_count": 42
}
```

#### List User Images
```bash
GET /images?limit=100&offset=0
Authorization: Bearer <api_token>

Response:
{
  "images": [
    {
      "id": "abc123",
      "filename": "photo.jpg",
      "url": "https://example.com/abc123.jpg",
      "size_bytes": 123456,
      "content_type": "image/jpeg",
      "created_at": 1706227200000
    }
  ],
  "count": 1
}
```

### Image Operations

#### Upload Image
```bash
POST /upload
Authorization: Bearer <api_token>
Content-Type: multipart/form-data

image=<file>

Response:
{
  "url": "https://example.com/abc123.jpg",
  "id": "abc123",
  "deleteUrl": "https://example.com/delete/abc123?token=delete-token"
}
```

#### Delete Image
```bash
DELETE /delete/<id>?token=<delete_token>

Response:
{
  "deleted": true
}
```

## Development

### Local Testing

Use Wrangler's local mode for development:

```bash
# Start local dev server
npm run dev

# Execute queries locally
wrangler d1 execute imghost --local --command="SELECT * FROM users LIMIT 10;"
```

### Testing the Database

```bash
# Create a test user
wrangler d1 execute imghost --local --command="
INSERT INTO users (id, email, password_hash, created_at, subscription_tier, api_token, storage_limit_bytes)
VALUES ('test-user-1', 'test@example.com', 'hash', $(date +%s)000, 'free', 'test-token-123', 104857600);
"

# Query users
wrangler d1 execute imghost --local --command="SELECT * FROM users;"

# Check storage usage
wrangler d1 execute imghost --local --command="SELECT * FROM storage_usage;"
```

## Migration Strategy

For future schema changes:

1. Create a new migration file in `migrations/` directory
2. Name it with incrementing number: `0002_description.sql`
3. Test locally first: `wrangler d1 execute imghost --local --file=./migrations/0002_description.sql`
4. Deploy to production: `wrangler d1 execute imghost --file=./migrations/0002_description.sql`

## Production Deployment

```bash
# Deploy worker with database binding
wrangler deploy

# Verify database connection
curl https://your-worker.workers.dev/health
```

## Security Considerations

1. **Password Storage**: Passwords are hashed using SHA-256. Consider upgrading to bcrypt or Argon2 for production.
2. **API Tokens**: Generated using `crypto.randomUUID()` which provides cryptographically secure random values.
3. **Delete Tokens**: Stored per-image to prevent unauthorized deletion.
4. **SQL Injection**: All queries use parameterized statements to prevent SQL injection.

## Monitoring & Maintenance

### Check Storage Usage

```bash
wrangler d1 execute imghost --command="
SELECT
  u.email,
  su.image_count,
  su.total_bytes_used,
  u.storage_limit_bytes,
  ROUND((su.total_bytes_used * 100.0) / u.storage_limit_bytes, 2) as usage_percent
FROM users u
LEFT JOIN storage_usage su ON u.id = su.user_id
ORDER BY usage_percent DESC
LIMIT 10;
"
```

### Cleanup Old API Logs

```bash
# Delete API usage logs older than 30 days
wrangler d1 execute imghost --command="
DELETE FROM api_usage
WHERE timestamp < $(date -d '30 days ago' +%s)000;
"
```

## Troubleshooting

### Database Not Found
- Verify database ID in `wrangler.toml` matches output from `wrangler d1 create`
- Check you're using the correct Cloudflare account

### Migration Failed
- Check syntax errors in SQL file
- Verify you're using SQLite-compatible SQL (D1 is SQLite)
- Try running locally first with `--local` flag

### Permission Denied
- Ensure you're authenticated: `wrangler login`
- Check your Cloudflare account has D1 access

## Next Steps

- [ ] Implement Stripe webhook handlers for subscription management
- [ ] Add rate limiting using api_usage table
- [ ] Set up automated cleanup of orphaned R2 objects
- [ ] Add email verification flow
- [ ] Implement password reset functionality
- [ ] Add OAuth providers (Google, GitHub)
