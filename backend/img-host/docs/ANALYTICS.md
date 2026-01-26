# Analytics and Usage Tracking

This document describes the analytics and usage tracking system implemented in the image hosting service.

## Overview

The analytics system tracks user behavior, system metrics, and business KPIs to inform product decisions and monitor system health. All analytics are GDPR-compliant with user opt-out options and configurable data retention.

## Features

### 1. Automatic Event Tracking

The system automatically tracks:

- **Image Uploads**: Count, size, format, user
- **Image Deletions**: Count, user
- **User Signups**: New user registrations
- **Subscription Changes**: Upgrades, downgrades, cancellations
- **API Usage**: Endpoint calls, response status

### 2. User Analytics

Users can view their personal usage statistics via `/analytics/user`:

```json
{
  "user_id": "abc123",
  "total_uploads": 150,
  "total_bytes_uploaded": 52428800,
  "total_deletions": 5,
  "storage_used_bytes": 48234567,
  "storage_limit_bytes": 104857600,
  "image_count": 145,
  "avg_image_size": 332164,
  "most_common_format": "image/png",
  "account_age_days": 45,
  "subscription_tier": "free",
  "uploads_last_30_days": 32
}
```

### 3. System Analytics

Administrators can view system-wide metrics via `/analytics/system`:

```json
{
  "total_users": 1250,
  "active_users_today": 87,
  "active_users_7d": 234,
  "active_users_30d": 678,
  "total_images": 45623,
  "total_bytes_stored": 5368709120,
  "uploads_today": 145,
  "uploads_7d": 892,
  "uploads_30d": 3421,
  "avg_upload_size": 117684,
  "subscription_distribution": {
    "free": 1180,
    "pro": 65,
    "enterprise": 5
  },
  "top_formats": [
    { "format": "image/png", "count": 23456, "percentage": 51.4 },
    { "format": "image/jpeg", "count": 18234, "percentage": 40.0 },
    { "format": "image/webp", "count": 3933, "percentage": 8.6 }
  ]
}
```

### 4. Privacy Controls (GDPR Compliance)

Users can control their analytics settings via `/analytics/privacy`:

```http
PUT /analytics/privacy
Authorization: Bearer <api_token>
Content-Type: application/json

{
  "analytics_enabled": false,
  "data_retention_days": 30
}
```

When analytics are disabled:
- No new analytics events are tracked for that user
- Existing data is retained according to retention policy
- System-level aggregates may still include historical data

## API Endpoints

### GET /analytics/user

Get personal analytics for the authenticated user.

**Authentication**: Required (Bearer token)

**Response**: User analytics summary (see example above)

### GET /analytics/system

Get system-wide analytics (admin only).

**Authentication**: Required (Bearer token + admin role)

**Response**: System analytics summary (see example above)

### PUT /analytics/privacy

Update analytics privacy settings.

**Authentication**: Required (Bearer token)

**Request Body**:
```json
{
  "analytics_enabled": boolean,
  "data_retention_days": number (default: 90)
}
```

**Response**:
```json
{
  "user_id": "abc123",
  "analytics_enabled": false,
  "data_retention_days": 30,
  "message": "Privacy settings updated successfully"
}
```

## Database Schema

### Analytics Tables

1. **analytics_daily_metrics**: Daily aggregated system metrics
2. **analytics_image_formats**: Image format statistics by day
3. **analytics_user_engagement**: Per-user daily activity
4. **analytics_subscription_events**: Subscription lifecycle events
5. **analytics_revenue_metrics**: Monthly revenue and MRR tracking
6. **analytics_storage_snapshots**: Daily storage growth snapshots
7. **analytics_feature_usage**: Feature adoption per user
8. **analytics_privacy_settings**: User privacy preferences

See `/backend/img-host/schema.sql` for full schema definitions.

## Metrics Tracked

### User Engagement
- **DAU/MAU**: Daily and monthly active users
- **Upload frequency**: Images uploaded per user per day
- **Retention**: User activity over time

### Storage Metrics
- **Total storage used**: Across all users
- **Average storage per user**: By tier
- **Storage growth rate**: Daily/weekly/monthly trends

### Subscription Metrics
- **Conversion funnel**: Free → Pro → Enterprise
- **Churn rate**: Cancellations per month
- **Tier distribution**: Users per subscription tier

### Image Metrics
- **Upload volume**: Count and total bytes
- **Popular formats**: PNG, JPEG, WebP, etc.
- **Average file size**: By format and tier

### Revenue Metrics (Future)
- **MRR**: Monthly Recurring Revenue
- **ARR**: Annual Recurring Revenue
- **Expansion/Contraction**: Upgrade/downgrade impact
- **Churn**: Revenue lost to cancellations

## Background Jobs

The analytics system includes several maintenance tasks that should run periodically:

### Daily Jobs (via Cloudflare Cron Triggers)

1. **Update Active Users**:
   ```typescript
   await analytics.updateActiveUsers();
   ```

2. **Generate Storage Snapshot**:
   ```typescript
   await analytics.generateStorageSnapshot();
   ```

3. **Cleanup Old Data**:
   ```typescript
   // Run for users with custom retention policies
   await analytics.cleanupOldData(userId);
   ```

### Example Cron Configuration

Add to `wrangler.toml`:

```toml
[triggers]
crons = ["0 0 * * *"] # Run daily at midnight UTC
```

Implement in a scheduled handler:

```typescript
export default {
  async scheduled(event: ScheduledEvent, env: Env, ctx: ExecutionContext) {
    const analytics = new Analytics(env.DB);

    // Update daily metrics
    await analytics.updateActiveUsers();
    await analytics.generateStorageSnapshot();

    // Cleanup old data for users with custom retention
    // This would need to iterate through users with custom settings
  }
}
```

## Privacy and Compliance

### GDPR Compliance

1. **User Consent**: Analytics are opt-in by default but users can disable
2. **Data Minimization**: Only essential metrics are tracked
3. **Right to Erasure**: User data is deleted when account is deleted (CASCADE)
4. **Data Retention**: Configurable retention period per user (default: 90 days)
5. **Transparency**: Clear documentation of what data is collected

### Data Retention

Default retention: **90 days**

Users can configure custom retention (30-365 days):
- Lower retention = better privacy
- Higher retention = better long-term analytics

Automated cleanup runs daily to remove expired data.

### Anonymization

- System-level aggregates do not include PII
- Individual user data is only accessible to that user
- Admin analytics show aggregates, not individual users

## Future Enhancements

1. **Real-time Dashboards**: WebSocket-based live metrics
2. **Custom Reports**: User-defined date ranges and filters
3. **Export Analytics**: CSV/JSON export of user data
4. **A/B Testing**: Feature flag tracking and conversion metrics
5. **Cohort Analysis**: User behavior by signup date/tier
6. **Funnel Visualization**: Signup → Upload → Paid conversion
7. **Alerts**: Anomaly detection and threshold alerts
8. **Integration**: PostHog, Mixpanel, or similar analytics platforms

## Example Queries

### Get most active users (last 30 days)

```sql
SELECT user_id, SUM(uploads_count) as total_uploads
FROM analytics_user_engagement
WHERE date >= date('now', '-30 days')
GROUP BY user_id
ORDER BY total_uploads DESC
LIMIT 10;
```

### Get subscription conversion rate

```sql
SELECT
  COUNT(CASE WHEN event_type = 'signup' THEN 1 END) as signups,
  COUNT(CASE WHEN event_type = 'upgrade' THEN 1 END) as upgrades,
  CAST(COUNT(CASE WHEN event_type = 'upgrade' THEN 1 END) AS FLOAT) /
    NULLIF(COUNT(CASE WHEN event_type = 'signup' THEN 1 END), 0) * 100 as conversion_rate
FROM analytics_subscription_events
WHERE timestamp >= strftime('%s', 'now', '-30 days') * 1000;
```

### Get storage growth trend

```sql
SELECT date, total_bytes_stored
FROM analytics_storage_snapshots
WHERE date >= date('now', '-30 days')
ORDER BY date ASC;
```

## Testing

Basic tests are included in `/backend/img-host/tests/analytics.test.ts`.

To run tests:
```bash
npm test
```

For integration testing, use the provided API endpoints with a test database.

## Support

For questions or issues related to analytics, please contact the development team or file an issue in the repository.
