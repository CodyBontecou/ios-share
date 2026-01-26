# Authentication System Setup Guide

Quick setup guide for implementing the enhanced authentication system.

## Prerequisites

- Cloudflare account with Wrangler CLI installed
- D1 database already created (from initial setup)
- Node.js and npm installed

## Step 1: Run Database Migration

The authentication system requires additional database tables for JWT refresh tokens, rate limiting, and email verification.

### Local Development

```bash
# Run the authentication migration
npm run db:migrate:auth:local

# Verify tables were created
npm run db:tables:local
```

Expected output should include:
- `users` (with new columns)
- `refresh_tokens`
- `rate_limits`
- `email_verification_attempts`

### Production

```bash
# Run the authentication migration
npm run db:migrate:auth

# Verify tables were created
npm run db:tables
```

## Step 2: Configure Environment Variables

### Generate JWT Secret

```bash
# Generate a secure random secret (32 bytes base64 encoded)
openssl rand -base64 32
```

### Local Development

Create `.dev.vars` file (copy from `.dev.vars.example`):

```bash
cp .dev.vars.example .dev.vars
```

Edit `.dev.vars`:

```env
# Required: Your generated JWT secret
JWT_SECRET=your-generated-secret-here

# Optional: Email configuration
EMAIL_FROM=noreply@your-domain.com
EMAIL_API_KEY=your-sendgrid-api-key
BASE_URL=http://localhost:8787

# Legacy (optional)
UPLOAD_TOKEN=legacy-test-token
```

### Production

Set secrets using Wrangler:

```bash
# Set JWT secret (will prompt for input)
wrangler secret put JWT_SECRET

# Optional: Set email API key
wrangler secret put EMAIL_API_KEY
```

Update `wrangler.toml` for non-secret variables:

```toml
[vars]
EMAIL_FROM = "noreply@your-production-domain.com"
BASE_URL = "https://your-production-domain.com"
```

## Step 3: Test the Implementation

### Start Development Server

```bash
npm run dev
```

### Run Authentication Tests

```bash
# Run the test suite
./examples/test-auth.sh http://localhost:8787
```

### Manual Testing

#### 1. Register a New User

```bash
curl -X POST http://localhost:8787/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "SecurePassword123"
  }'
```

Expected response:
```json
{
  "access_token": "eyJhbGc...",
  "refresh_token": "...",
  "api_token": "uuid-here",
  "expires_in": 3600,
  "token_type": "Bearer",
  "user_id": "uuid",
  "email": "test@example.com",
  "subscription_tier": "free",
  "email_verified": false,
  "message": "Registration successful. Please check your email to verify your account."
}
```

#### 2. Login

```bash
curl -X POST http://localhost:8787/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "SecurePassword123"
  }'
```

#### 3. Test JWT Authentication

```bash
# Save the access token from login/register response
ACCESS_TOKEN="your-access-token-here"

# Make authenticated request
curl -X GET http://localhost:8787/user \
  -H "Authorization: Bearer $ACCESS_TOKEN"
```

#### 4. Test Token Refresh

```bash
# Save the refresh token from login/register response
REFRESH_TOKEN="your-refresh-token-here"

# Refresh access token
curl -X POST http://localhost:8787/auth/refresh \
  -H "Content-Type: application/json" \
  -d "{\"refresh_token\":\"$REFRESH_TOKEN\"}"
```

## Step 4: Email Verification Setup (Optional)

### Development (Console Logging)

By default, emails are logged to the console. Check server logs for:
- Email verification tokens
- Password reset tokens

Example log output:
```
[EMAIL] To: test@example.com
Subject: Verify your email address
Body: Welcome to ImageHost! Please verify your email by clicking this link: http://localhost:8787/auth/verify-email?token=...
```

### Production (Email Service Integration)

Edit `src/auth-handlers.ts` and uncomment the email service integration code.

#### Option 1: SendGrid

1. Sign up at https://sendgrid.com
2. Create an API key
3. Set `EMAIL_API_KEY` secret
4. Uncomment SendGrid code in `sendEmail()` function

#### Option 2: Postmark

Similar setup with Postmark API

#### Option 3: Cloudflare Email Workers

Use Cloudflare's email routing and workers

## Step 5: Verify Email Flow

### Get Verification Token from Logs

After registration, check console logs for the verification token.

### Verify Email

```bash
# Using token from logs
VERIFY_TOKEN="token-from-logs"

curl -X POST http://localhost:8787/auth/verify-email \
  -H "Content-Type: application/json" \
  -d "{\"token\":\"$VERIFY_TOKEN\"}"
```

Expected response:
```json
{
  "message": "Email successfully verified!",
  "email_verified": true
}
```

## Step 6: Test Password Reset Flow

### Request Password Reset

```bash
curl -X POST http://localhost:8787/auth/forgot-password \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com"
  }'
```

### Get Reset Token from Logs

Check console logs for the password reset token.

### Reset Password

```bash
# Using token from logs
RESET_TOKEN="token-from-logs"

curl -X POST http://localhost:8787/auth/reset-password \
  -H "Content-Type: application/json" \
  -d '{
    "token": "'"$RESET_TOKEN"'",
    "new_password": "NewSecurePassword456"
  }'
```

### Login with New Password

```bash
curl -X POST http://localhost:8787/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "NewSecurePassword456"
  }'
```

## Step 7: Deploy to Production

### Build and Deploy

```bash
# Deploy to Cloudflare Workers
npm run deploy
```

### Run Production Migration

```bash
# Run authentication migration on production database
npm run db:migrate:auth
```

### Verify Production

```bash
# Test production endpoints
./examples/test-auth.sh https://your-worker-url.workers.dev
```

## Troubleshooting

### Migration Errors

**Error: "table already exists"**
- Some tables may have been created by other migrations
- Check which migration added them
- You can skip duplicate table creation or run migrations individually

**Error: "no such table: users"**
- Run the initial schema migration first: `npm run db:migrate:local`

### JWT Errors

**Error: "Invalid JWT signature"**
- Ensure `JWT_SECRET` is set in `.dev.vars` or production secrets
- Secret must be the same across all instances
- Generate a new secret if needed: `openssl rand -base64 32`

**Error: "JWT expired"**
- Access tokens expire after 1 hour
- Use the refresh token to get a new access token
- See Step 4 for refresh token usage

### Rate Limiting

**Error: "Too many requests"**
- Rate limits are working correctly
- Wait for the window to reset (shown in `retry_after` field)
- For development, you can clear rate limits:
  ```bash
  npm run db:query:local "DELETE FROM rate_limits;"
  ```

### Email Issues

**Emails not sending**
- Check that `EMAIL_API_KEY` and `EMAIL_FROM` are configured
- Verify email service credentials
- Check email service logs/dashboard
- In development, emails are logged to console by default

**Can't find verification token**
- Check console logs where `wrangler dev` is running
- Look for `[EMAIL]` prefix in logs
- Token is included in the email body

## Security Checklist

Before going to production:

- [ ] Generated strong `JWT_SECRET` (32+ bytes)
- [ ] Set `JWT_SECRET` as a Wrangler secret (not in code)
- [ ] Configured `BASE_URL` to production domain
- [ ] Email service configured and tested
- [ ] HTTPS enforced on production domain
- [ ] Rate limiting tested and working
- [ ] Password requirements enforced (min 8 characters)
- [ ] Email verification flow tested
- [ ] Password reset flow tested
- [ ] Token refresh tested
- [ ] Old API tokens still work (backward compatibility)

## Performance Optimization

### Database Indexes

All necessary indexes are created by the migration:
- Email lookup index
- API token index
- Refresh token index
- Rate limit indexes

### Cleanup Scheduled Tasks

Consider adding scheduled cleanup tasks:

```typescript
// In a scheduled worker or cron job
await db.cleanupExpiredRefreshTokens();
await db.cleanupOldRateLimits(3600000); // 1 hour
await db.cleanupOldApiUsage(30); // 30 days
```

## Next Steps

1. Review [AUTHENTICATION.md](./AUTHENTICATION.md) for complete API documentation
2. Integrate with your iOS app using the JWT tokens
3. Set up email service for production
4. Configure monitoring and alerts
5. Implement OAuth providers (optional)
6. Add two-factor authentication (optional)

## Support

For issues or questions:
1. Check [AUTHENTICATION.md](./AUTHENTICATION.md)
2. Check [DATABASE.md](./DATABASE.md)
3. Review server logs for detailed error messages
4. Verify environment variables are set correctly
