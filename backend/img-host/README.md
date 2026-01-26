# img-host

Multi-user image hosting backend using Cloudflare Workers, R2 storage, and D1 database.

## Features

- Multi-user authentication with API tokens
- Tiered subscriptions (free, pro, enterprise)
- Storage quotas and limits per tier
- Per-user image management
- Stripe integration ready
- API usage tracking and analytics

## Quick Start

### 1. Install Dependencies

```bash
npm install
```

### 2. Login to Cloudflare

```bash
wrangler login
```

### 3. Create R2 Bucket

```bash
wrangler r2 bucket create images
```

### 4. Initialize Database

Run the interactive setup script:

```bash
npm run db:init
```

Or manually:

```bash
# Create D1 database
wrangler d1 create imagehost

# Update wrangler.toml with the database_id from above

# Run migrations
npm run db:migrate:local  # For local development
npm run db:migrate        # For production
```

### 5. Run Locally

```bash
npm run dev
```

For local development, create a `.dev.vars` file:

```
UPLOAD_TOKEN=legacy-test-token
```

### 6. Test the API

```bash
./examples/api-examples.sh
```

### 7. Deploy

```bash
npm run deploy
```

## Database Setup

See [DATABASE.md](./DATABASE.md) for detailed database schema, migration instructions, and API documentation.

### Quick Database Commands

```bash
# Initialize database
npm run db:init

# Run migrations
npm run db:migrate:local      # Local
npm run db:migrate            # Production

# List tables
npm run db:tables:local       # Local
npm run db:tables             # Production

# Execute custom query
npm run db:query:local "SELECT * FROM users LIMIT 5;"
npm run db:query "SELECT * FROM users LIMIT 5;"
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
```

#### Login
```bash
POST /auth/login
Content-Type: application/json

{
  "email": "user@example.com",
  "password": "secure-password"
}
```

### User Management

#### Get User Info
```bash
GET /user
Authorization: Bearer <api_token>
```

#### List User Images
```bash
GET /images?limit=100&offset=0
Authorization: Bearer <api_token>
```

### Image Operations

#### Upload Image
```bash
POST /upload
Authorization: Bearer <api_token>
Content-Type: multipart/form-data

image=<file>
```

#### Get Image
```bash
GET /<id>.<ext>
```

#### Delete Image
```bash
DELETE /delete/<id>?token=<delete_token>
```

### Health Check
```bash
GET /health
```

## Subscription Tiers

### Free Tier
- 100MB storage
- 10MB max file size
- 100 images maximum
- API access

### Pro Tier
- 10GB storage
- 50MB max file size
- Unlimited images
- Custom domains
- Analytics
- API access

### Enterprise Tier
- 100GB storage
- 100MB max file size
- Unlimited images
- Custom domains
- Analytics
- API access
- Priority support

## Project Structure

```
img-host/
├── src/
│   ├── index.ts        # Main worker entry point
│   ├── database.ts     # D1 database utilities
│   ├── auth.ts         # Authentication utilities
│   └── types.ts        # TypeScript type definitions
├── migrations/
│   └── 0001_initial_schema.sql
├── scripts/
│   └── init-db.sh      # Database initialization script
├── examples/
│   └── api-examples.sh # API usage examples
├── schema.sql          # Complete database schema
├── DATABASE.md         # Database documentation
├── wrangler.toml       # Cloudflare configuration
└── package.json
```

## Development

### Local Development with Database

```bash
# Start local dev server
npm run dev

# In another terminal, run migrations
npm run db:migrate:local

# Create test user and get API token
./examples/api-examples.sh
```

### Testing

```bash
# Test API endpoints
./examples/api-examples.sh

# Query database
npm run db:query:local "SELECT * FROM storage_usage;"

# Check user storage
npm run db:query:local "
SELECT
  u.email,
  COUNT(i.id) as image_count,
  SUM(i.size_bytes) as total_bytes
FROM users u
LEFT JOIN images i ON u.id = i.user_id
GROUP BY u.id;
"
```

## Security

- Passwords are hashed using SHA-256 (consider upgrading to bcrypt/Argon2 for production)
- API tokens are cryptographically secure UUIDs
- All database queries use parameterized statements
- Per-image delete tokens prevent unauthorized deletion
- Storage quotas enforce tier limits

## Migration from Single-User

The legacy `UPLOAD_TOKEN` environment variable is still supported for backward compatibility, but new users should register via `/auth/register` and use API tokens.

## Next Steps

- [ ] Implement Stripe webhook handlers
- [ ] Add rate limiting using api_usage table
- [ ] Set up automated cleanup of orphaned R2 objects
- [ ] Add email verification
- [ ] Implement password reset
- [ ] Add OAuth providers (Google, GitHub)

## Troubleshooting

### Database Not Found
Verify `database_id` in `wrangler.toml` matches the output from `wrangler d1 create imagehost`

### Migration Failed
Check SQL syntax and ensure you're using SQLite-compatible SQL

### Permission Denied
Ensure you're authenticated: `wrangler login`

See [DATABASE.md](./DATABASE.md) for more troubleshooting tips.

## License

Private - All rights reserved
