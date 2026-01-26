// Analytics tracking and metrics calculation

export interface DailyMetrics {
  date: string;
  total_uploads: number;
  total_bytes_uploaded: number;
  total_deletions: number;
  new_users: number;
  active_users: number;
  total_api_calls: number;
  created_at: number;
}

export interface ImageFormatStats {
  id: string;
  date: string;
  content_type: string;
  upload_count: number;
  total_bytes: number;
  avg_size_bytes: number;
  created_at: number;
}

export interface UserEngagement {
  id: string;
  user_id: string;
  date: string;
  uploads_count: number;
  deletions_count: number;
  api_calls_count: number;
  last_activity_timestamp: number;
}

export interface SubscriptionEvent {
  id: string;
  user_id: string;
  event_type: 'signup' | 'upgrade' | 'downgrade' | 'cancel' | 'reactivate' | 'churn';
  from_tier: string | null;
  to_tier: string;
  timestamp: number;
}

export interface RevenueMetrics {
  month: string;
  mrr: number;
  arr: number;
  new_mrr: number;
  expansion_mrr: number;
  contraction_mrr: number;
  churned_mrr: number;
  active_subscriptions: number;
  free_users: number;
  pro_users: number;
  enterprise_users: number;
  created_at: number;
  updated_at: number;
}

export interface StorageSnapshot {
  id: string;
  date: string;
  total_users: number;
  total_images: number;
  total_bytes_stored: number;
  avg_bytes_per_user: number;
  avg_images_per_user: number;
  created_at: number;
}

export interface FeatureUsage {
  id: string;
  user_id: string;
  feature_name: string;
  usage_count: number;
  first_used_at: number;
  last_used_at: number;
}

export interface PrivacySettings {
  user_id: string;
  analytics_enabled: boolean;
  data_retention_days: number;
  updated_at: number;
}

export interface UserAnalyticsSummary {
  user_id: string;
  total_uploads: number;
  total_bytes_uploaded: number;
  total_deletions: number;
  storage_used_bytes: number;
  storage_limit_bytes: number;
  image_count: number;
  avg_image_size: number;
  most_common_format: string | null;
  account_age_days: number;
  subscription_tier: string;
  uploads_last_30_days: number;
}

export interface SystemAnalyticsSummary {
  total_users: number;
  active_users_today: number;
  active_users_7d: number;
  active_users_30d: number;
  total_images: number;
  total_bytes_stored: number;
  uploads_today: number;
  uploads_7d: number;
  uploads_30d: number;
  avg_upload_size: number;
  subscription_distribution: {
    free: number;
    pro: number;
    enterprise: number;
  };
  top_formats: Array<{ format: string; count: number; percentage: number }>;
}

export class Analytics {
  constructor(private db: D1Database) {}

  // Get current date in YYYY-MM-DD format
  private getDateString(timestamp?: number): string {
    const date = timestamp ? new Date(timestamp) : new Date();
    return date.toISOString().split('T')[0];
  }

  // Get current month in YYYY-MM format
  private getMonthString(timestamp?: number): string {
    const date = timestamp ? new Date(timestamp) : new Date();
    return date.toISOString().slice(0, 7);
  }

  // Check if user has analytics enabled (GDPR compliance)
  async isAnalyticsEnabled(userId: string): Promise<boolean> {
    const result = await this.db
      .prepare('SELECT analytics_enabled FROM analytics_privacy_settings WHERE user_id = ?')
      .bind(userId)
      .first<{ analytics_enabled: number }>();

    // Default to enabled if no preference set
    return result ? result.analytics_enabled === 1 : true;
  }

  // Track image upload
  async trackUpload(userId: string, sizeBytes: number, contentType: string): Promise<void> {
    if (!await this.isAnalyticsEnabled(userId)) return;

    const date = this.getDateString();
    const timestamp = Date.now();

    // Update daily metrics
    await this.db
      .prepare(`
        INSERT INTO analytics_daily_metrics (date, total_uploads, total_bytes_uploaded, total_deletions, new_users, active_users, total_api_calls, created_at)
        VALUES (?, 1, ?, 0, 0, 0, 0, ?)
        ON CONFLICT(date) DO UPDATE SET
          total_uploads = total_uploads + 1,
          total_bytes_uploaded = total_bytes_uploaded + ?
      `)
      .bind(date, sizeBytes, timestamp, sizeBytes)
      .run();

    // Update format statistics
    const formatId = crypto.randomUUID();
    await this.db
      .prepare(`
        INSERT INTO analytics_image_formats (id, date, content_type, upload_count, total_bytes, avg_size_bytes, created_at)
        VALUES (?, ?, ?, 1, ?, ?, ?)
        ON CONFLICT(date, content_type) DO UPDATE SET
          upload_count = upload_count + 1,
          total_bytes = total_bytes + ?,
          avg_size_bytes = (total_bytes + ?) / (upload_count + 1)
      `)
      .bind(formatId, date, contentType, sizeBytes, sizeBytes, timestamp, sizeBytes, sizeBytes)
      .run();

    // Update user engagement
    const engagementId = crypto.randomUUID();
    await this.db
      .prepare(`
        INSERT INTO analytics_user_engagement (id, user_id, date, uploads_count, deletions_count, api_calls_count, last_activity_timestamp)
        VALUES (?, ?, ?, 1, 0, 0, ?)
        ON CONFLICT(user_id, date) DO UPDATE SET
          uploads_count = uploads_count + 1,
          last_activity_timestamp = ?
      `)
      .bind(engagementId, userId, date, timestamp, timestamp)
      .run();
  }

  // Track image deletion
  async trackDeletion(userId: string): Promise<void> {
    if (!await this.isAnalyticsEnabled(userId)) return;

    const date = this.getDateString();
    const timestamp = Date.now();

    // Update daily metrics
    await this.db
      .prepare(`
        INSERT INTO analytics_daily_metrics (date, total_uploads, total_bytes_uploaded, total_deletions, new_users, active_users, total_api_calls, created_at)
        VALUES (?, 0, 0, 1, 0, 0, 0, ?)
        ON CONFLICT(date) DO UPDATE SET
          total_deletions = total_deletions + 1
      `)
      .bind(date, timestamp)
      .run();

    // Update user engagement
    const engagementId = crypto.randomUUID();
    await this.db
      .prepare(`
        INSERT INTO analytics_user_engagement (id, user_id, date, uploads_count, deletions_count, api_calls_count, last_activity_timestamp)
        VALUES (?, ?, ?, 0, 1, 0, ?)
        ON CONFLICT(user_id, date) DO UPDATE SET
          deletions_count = deletions_count + 1,
          last_activity_timestamp = ?
      `)
      .bind(engagementId, userId, date, timestamp, timestamp)
      .run();
  }

  // Track new user signup
  async trackSignup(userId: string, tier: string): Promise<void> {
    const date = this.getDateString();
    const timestamp = Date.now();

    // Update daily metrics
    await this.db
      .prepare(`
        INSERT INTO analytics_daily_metrics (date, total_uploads, total_bytes_uploaded, total_deletions, new_users, active_users, total_api_calls, created_at)
        VALUES (?, 0, 0, 0, 1, 0, 0, ?)
        ON CONFLICT(date) DO UPDATE SET
          new_users = new_users + 1
      `)
      .bind(date, timestamp)
      .run();

    // Track subscription event
    const eventId = crypto.randomUUID();
    await this.db
      .prepare(
        'INSERT INTO analytics_subscription_events (id, user_id, event_type, from_tier, to_tier, timestamp) VALUES (?, ?, ?, ?, ?, ?)'
      )
      .bind(eventId, userId, 'signup', null, tier, timestamp)
      .run();
  }

  // Track subscription change
  async trackSubscriptionChange(
    userId: string,
    fromTier: string,
    toTier: string,
    eventType: 'upgrade' | 'downgrade' | 'cancel' | 'reactivate'
  ): Promise<void> {
    const eventId = crypto.randomUUID();
    const timestamp = Date.now();

    await this.db
      .prepare(
        'INSERT INTO analytics_subscription_events (id, user_id, event_type, from_tier, to_tier, timestamp) VALUES (?, ?, ?, ?, ?, ?)'
      )
      .bind(eventId, userId, eventType, fromTier, toTier, timestamp)
      .run();
  }

  // Track feature usage
  async trackFeatureUsage(userId: string, featureName: string): Promise<void> {
    if (!await this.isAnalyticsEnabled(userId)) return;

    const featureId = crypto.randomUUID();
    const timestamp = Date.now();

    await this.db
      .prepare(`
        INSERT INTO analytics_feature_usage (id, user_id, feature_name, usage_count, first_used_at, last_used_at)
        VALUES (?, ?, ?, 1, ?, ?)
        ON CONFLICT(user_id, feature_name) DO UPDATE SET
          usage_count = usage_count + 1,
          last_used_at = ?
      `)
      .bind(featureId, userId, featureName, timestamp, timestamp, timestamp)
      .run();
  }

  // Get user analytics summary
  async getUserAnalytics(userId: string): Promise<UserAnalyticsSummary | null> {
    // Get user info
    const user = await this.db
      .prepare('SELECT * FROM users WHERE id = ?')
      .bind(userId)
      .first<any>();

    if (!user) return null;

    // Get total uploads and bytes
    const uploadStats = await this.db
      .prepare(`
        SELECT
          COUNT(*) as total_uploads,
          COALESCE(SUM(size_bytes), 0) as total_bytes_uploaded
        FROM images
        WHERE user_id = ?
      `)
      .bind(userId)
      .first<{ total_uploads: number; total_bytes_uploaded: number }>();

    // Get recent uploads (last 30 days)
    const thirtyDaysAgo = Date.now() - (30 * 24 * 60 * 60 * 1000);
    const recentUploads = await this.db
      .prepare('SELECT COUNT(*) as count FROM images WHERE user_id = ? AND created_at > ?')
      .bind(userId, thirtyDaysAgo)
      .first<{ count: number }>();

    // Get deletions count
    const deletions = await this.db
      .prepare('SELECT SUM(deletions_count) as total FROM analytics_user_engagement WHERE user_id = ?')
      .bind(userId)
      .first<{ total: number | null }>();

    // Get storage usage
    const storage = await this.db
      .prepare('SELECT * FROM storage_usage WHERE user_id = ?')
      .bind(userId)
      .first<{ image_count: number; total_bytes_used: number }>();

    // Get most common format
    const topFormat = await this.db
      .prepare('SELECT content_type, COUNT(*) as count FROM images WHERE user_id = ? GROUP BY content_type ORDER BY count DESC LIMIT 1')
      .bind(userId)
      .first<{ content_type: string }>();

    const accountAgeDays = Math.floor((Date.now() - user.created_at) / (24 * 60 * 60 * 1000));
    const avgSize = uploadStats && uploadStats.total_uploads > 0
      ? Math.floor(uploadStats.total_bytes_uploaded / uploadStats.total_uploads)
      : 0;

    return {
      user_id: userId,
      total_uploads: uploadStats?.total_uploads || 0,
      total_bytes_uploaded: uploadStats?.total_bytes_uploaded || 0,
      total_deletions: deletions?.total || 0,
      storage_used_bytes: storage?.total_bytes_used || 0,
      storage_limit_bytes: user.storage_limit_bytes,
      image_count: storage?.image_count || 0,
      avg_image_size: avgSize,
      most_common_format: topFormat?.content_type || null,
      account_age_days: accountAgeDays,
      subscription_tier: user.subscription_tier,
      uploads_last_30_days: recentUploads?.count || 0,
    };
  }

  // Get system-wide analytics
  async getSystemAnalytics(): Promise<SystemAnalyticsSummary> {
    const today = this.getDateString();
    const sevenDaysAgo = this.getDateString(Date.now() - 7 * 24 * 60 * 60 * 1000);
    const thirtyDaysAgo = this.getDateString(Date.now() - 30 * 24 * 60 * 60 * 1000);

    // Total users
    const totalUsers = await this.db
      .prepare('SELECT COUNT(*) as count FROM users')
      .first<{ count: number }>();

    // Active users
    const activeToday = await this.db
      .prepare('SELECT COUNT(DISTINCT user_id) as count FROM analytics_user_engagement WHERE date = ?')
      .bind(today)
      .first<{ count: number }>();

    const active7d = await this.db
      .prepare('SELECT COUNT(DISTINCT user_id) as count FROM analytics_user_engagement WHERE date >= ?')
      .bind(sevenDaysAgo)
      .first<{ count: number }>();

    const active30d = await this.db
      .prepare('SELECT COUNT(DISTINCT user_id) as count FROM analytics_user_engagement WHERE date >= ?')
      .bind(thirtyDaysAgo)
      .first<{ count: number }>();

    // Total images and storage
    const imageStats = await this.db
      .prepare('SELECT COUNT(*) as total_images, COALESCE(SUM(size_bytes), 0) as total_bytes FROM images')
      .first<{ total_images: number; total_bytes: number }>();

    // Uploads by time period
    const uploadsToday = await this.db
      .prepare('SELECT COALESCE(SUM(total_uploads), 0) as count FROM analytics_daily_metrics WHERE date = ?')
      .bind(today)
      .first<{ count: number }>();

    const uploads7d = await this.db
      .prepare('SELECT COALESCE(SUM(total_uploads), 0) as count FROM analytics_daily_metrics WHERE date >= ?')
      .bind(sevenDaysAgo)
      .first<{ count: number }>();

    const uploads30d = await this.db
      .prepare('SELECT COALESCE(SUM(total_uploads), 0) as count FROM analytics_daily_metrics WHERE date >= ?')
      .bind(thirtyDaysAgo)
      .first<{ count: number }>();

    // Subscription distribution
    const subDistribution = await this.db
      .prepare('SELECT subscription_tier, COUNT(*) as count FROM users GROUP BY subscription_tier')
      .all<{ subscription_tier: string; count: number }>();

    const distribution = {
      free: 0,
      pro: 0,
      enterprise: 0,
    };

    subDistribution.results?.forEach(row => {
      if (row.subscription_tier in distribution) {
        distribution[row.subscription_tier as keyof typeof distribution] = row.count;
      }
    });

    // Top formats
    const topFormats = await this.db
      .prepare('SELECT content_type, COUNT(*) as count FROM images GROUP BY content_type ORDER BY count DESC LIMIT 5')
      .all<{ content_type: string; count: number }>();

    const totalImagesForPercentage = imageStats?.total_images || 0;
    const topFormatsWithPercentage = (topFormats.results || []).map(f => ({
      format: f.content_type,
      count: f.count,
      percentage: totalImagesForPercentage > 0 ? (f.count / totalImagesForPercentage) * 100 : 0,
    }));

    const avgUploadSize = imageStats && imageStats.total_images > 0
      ? Math.floor(imageStats.total_bytes / imageStats.total_images)
      : 0;

    return {
      total_users: totalUsers?.count || 0,
      active_users_today: activeToday?.count || 0,
      active_users_7d: active7d?.count || 0,
      active_users_30d: active30d?.count || 0,
      total_images: imageStats?.total_images || 0,
      total_bytes_stored: imageStats?.total_bytes || 0,
      uploads_today: uploadsToday?.count || 0,
      uploads_7d: uploads7d?.count || 0,
      uploads_30d: uploads30d?.count || 0,
      avg_upload_size: avgUploadSize,
      subscription_distribution: distribution,
      top_formats: topFormatsWithPercentage,
    };
  }

  // Update or set privacy settings
  async updatePrivacySettings(
    userId: string,
    analyticsEnabled: boolean,
    dataRetentionDays: number = 90
  ): Promise<void> {
    const timestamp = Date.now();

    await this.db
      .prepare(`
        INSERT INTO analytics_privacy_settings (user_id, analytics_enabled, data_retention_days, updated_at)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(user_id) DO UPDATE SET
          analytics_enabled = ?,
          data_retention_days = ?,
          updated_at = ?
      `)
      .bind(
        userId,
        analyticsEnabled ? 1 : 0,
        dataRetentionDays,
        timestamp,
        analyticsEnabled ? 1 : 0,
        dataRetentionDays,
        timestamp
      )
      .run();
  }

  // Cleanup old analytics data based on retention policy
  async cleanupOldData(userId: string): Promise<void> {
    const settings = await this.db
      .prepare('SELECT data_retention_days FROM analytics_privacy_settings WHERE user_id = ?')
      .bind(userId)
      .first<{ data_retention_days: number }>();

    const retentionDays = settings?.data_retention_days || 90;
    const cutoffTimestamp = Date.now() - (retentionDays * 24 * 60 * 60 * 1000);

    // Clean up user engagement data
    await this.db
      .prepare('DELETE FROM analytics_user_engagement WHERE user_id = ? AND last_activity_timestamp < ?')
      .bind(userId, cutoffTimestamp)
      .run();

    // Clean up feature usage data
    await this.db
      .prepare('DELETE FROM analytics_feature_usage WHERE user_id = ? AND last_used_at < ?')
      .bind(userId, cutoffTimestamp)
      .run();
  }

  // Generate daily storage snapshot (should be run via cron)
  async generateStorageSnapshot(): Promise<void> {
    const date = this.getDateString();
    const timestamp = Date.now();

    const stats = await this.db
      .prepare(`
        SELECT
          COUNT(DISTINCT user_id) as total_users,
          COUNT(*) as total_images,
          COALESCE(SUM(size_bytes), 0) as total_bytes
        FROM images
      `)
      .first<{ total_users: number; total_images: number; total_bytes: number }>();

    const avgBytesPerUser = stats && stats.total_users > 0
      ? Math.floor(stats.total_bytes / stats.total_users)
      : 0;
    const avgImagesPerUser = stats && stats.total_users > 0
      ? Math.floor(stats.total_images / stats.total_users)
      : 0;

    const id = crypto.randomUUID();
    await this.db
      .prepare(`
        INSERT OR REPLACE INTO analytics_storage_snapshots
        (id, date, total_users, total_images, total_bytes_stored, avg_bytes_per_user, avg_images_per_user, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      `)
      .bind(
        id,
        date,
        stats?.total_users || 0,
        stats?.total_images || 0,
        stats?.total_bytes || 0,
        avgBytesPerUser,
        avgImagesPerUser,
        timestamp
      )
      .run();
  }

  // Calculate and update active users for today
  async updateActiveUsers(): Promise<void> {
    const date = this.getDateString();
    const timestamp = Date.now();

    const activeCount = await this.db
      .prepare('SELECT COUNT(DISTINCT user_id) as count FROM analytics_user_engagement WHERE date = ?')
      .bind(date)
      .first<{ count: number }>();

    await this.db
      .prepare(`
        INSERT INTO analytics_daily_metrics (date, total_uploads, total_bytes_uploaded, total_deletions, new_users, active_users, total_api_calls, created_at)
        VALUES (?, 0, 0, 0, 0, ?, 0, ?)
        ON CONFLICT(date) DO UPDATE SET
          active_users = ?
      `)
      .bind(date, activeCount?.count || 0, timestamp, activeCount?.count || 0)
      .run();
  }
}
