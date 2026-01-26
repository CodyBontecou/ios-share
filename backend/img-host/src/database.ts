// Database utilities and types for D1

export interface User {
  id: string;
  email: string;
  password_hash: string;
  created_at: number;
  subscription_tier: 'free' | 'pro' | 'enterprise';
  api_token: string;
  storage_limit_bytes: number;
}

export interface Image {
  id: string;
  user_id: string;
  r2_key: string;
  filename: string;
  size_bytes: number;
  content_type: string;
  created_at: number;
  delete_token: string;
}

export interface Subscription {
  id: string;
  user_id: string;
  tier: 'free' | 'pro' | 'enterprise';
  status: 'active' | 'cancelled' | 'past_due' | 'trialing';
  stripe_customer_id?: string;
  stripe_subscription_id?: string;
  current_period_start?: number;
  current_period_end?: number;
  cancel_at_period_end: boolean;
  created_at: number;
  updated_at: number;
}

export interface StorageUsage {
  user_id: string;
  image_count: number;
  total_bytes_used: number;
}

export interface TierLimits {
  tier: string;
  storage_limit_bytes: number;
  max_file_size_bytes: number;
  max_images: number | null;
  features: string; // JSON string
}

export class Database {
  constructor(private db: D1Database) {}

  // User operations
  async createUser(
    email: string,
    passwordHash: string,
    apiToken: string,
    tier: 'free' | 'pro' | 'enterprise' = 'free'
  ): Promise<User> {
    const id = crypto.randomUUID();
    const createdAt = Date.now();
    const storageLimitBytes = tier === 'free' ? 104857600 : tier === 'pro' ? 10737418240 : 107374182400;

    await this.db
      .prepare(
        `INSERT INTO users (id, email, password_hash, created_at, subscription_tier, api_token, storage_limit_bytes)
         VALUES (?, ?, ?, ?, ?, ?, ?)`
      )
      .bind(id, email, passwordHash, createdAt, tier, apiToken, storageLimitBytes)
      .run();

    return {
      id,
      email,
      password_hash: passwordHash,
      created_at: createdAt,
      subscription_tier: tier,
      api_token: apiToken,
      storage_limit_bytes: storageLimitBytes,
    };
  }

  async getUserByEmail(email: string): Promise<User | null> {
    const result = await this.db
      .prepare('SELECT * FROM users WHERE email = ?')
      .bind(email)
      .first<User>();
    return result || null;
  }

  async getUserByApiToken(apiToken: string): Promise<User | null> {
    const result = await this.db
      .prepare('SELECT * FROM users WHERE api_token = ?')
      .bind(apiToken)
      .first<User>();
    return result || null;
  }

  async getUserById(id: string): Promise<User | null> {
    const result = await this.db
      .prepare('SELECT * FROM users WHERE id = ?')
      .bind(id)
      .first<User>();
    return result || null;
  }

  async updateUserTier(userId: string, tier: 'free' | 'pro' | 'enterprise'): Promise<void> {
    const storageLimitBytes = tier === 'free' ? 104857600 : tier === 'pro' ? 10737418240 : 107374182400;
    await this.db
      .prepare('UPDATE users SET subscription_tier = ?, storage_limit_bytes = ? WHERE id = ?')
      .bind(tier, storageLimitBytes, userId)
      .run();
  }

  // Image operations
  async createImage(
    userId: string,
    r2Key: string,
    filename: string,
    sizeBytes: number,
    contentType: string,
    deleteToken: string
  ): Promise<Image> {
    const id = crypto.randomUUID().slice(0, 8);
    const createdAt = Date.now();

    await this.db
      .prepare(
        `INSERT INTO images (id, user_id, r2_key, filename, size_bytes, content_type, created_at, delete_token)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
      )
      .bind(id, userId, r2Key, filename, sizeBytes, contentType, createdAt, deleteToken)
      .run();

    return {
      id,
      user_id: userId,
      r2_key: r2Key,
      filename,
      size_bytes: sizeBytes,
      content_type: contentType,
      created_at: createdAt,
      delete_token: deleteToken,
    };
  }

  async getImageByR2Key(r2Key: string): Promise<Image | null> {
    const result = await this.db
      .prepare('SELECT * FROM images WHERE r2_key = ?')
      .bind(r2Key)
      .first<Image>();
    return result || null;
  }

  async getImageById(id: string): Promise<Image | null> {
    const result = await this.db
      .prepare('SELECT * FROM images WHERE id = ?')
      .bind(id)
      .first<Image>();
    return result || null;
  }

  async getImagesByUserId(userId: string, limit = 100, offset = 0): Promise<Image[]> {
    const result = await this.db
      .prepare('SELECT * FROM images WHERE user_id = ? ORDER BY created_at DESC LIMIT ? OFFSET ?')
      .bind(userId, limit, offset)
      .all<Image>();
    return result.results || [];
  }

  async deleteImage(id: string): Promise<boolean> {
    const result = await this.db
      .prepare('DELETE FROM images WHERE id = ?')
      .bind(id)
      .run();
    return result.success;
  }

  async verifyDeleteToken(id: string, deleteToken: string): Promise<boolean> {
    const result = await this.db
      .prepare('SELECT delete_token FROM images WHERE id = ?')
      .bind(id)
      .first<{ delete_token: string }>();

    return result?.delete_token === deleteToken;
  }

  // Storage usage operations
  async getStorageUsage(userId: string): Promise<StorageUsage> {
    const result = await this.db
      .prepare('SELECT * FROM storage_usage WHERE user_id = ?')
      .bind(userId)
      .first<StorageUsage>();

    return result || { user_id: userId, image_count: 0, total_bytes_used: 0 };
  }

  async checkStorageLimit(userId: string, additionalBytes: number): Promise<boolean> {
    const user = await this.getUserById(userId);
    if (!user) return false;

    const usage = await this.getStorageUsage(userId);
    return (usage.total_bytes_used + additionalBytes) <= user.storage_limit_bytes;
  }

  // Subscription operations
  async createSubscription(
    userId: string,
    tier: 'free' | 'pro' | 'enterprise',
    status: 'active' | 'cancelled' | 'past_due' | 'trialing',
    stripeCustomerId?: string,
    stripeSubscriptionId?: string
  ): Promise<Subscription> {
    const id = crypto.randomUUID();
    const now = Date.now();

    await this.db
      .prepare(
        `INSERT INTO subscriptions (id, user_id, tier, status, stripe_customer_id, stripe_subscription_id, cancel_at_period_end, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?)`
      )
      .bind(id, userId, tier, status, stripeCustomerId || null, stripeSubscriptionId || null, now, now)
      .run();

    return {
      id,
      user_id: userId,
      tier,
      status,
      stripe_customer_id: stripeCustomerId,
      stripe_subscription_id: stripeSubscriptionId,
      cancel_at_period_end: false,
      created_at: now,
      updated_at: now,
    };
  }

  async getSubscriptionByUserId(userId: string): Promise<Subscription | null> {
    const result = await this.db
      .prepare('SELECT * FROM subscriptions WHERE user_id = ?')
      .bind(userId)
      .first<Subscription>();
    return result || null;
  }

  async updateSubscriptionStatus(
    userId: string,
    status: 'active' | 'cancelled' | 'past_due' | 'trialing'
  ): Promise<void> {
    const now = Date.now();
    await this.db
      .prepare('UPDATE subscriptions SET status = ?, updated_at = ? WHERE user_id = ?')
      .bind(status, now, userId)
      .run();
  }

  // Tier limits operations
  async getTierLimits(tier: string): Promise<TierLimits | null> {
    const result = await this.db
      .prepare('SELECT * FROM tier_limits WHERE tier = ?')
      .bind(tier)
      .first<TierLimits>();
    return result || null;
  }

  // API usage tracking
  async logApiUsage(
    userId: string,
    endpoint: string,
    method: string,
    responseStatus: number
  ): Promise<void> {
    const id = crypto.randomUUID();
    const timestamp = Date.now();

    await this.db
      .prepare(
        'INSERT INTO api_usage (id, user_id, endpoint, method, timestamp, response_status) VALUES (?, ?, ?, ?, ?, ?)'
      )
      .bind(id, userId, endpoint, method, timestamp, responseStatus)
      .run();
  }

  // Cleanup old API usage logs (for maintenance)
  async cleanupOldApiUsage(daysToKeep = 30): Promise<void> {
    const cutoffTimestamp = Date.now() - (daysToKeep * 24 * 60 * 60 * 1000);
    await this.db
      .prepare('DELETE FROM api_usage WHERE timestamp < ?')
      .bind(cutoffTimestamp)
      .run();
  }
}
