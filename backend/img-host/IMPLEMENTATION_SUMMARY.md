# Rate Limiting and Abuse Prevention - Implementation Summary

## Overview

This document summarizes the implementation of rate limiting and abuse prevention features for the imghost API, completed as part of issue `ios-share-azo`.

## Files Created

### Core Implementation Files

1. **src/rate-limiter.ts** (323 lines)
   - `RateLimiter` class for managing rate limits
   - User-based rate limiting with tier-specific limits
   - IP-based rate limiting for unauthenticated requests
   - Failed attempt tracking with exponential backoff
   - User suspension management
   - Helper functions: `getRateLimitConfig()`, `getIpRateLimitConfig()`

2. **src/content-moderation.ts** (380 lines)
   - `ContentModerator` class for content safety
   - File type validation using magic bytes
   - Malware scanning and detection
   - Abuse reporting system
   - Unusual upload pattern detection
   - Content flagging for review

3. **src/index.ts** (Updated - 850+ lines)
   - Integrated rate limiting into all endpoints
   - Added IP detection helper function
   - Enhanced upload handler with malware scanning
   - Protected login/register with failed attempt tracking
   - Added abuse report endpoint
   - Rate limit headers in all responses

### Database Files

4. **migrations/0002_rate_limiting.sql** (103 lines)
   - Database schema for rate limiting tables
   - Includes: rate_limits, ip_rate_limits, failed_attempts
   - Abuse prevention tables: abuse_reports, content_flags, user_suspensions
   - Indexes for optimal query performance

5. **schema.sql** (Updated)
   - Appended rate limiting schema to main schema file
   - Maintains backwards compatibility

### Documentation Files

6. **RATE_LIMITING.md** (450+ lines)
   - Comprehensive documentation of all features
   - API examples and integration guides
   - Monitoring and alerting recommendations
   - Configuration instructions
   - Security considerations

7. **IMPLEMENTATION_SUMMARY.md** (This file)
   - Implementation overview and summary

### Test Files

8. **tests/rate-limiting.test.ts** (200+ lines)
   - Unit tests for rate limiting logic
   - File type detection tests
   - Malware scanning tests
   - Exponential backoff validation

## Features Implemented

### 1. Tier-Based Rate Limiting ✓

**Daily Limits:**
- Free: 100 uploads, 1,000 API calls
- Starter: 1,000 uploads, 5,000 API calls
- Pro: 10,000 uploads, 50,000 API calls
- Business/Enterprise: Unlimited

**Implementation:**
- Sliding window algorithm using database
- Per-endpoint tracking
- Automatic cleanup of old records

### 2. Rate Limit Headers ✓

All authenticated responses include:
- `X-RateLimit-Limit`
- `X-RateLimit-Remaining`
- `X-RateLimit-Reset`
- `Retry-After` (when rate limited)

### 3. IP-Based Rate Limiting ✓

**Unauthenticated Endpoints:**
- Login/Register: 10 attempts/hour per IP
- Other endpoints: 100 requests/hour per IP

**IP Detection:**
- Uses Cloudflare's `CF-Connecting-IP` header
- Fallback to `X-Forwarded-For`

### 4. Exponential Backoff ✓

**Failed Login/Register Attempts:**
- Attempts 1-4: No lockout
- Attempt 5: 1-minute lockout
- Attempt 6: 5-minute lockout
- Attempt 7: 15-minute lockout
- Attempt 8: 1-hour lockout
- Attempt 9+: 24-hour lockout

**Auto-Reset:**
- Counters reset after 1 hour of inactivity
- Cleared on successful authentication

### 5. CAPTCHA Integration Support ✓

**Trigger:**
- After 3 failed attempts
- Response includes `requires_captcha: true`

**Note:**
- Framework implemented
- Actual CAPTCHA service (hCaptcha/reCAPTCHA) needs frontend integration

### 6. Content Moderation ✓

**File Validation:**
- MIME type checking
- Magic bytes detection (JPEG, PNG, GIF, WebP)
- Double extension detection
- Executable file blocking

**Malware Scanning:**
- Detects PE (Windows) executables
- Detects ELF (Linux) executables
- Blocks disguised executables
- Confidence scoring for automated decisions

### 7. Abuse Reporting ✓

**Features:**
- Anonymous or authenticated reporting
- Reason categories: NSFW, copyright, malware, spam, other
- Optional description field
- Status tracking: pending, reviewing, resolved, dismissed

**API Endpoint:**
```
POST /api/abuse-report
{
  "image_id": "abc123",
  "reason": "nsfw",
  "description": "Optional details"
}
```

### 8. Unusual Pattern Detection ✓

**Monitors For:**
- High upload rate (>50 uploads/hour)
- Identical file sizes (>10 files same size/day)
- Bot-like behavior (too-consistent intervals)

**Action:**
- Logs warnings
- Flags for review
- Doesn't auto-block (allows legitimate bulk uploads)

### 9. User Suspensions ✓

**Types:**
- Temporary (with end timestamp)
- Permanent (no end date)

**Triggers:**
- Automated: Multiple malware attempts
- Manual: Admin action

**Response:**
- HTTP 403 with suspension details
- Includes reason and expiry

### 10. Monitoring Support ✓

**Metrics Available:**
- Rate limit hits (429 responses)
- Failed login attempts
- Abuse reports (pending/resolved)
- Content flags by type
- Suspicious pattern detections
- Suspension events

## Database Schema

### New Tables

1. **rate_limits**
   - Tracks user-based rate limiting
   - Columns: id, user_id, endpoint, window_start, request_count, timestamps

2. **ip_rate_limits**
   - Tracks IP-based rate limiting
   - Columns: id, ip_address, endpoint, window_start, request_count, timestamps

3. **failed_attempts**
   - Tracks failed login/register attempts
   - Columns: id, identifier, attempt_type, attempt_count, last_attempt_at, locked_until, created_at

4. **abuse_reports**
   - Stores user-submitted reports
   - Columns: id, reported_image_id, reported_user_id, reporter_user_id, reporter_ip, reason, description, status, timestamps, reviewed_by, resolution_notes

5. **content_flags**
   - Automated content flags
   - Columns: id, image_id, flag_type, confidence_score, flagged_by, metadata, created_at

6. **user_suspensions**
   - Active and historical suspensions
   - Columns: id, user_id, reason, suspended_at, suspended_until, suspended_by, notes, is_active

### Indexes

All tables have appropriate indexes for:
- Fast lookups by user_id, ip_address, image_id
- Time-based queries (window_start, created_at)
- Status filtering

## Migration Instructions

### 1. Apply Database Migration

**Local Development:**
```bash
npm run db:migrate:rate-limiting:local
```

**Production:**
```bash
npm run db:migrate:rate-limiting
```

### 2. Deploy Code

```bash
npm run deploy
```

### 3. Verify Deployment

Test the rate limiting:
```bash
# Check rate limit headers
curl -H "Authorization: Bearer YOUR_TOKEN" \
  https://your-api.com/upload \
  -I

# Should see headers:
# X-RateLimit-Limit: 100
# X-RateLimit-Remaining: 99
# X-RateLimit-Reset: 1706486400000
```

## Testing

### Manual Testing

1. **Test Rate Limiting:**
   - Make multiple upload requests
   - Verify rate limit headers
   - Exceed limit and check 429 response

2. **Test Failed Logins:**
   - Attempt 3 failed logins
   - Verify `requires_captcha` flag
   - Attempt 5 failed logins
   - Verify lockout with timeout

3. **Test Malware Detection:**
   - Try uploading non-image file
   - Try file with double extension
   - Verify rejection

4. **Test Abuse Reporting:**
   - Submit abuse report for an image
   - Verify report creation

### Automated Testing

```bash
# Install test dependencies (if not already)
npm install -D vitest

# Run tests
npm test
```

## Configuration

### Customizing Rate Limits

Edit `src/rate-limiter.ts`:

```typescript
const tierLimits: Record<string, { uploads: number; api: number }> = {
  free: { uploads: 100, api: 1000 },
  starter: { uploads: 1000, api: 5000 },
  pro: { uploads: 10000, api: 50000 },
  business: { uploads: 999999, api: 999999 },
  enterprise: { uploads: 999999, api: 999999 },
};
```

### Customizing Lockout Schedule

Edit `recordFailedAttempt()` in `src/rate-limiter.ts`:

```typescript
// Current: 1, 5, 15, 60, 1440 minutes
const lockoutMinutes = [1, 5, 15, 60, 1440][Math.min(newCount - 5, 4)];
```

## Monitoring Setup

### CloudflareWorkers Analytics

Monitor these metrics in Cloudflare dashboard:
- Request rate by endpoint
- 429 response rate
- Error rate

### Custom Alerts (Recommended)

Set up alerts for:
1. High 429 rate (>10% of requests)
2. Multiple malware detections from single user
3. Pending abuse reports >50
4. Unusual suspension spike

### Database Queries for Monitoring

```sql
-- Failed login attempts in last hour
SELECT COUNT(*) FROM failed_attempts
WHERE last_attempt_at > (unixepoch() * 1000) - 3600000;

-- Pending abuse reports
SELECT COUNT(*) FROM abuse_reports
WHERE status = 'pending';

-- Active suspensions
SELECT COUNT(*) FROM user_suspensions
WHERE is_active = 1;

-- Top rate-limited users (current window)
SELECT user_id, endpoint, request_count
FROM rate_limits
WHERE window_start > (unixepoch() * 1000) - 86400000
ORDER BY request_count DESC
LIMIT 10;
```

## Maintenance Tasks

### Regular Cleanup (Recommended Cron Jobs)

```typescript
// Daily cleanup job
async function dailyMaintenance(env: Env) {
  const db = new Database(env.DB);
  const rateLimiter = new RateLimiter(env.DB);

  // Clean up old rate limit records (keep 24 hours)
  await rateLimiter.cleanupOldRateLimits(24);

  // Clean up old API usage logs (keep 30 days)
  await db.cleanupOldApiUsage(30);

  // Clean up expired exports
  await db.cleanupExpiredExports();
}
```

## Security Considerations

1. **IP Spoofing Protection:**
   - Trust Cloudflare headers only
   - Validate IP format

2. **Rate Limit Bypass:**
   - Monitor for users creating multiple accounts
   - Consider email verification

3. **Database Performance:**
   - Indexes ensure fast queries
   - Cleanup jobs prevent table bloat

4. **False Positives:**
   - Low-confidence flags don't block uploads
   - Manual review process for suspensions

## Future Enhancements

### Short Term (Recommended)
1. Email notifications for suspensions
2. Admin dashboard for reviewing reports
3. Webhook notifications for critical events

### Medium Term
1. CAPTCHA service integration (hCaptcha/reCAPTCHA)
2. Email verification for registrations
3. Geolocation-based restrictions

### Long Term
1. NSFW detection API integration
2. Advanced malware scanning (VirusTotal)
3. Copyright detection (image fingerprinting)
4. Reputation scoring system

## API Changes

### New Endpoint

- `POST /api/abuse-report` - Submit abuse report

### Modified Responses

All authenticated endpoints now include rate limit headers:
```json
{
  "data": "...",
  "headers": {
    "X-RateLimit-Limit": "100",
    "X-RateLimit-Remaining": "95",
    "X-RateLimit-Reset": "1706486400000"
  }
}
```

### New Error Responses

**Rate Limit Exceeded (429):**
```json
{
  "error": "Rate limit exceeded",
  "retry_after": "2024-01-28T12:00:00.000Z"
}
```

**Account Locked (429):**
```json
{
  "error": "Account temporarily locked",
  "locked_until": 1706486400000,
  "retry_in_minutes": 5,
  "requires_captcha": true
}
```

**Account Suspended (403):**
```json
{
  "error": "Account suspended",
  "reason": "Multiple policy violations",
  "suspended_until": 1706486400000
}
```

## Compliance

### GDPR Considerations

- IP addresses stored for abuse prevention (legitimate interest)
- User IDs in abuse reports (necessary for service operation)
- Provide data export for user data
- Implement right to deletion (cascade deletes in place)

### Terms of Service

Update ToS to include:
- Rate limiting policy
- Acceptable use policy
- Content moderation rules
- Suspension appeal process

## Support

### Common Issues

1. **User locked out legitimately:**
   - Clear failed attempts manually in database
   - Reset: `DELETE FROM failed_attempts WHERE identifier = 'user@email.com'`

2. **False malware detection:**
   - Review content_flags table
   - Whitelist legitimate file types if needed

3. **Rate limit too strict:**
   - Consider upgrading user's tier
   - Adjust limits in configuration

### Admin Tools (Future)

Create admin commands for:
- Clearing failed attempts
- Removing suspensions
- Reviewing flagged content
- Adjusting rate limits per user

## Conclusion

The rate limiting and abuse prevention system is now fully implemented with:

- ✅ Tier-based rate limiting (100-unlimited per day)
- ✅ Rate limit headers on all responses
- ✅ IP-based rate limiting for auth endpoints
- ✅ Exponential backoff for failed attempts
- ✅ CAPTCHA support framework
- ✅ Content moderation (file validation & malware scanning)
- ✅ Abuse reporting mechanism
- ✅ Unusual pattern detection
- ✅ User suspension system
- ✅ Comprehensive documentation
- ✅ Database schema with proper indexes
- ✅ Test suite

The system is production-ready and provides robust protection against abuse while maintaining a good user experience for legitimate users.
