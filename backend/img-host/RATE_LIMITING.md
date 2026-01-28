# Rate Limiting and Abuse Prevention

This document describes the rate limiting and abuse prevention features implemented in the imghost API.

## Overview

The system implements comprehensive rate limiting and abuse prevention mechanisms to ensure fair usage, prevent spam, and protect against malicious actors.

## Rate Limiting

### Tier-Based Rate Limits

Rate limits are enforced per subscription tier with the following daily limits:

| Tier       | Daily Uploads | Daily API Calls |
|------------|---------------|-----------------|
| Free       | 100           | 1,000           |
| Starter    | 1,000         | 5,000           |
| Pro        | 10,000        | 50,000          |
| Business   | Unlimited     | Unlimited       |
| Enterprise | Unlimited     | Unlimited       |

### Rate Limit Headers

All authenticated API responses include rate limit headers:

```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1706486400000
```

When rate limit is exceeded, the API returns HTTP 429 with:

```json
{
  "error": "Rate limit exceeded",
  "retry_after": "2024-01-28T12:00:00.000Z"
}
```

### IP-Based Rate Limiting

Unauthenticated endpoints use IP-based rate limiting:

- **Registration/Login**: 10 attempts per hour per IP
- **Other endpoints**: 100 requests per hour per IP

## Failed Login Protection

### Exponential Backoff

The system implements exponential backoff for failed login/registration attempts:

1. **Attempts 1-4**: No lockout, warning only
2. **Attempt 5**: 1-minute lockout
3. **Attempt 6**: 5-minute lockout
4. **Attempt 7**: 15-minute lockout
5. **Attempt 8**: 1-hour lockout
6. **Attempt 9+**: 24-hour lockout

### CAPTCHA Requirement

After 3 failed attempts, the API response includes `requires_captcha: true`, indicating that the client should present a CAPTCHA challenge before the next attempt.

```json
{
  "error": "Too many failed attempts",
  "locked_until": 1706486400000,
  "retry_in_minutes": 5,
  "requires_captcha": true
}
```

### Auto-Reset

Failed attempt counters automatically reset after 1 hour of inactivity.

## Content Moderation

### File Type Validation

The system performs multi-layer file validation:

1. **MIME Type Check**: Validates the Content-Type header
2. **Magic Bytes Detection**: Reads file signatures to detect actual file type
3. **Extension Validation**: Checks for suspicious double extensions (e.g., `.jpg.exe`)
4. **Executable Detection**: Blocks files with executable magic bytes

### Malware Scanning

Basic malware detection checks for:

- Executable files disguised as images
- Suspicious file extensions
- Double extensions (common malware technique)
- PE (Windows) and ELF (Linux) executable headers

High-confidence malware detections (≥0.8 confidence) result in immediate upload rejection.

### Abuse Pattern Detection

The system monitors for unusual upload patterns:

- **High Upload Rate**: More than 50 uploads in one hour
- **Identical File Sizes**: More than 10 files with identical size in 24 hours
- **Bot-Like Behavior**: Too-consistent upload intervals (within 1 second)

Suspicious patterns are logged and flagged for review but don't automatically block uploads.

## Abuse Reporting

### Submit Abuse Report

Users can report abusive content:

```bash
POST /api/abuse-report
Authorization: Bearer <token>  # Optional - reports can be anonymous

{
  "image_id": "abc12345",
  "reason": "nsfw",  # nsfw | copyright | malware | spam | other
  "description": "Optional detailed description"
}
```

### Abuse Report Status

- **pending**: Newly submitted, awaiting review
- **reviewing**: Under active review by moderators
- **resolved**: Issue resolved (content removed or warning issued)
- **dismissed**: Report found to be invalid

## User Suspensions

### Automatic Suspension

Users can be automatically suspended for:

- Repeated malware upload attempts
- Multiple abuse reports against their content
- Severe policy violations

### Suspension Types

- **Temporary**: Suspended until a specific timestamp
- **Permanent**: `suspended_until` is `null`

### Suspension Response

When a suspended user attempts to access the API:

```json
{
  "error": "Account suspended",
  "reason": "Multiple policy violations",
  "suspended_until": 1706486400000  # null for permanent
}
```

## Database Tables

### rate_limits

Tracks user-based rate limiting per endpoint and time window.

### ip_rate_limits

Tracks IP-based rate limiting for unauthenticated requests.

### failed_attempts

Stores failed login/registration attempts with lockout timestamps.

### abuse_reports

Records user-submitted abuse reports for moderation.

### content_flags

Automated content flags (NSFW, malware, suspicious patterns).

### user_suspensions

Active and historical user suspensions.

## Monitoring and Alerts

### Metrics to Monitor

1. **Rate Limit Hits**: Track 429 responses by tier and endpoint
2. **Failed Logins**: Monitor failed login rates by IP and email
3. **Abuse Reports**: Count pending reports and resolution times
4. **Content Flags**: Track automated flags by type and confidence
5. **Suspicious Patterns**: Alert on unusual upload behavior
6. **Suspensions**: Monitor automatic vs. manual suspensions

### Recommended Alerts

- **High Failed Login Rate**: >100 failed attempts from single IP in 10 minutes
- **Pending Abuse Reports**: >50 unreviewed reports
- **Malware Detections**: Any high-confidence malware detection
- **Suspension Spike**: >10 automatic suspensions in 1 hour

## Cleanup and Maintenance

### Automated Cleanup

Recommended cron jobs or scheduled tasks:

```typescript
// Clean up old rate limit records (keep 24 hours)
await rateLimiter.cleanupOldRateLimits(24);

// Clean up old API usage logs (keep 30 days)
await db.cleanupOldApiUsage(30);

// Clean up expired export jobs
await db.cleanupExpiredExports();
```

### Manual Review Queue

Administrators should regularly review:

1. Pending abuse reports
2. Content flags with high confidence scores
3. Suspended accounts for potential reinstatement

## API Integration Examples

### Handling Rate Limits (Client)

```typescript
async function uploadImage(file: File, apiToken: string) {
  const formData = new FormData();
  formData.append('image', file);

  const response = await fetch('https://api.example.com/upload', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${apiToken}`,
    },
    body: formData,
  });

  // Check rate limit headers
  const rateLimit = {
    limit: parseInt(response.headers.get('X-RateLimit-Limit') || '0'),
    remaining: parseInt(response.headers.get('X-RateLimit-Remaining') || '0'),
    reset: parseInt(response.headers.get('X-RateLimit-Reset') || '0'),
  };

  if (response.status === 429) {
    const data = await response.json();
    throw new Error(`Rate limit exceeded. Retry after: ${data.retry_after}`);
  }

  return { data: await response.json(), rateLimit };
}
```

### Handling Failed Logins (Client)

```typescript
async function login(email: string, password: string) {
  const response = await fetch('https://api.example.com/auth/login', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });

  if (response.status === 429) {
    const data = await response.json();
    if (data.requires_captcha) {
      // Show CAPTCHA challenge
      return { requiresCaptcha: true, lockedUntil: data.locked_until };
    }
    throw new Error(`Account locked. Retry in ${data.retry_in_minutes} minutes`);
  }

  if (!response.ok) {
    throw new Error('Invalid credentials');
  }

  return response.json();
}
```

## Configuration

### Environment Variables

No additional environment variables are required. Rate limits are configured in code based on subscription tiers.

### Customizing Rate Limits

Edit `src/rate-limiter.ts` to modify rate limit configurations:

```typescript
const tierLimits: Record<string, { uploads: number; api: number }> = {
  free: { uploads: 100, api: 1000 },
  starter: { uploads: 1000, api: 5000 },
  pro: { uploads: 10000, api: 50000 },
  // ...
};
```

## Future Enhancements

Potential improvements for future iterations:

1. **CAPTCHA Integration**: Integrate with hCaptcha or reCAPTCHA
2. **NSFW Detection**: Integrate with external NSFW detection APIs
3. **Advanced Malware Scanning**: Integrate with VirusTotal or similar
4. **Copyright Detection**: Image fingerprinting for copyright claims
5. **Geolocation Blocking**: Block uploads from high-risk countries
6. **Reputation Scoring**: Automatic scoring based on user behavior
7. **Admin Dashboard**: Web UI for reviewing reports and flags
8. **Webhook Notifications**: Alert admins of critical events

## Security Considerations

1. **IP Spoofing**: Trust Cloudflare headers (`CF-Connecting-IP`) for accurate IP detection
2. **Token Leakage**: Rate limits are per-user, so compromised tokens affect only that user
3. **Bypass Attempts**: Monitor for users creating multiple accounts to bypass limits
4. **DoS Protection**: Cloudflare's DDoS protection provides additional layer
5. **Data Privacy**: Store minimal PII in abuse reports and logs

## Support

For questions or issues related to rate limiting and abuse prevention:

1. Check logs in Cloudflare Workers dashboard
2. Review database records for failed attempts and flags
3. Contact support with user ID and timestamp for investigation
