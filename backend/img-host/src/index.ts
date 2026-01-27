import { Database } from './database';
import { Auth } from './auth';
import { ExportService } from './export';
import { Analytics } from './analytics';
import { RateLimiter, getRateLimitConfig, getIpRateLimitConfig } from './rate-limiter';
import { ContentModerator } from './content-moderation';
import {
  handleRegisterV2,
  handleLoginV2,
  handleRefreshToken,
  handleForgotPassword,
  handleResetPassword,
  handleVerifyEmail,
  handleResendVerification,
  handleAppleSignIn
} from './auth-handlers';
import type { ExportJobResponse } from './types';

export interface Env {
  IMAGES: R2Bucket;
  DB: D1Database;
  UPLOAD_TOKEN: string; // Legacy - kept for backward compatibility
  JWT_SECRET: string;
  EMAIL_FROM?: string;
  EMAIL_API_KEY?: string;
  BASE_URL?: string;
}

const MAX_FILE_SIZE = 10 * 1024 * 1024; // 10MB

function generateId(): string {
  return crypto.randomUUID().slice(0, 8);
}

function generateDeleteToken(): string {
  return crypto.randomUUID();
}

function getExtension(filename: string): string {
  const parts = filename.split('.');
  return parts.length > 1 ? parts.pop()!.toLowerCase() : 'png';
}

function getClientIp(request: Request): string {
  // Try CF-Connecting-IP first (Cloudflare)
  const cfIp = request.headers.get('CF-Connecting-IP');
  if (cfIp) return cfIp;

  // Fallback to X-Forwarded-For
  const forwardedFor = request.headers.get('X-Forwarded-For');
  if (forwardedFor) {
    return forwardedFor.split(',')[0].trim();
  }

  // Default fallback
  return 'unknown';
}

function json(data: unknown, status = 200, headers?: Record<string, string>): Response {
  const responseHeaders = new Headers({
    'Content-Type': 'application/json',
    ...headers,
  });

  return new Response(JSON.stringify(data), {
    status,
    headers: responseHeaders,
  });
}

async function handleUpload(request: Request, env: Env): Promise<Response> {
  const db = new Database(env.DB);
  const analytics = new Analytics(env.DB);
  const rateLimiter = new RateLimiter(env.DB);
  const moderator = new ContentModerator(env.DB);

  const authHeader = request.headers.get('Authorization');
  const token = Auth.extractBearerToken(authHeader);

  if (!token) {
    return json({ error: 'Unauthorized' }, 401);
  }

  const jwtSecret = env.JWT_SECRET || 'default-secret-change-in-production';
  const jwtPayload = await Auth.verifyJWT(token, jwtSecret);

  if (!jwtPayload || jwtPayload.type !== 'access') {
    return json({ error: 'Invalid token' }, 401);
  }

  const user = await db.getUserById(jwtPayload.sub);
  if (!user) {
    return json({ error: 'User not found' }, 401);
  }

  // Check if email is verified
  if (user.email_verified !== 1) {
    return json({ error: 'Email verification required', email_verified: false }, 403);
  }

  // Check if user is suspended
  const suspension = await rateLimiter.checkUserSuspension(user.id);
  if (suspension.suspended) {
    return json({
      error: 'Account suspended',
      reason: suspension.reason,
      suspended_until: suspension.until,
    }, 403);
  }

  // Check rate limit
  const rateLimitConfig = getRateLimitConfig(user.subscription_tier, '/upload');
  const rateLimit = await rateLimiter.checkUserRateLimit(
    user.id,
    '/upload',
    rateLimitConfig
  );

  if (!rateLimit.allowed) {
    return json(
      {
        error: 'Rate limit exceeded',
        retry_after: new Date(rateLimit.reset).toISOString(),
      },
      429,
      {
        'X-RateLimit-Limit': rateLimit.limit.toString(),
        'X-RateLimit-Remaining': rateLimit.remaining.toString(),
        'X-RateLimit-Reset': rateLimit.reset.toString(),
        'Retry-After': Math.ceil((rateLimit.reset - Date.now()) / 1000).toString(),
      }
    );
  }

  // Check for unusual upload patterns
  const patternCheck = await moderator.detectUnusualUploadPattern(user.id);
  if (patternCheck.suspicious) {
    // Log for monitoring but don't block yet (could be legitimate bulk upload)
    console.warn('Unusual upload pattern detected:', {
      userId: user.id,
      reasons: patternCheck.reasons,
    });

    // Flag for manual review if severity is high
    if (patternCheck.reasons.length >= 2) {
      await moderator.flagContent(
        'pending_upload',
        'suspicious',
        0.7,
        'system',
        { pattern_reasons: patternCheck.reasons }
      );
    }
  }

  // Parse form data
  let formData: FormData;
  try {
    formData = await request.formData();
  } catch {
    return json({ error: 'Invalid form data' }, 400);
  }

  const file = formData.get('image');
  if (!file || !(file instanceof File)) {
    return json({ error: 'Missing image field' }, 400);
  }

  // Validate content type
  if (!file.type.startsWith('image/')) {
    return json({ error: 'File must be an image' }, 400);
  }

  // Read file into ArrayBuffer ONCE to avoid stream consumption issues
  const fileBuffer = await file.arrayBuffer();

  // Advanced file type validation and malware scanning
  const malwareScan = await moderator.scanForMalware(file);
  if (malwareScan.flagged) {
    const highConfidenceFlags = malwareScan.flags.filter(f => f.confidence >= 0.8);
    if (highConfidenceFlags.length > 0) {
      // Block upload and log incident
      console.error('Malware detected:', {
        userId: user.id,
        filename: file.name,
        flags: malwareScan.flags,
      });

      // Increment abuse counter for potential suspension
      await rateLimiter.recordFailedAttempt(user.id, 'upload_abuse');

      return json({
        error: 'File rejected',
        reason: 'Security check failed',
      }, 400);
    }
  }

  // Get tier limits for user
  const tierLimits = await db.getTierLimits(user.subscription_tier);
  if (!tierLimits) {
    return json({ error: 'Invalid subscription tier' }, 500);
  }

  // Validate file size against tier limit
  if (file.size > tierLimits.max_file_size_bytes) {
    return json({
      error: `File exceeds ${tierLimits.max_file_size_bytes / (1024 * 1024)}MB limit for ${user.subscription_tier} tier`
    }, 400);
  }

  // Check storage limit
  const hasSpace = await db.checkStorageLimit(user.id, file.size);
  if (!hasSpace) {
    const usage = await db.getStorageUsage(user.id);
    return json({
      error: 'Storage limit exceeded',
      current_usage: usage.total_bytes_used,
      limit: user.storage_limit_bytes
    }, 403);
  }

  // Generate ID and delete token
  const id = generateId();
  const deleteToken = generateDeleteToken();
  const ext = getExtension(file.name);
  const key = `${id}.${ext}`;

  // Upload to R2 using the ArrayBuffer we already read
  await env.IMAGES.put(key, fileBuffer, {
    httpMetadata: {
      contentType: file.type,
    },
    customMetadata: {
      deleteToken,
      originalName: file.name,
      userId: user.id,
    },
  });

  // Save image metadata to database
  const image = await db.createImage(
    user.id,
    key,
    file.name,
    file.size,
    file.type,
    deleteToken
  );

  // Flag low-confidence issues for review (don't block upload)
  if (malwareScan.flagged) {
    for (const flag of malwareScan.flags) {
      await moderator.flagContent(
        image.id,
        flag.type,
        flag.confidence,
        'system',
        { reason: flag.reason }
      );
    }
  }

  // Log API usage
  await db.logApiUsage(user.id, '/upload', 'POST', 200);

  // Build response URLs
  const url = new URL(request.url);
  const host = url.origin;

  return json(
    {
      url: `${host}/${key}`,
      id: image.id,
      deleteUrl: `${host}/delete/${image.id}?token=${deleteToken}`,
    },
    200,
    {
      'X-RateLimit-Limit': rateLimit.limit.toString(),
      'X-RateLimit-Remaining': rateLimit.remaining.toString(),
      'X-RateLimit-Reset': rateLimit.reset.toString(),
    }
  );
}

async function handleGet(request: Request, env: Env, key: string): Promise<Response> {
  const object = await env.IMAGES.get(key);

  if (!object) {
    return json({ error: 'Not found' }, 404);
  }

  const headers = new Headers();
  headers.set('Content-Type', object.httpMetadata?.contentType || 'application/octet-stream');
  headers.set('Cache-Control', 'public, max-age=31536000');
  headers.set('ETag', object.httpEtag);

  return new Response(object.body, { headers });
}

async function handleDelete(request: Request, env: Env, id: string): Promise<Response> {
  const db = new Database(env.DB);
  const url = new URL(request.url);
  const token = url.searchParams.get('token');

  if (!token) {
    return json({ error: 'Missing token' }, 400);
  }

  // Get image from database
  const image = await db.getImageById(id);
  if (!image) {
    return json({ error: 'Not found' }, 404);
  }

  // Validate delete token
  const isValid = await db.verifyDeleteToken(id, token);
  if (!isValid) {
    return json({ error: 'Invalid token' }, 403);
  }

  // Delete from R2
  await env.IMAGES.delete(image.r2_key);

  // Delete from database
  await db.deleteImage(id);

  // Log API usage
  await db.logApiUsage(image.user_id, `/delete/${id}`, 'DELETE', 200);

  return json({ deleted: true });
}

async function handleRegister(request: Request, env: Env): Promise<Response> {
  const db = new Database(env.DB);
  const rateLimiter = new RateLimiter(env.DB);
  const clientIp = getClientIp(request);

  // Check IP-based rate limit for registration
  const ipRateLimit = await rateLimiter.checkIpRateLimit(
    clientIp,
    '/auth/register',
    getIpRateLimitConfig('/auth/register')
  );

  if (!ipRateLimit.allowed) {
    return json(
      {
        error: 'Too many registration attempts',
        retry_after: new Date(ipRateLimit.reset).toISOString(),
      },
      429,
      {
        'X-RateLimit-Limit': ipRateLimit.limit.toString(),
        'X-RateLimit-Remaining': ipRateLimit.remaining.toString(),
        'X-RateLimit-Reset': ipRateLimit.reset.toString(),
      }
    );
  }

  try {
    const body = await request.json() as { email: string; password: string };
    const { email, password } = body;

    if (!email || !password) {
      return json({ error: 'Email and password required' }, 400);
    }

    // Check failed attempts for this email
    const failedCheck = await rateLimiter.checkFailedAttempts(email, 'register');
    if (!failedCheck.allowed) {
      const lockoutMinutes = failedCheck.lockedUntil
        ? Math.ceil((failedCheck.lockedUntil - Date.now()) / (60 * 1000))
        : 0;

      return json({
        error: 'Too many failed attempts',
        locked_until: failedCheck.lockedUntil,
        retry_in_minutes: lockoutMinutes,
        requires_captcha: failedCheck.requiresCaptcha,
      }, 429);
    }

    // Validate email format
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(email)) {
      await rateLimiter.recordFailedAttempt(email, 'register');
      return json({ error: 'Invalid email format' }, 400);
    }

    // Check if user already exists
    const existingUser = await db.getUserByEmail(email);
    if (existingUser) {
      await rateLimiter.recordFailedAttempt(email, 'register');
      return json({ error: 'Email already registered' }, 409);
    }

    // Hash password and generate API token
    const passwordHash = await Auth.hashPassword(password);
    const apiToken = Auth.generateApiToken();

    // Create user
    const user = await db.createUser(email, passwordHash, apiToken, 'free');

    // Create free subscription
    await db.createSubscription(user.id, 'free', 'active');

    // Clear any failed attempts on successful registration
    await rateLimiter.clearFailedAttempts(email, 'register');

    return json({
      user_id: user.id,
      email: user.email,
      api_token: apiToken,
      subscription_tier: user.subscription_tier,
    }, 201);
  } catch (error) {
    console.error('Register error:', error);
    return json({ error: 'Invalid request body' }, 400);
  }
}

async function handleLogin(request: Request, env: Env): Promise<Response> {
  const db = new Database(env.DB);
  const rateLimiter = new RateLimiter(env.DB);
  const clientIp = getClientIp(request);

  // Check IP-based rate limit for login
  const ipRateLimit = await rateLimiter.checkIpRateLimit(
    clientIp,
    '/auth/login',
    getIpRateLimitConfig('/auth/login')
  );

  if (!ipRateLimit.allowed) {
    return json(
      {
        error: 'Too many login attempts',
        retry_after: new Date(ipRateLimit.reset).toISOString(),
      },
      429,
      {
        'X-RateLimit-Limit': ipRateLimit.limit.toString(),
        'X-RateLimit-Remaining': ipRateLimit.remaining.toString(),
        'X-RateLimit-Reset': ipRateLimit.reset.toString(),
      }
    );
  }

  try {
    const body = await request.json() as { email: string; password: string };
    const { email, password } = body;

    if (!email || !password) {
      return json({ error: 'Email and password required' }, 400);
    }

    // Check failed attempts for this email
    const failedCheck = await rateLimiter.checkFailedAttempts(email, 'login');
    if (!failedCheck.allowed) {
      const lockoutMinutes = failedCheck.lockedUntil
        ? Math.ceil((failedCheck.lockedUntil - Date.now()) / (60 * 1000))
        : 0;

      return json({
        error: 'Account temporarily locked due to failed login attempts',
        locked_until: failedCheck.lockedUntil,
        retry_in_minutes: lockoutMinutes,
        requires_captcha: failedCheck.requiresCaptcha,
      }, 429);
    }

    // Get user
    const user = await db.getUserByEmail(email);
    if (!user) {
      await rateLimiter.recordFailedAttempt(email, 'login');
      await rateLimiter.recordFailedAttempt(clientIp, 'login');
      return json({ error: 'Invalid credentials' }, 401);
    }

    // Check if user is suspended
    const suspension = await rateLimiter.checkUserSuspension(user.id);
    if (suspension.suspended) {
      return json({
        error: 'Account suspended',
        reason: suspension.reason,
        suspended_until: suspension.until,
      }, 403);
    }

    // Verify password
    const isValid = await Auth.verifyPassword(password, user.password_hash);
    if (!isValid) {
      await rateLimiter.recordFailedAttempt(email, 'login');
      await rateLimiter.recordFailedAttempt(clientIp, 'login');
      return json({ error: 'Invalid credentials' }, 401);
    }

    // Clear failed attempts on successful login
    await rateLimiter.clearFailedAttempts(email, 'login');
    await rateLimiter.clearFailedAttempts(clientIp, 'login');

    return json({
      user_id: user.id,
      email: user.email,
      api_token: user.api_token,
      subscription_tier: user.subscription_tier,
    });
  } catch (error) {
    console.error('Login error:', error);
    return json({ error: 'Invalid request body' }, 400);
  }
}

async function handleGetUser(request: Request, env: Env): Promise<Response> {
  const db = new Database(env.DB);

  const authHeader = request.headers.get('Authorization');
  const token = Auth.extractBearerToken(authHeader);

  if (!token) {
    return json({ error: 'Unauthorized' }, 401);
  }

  const jwtSecret = env.JWT_SECRET || 'default-secret-change-in-production';
  const jwtPayload = await Auth.verifyJWT(token, jwtSecret);

  if (!jwtPayload || jwtPayload.type !== 'access') {
    return json({ error: 'Invalid token' }, 401);
  }

  const user = await db.getUserById(jwtPayload.sub);
  if (!user) {
    return json({ error: 'User not found' }, 401);
  }

  // Get storage usage
  const usage = await db.getStorageUsage(user.id);

  return json({
    user_id: user.id,
    email: user.email,
    subscription_tier: user.subscription_tier,
    email_verified: user.email_verified === 1,
    storage_limit_bytes: user.storage_limit_bytes,
    storage_used_bytes: usage.total_bytes_used,
    image_count: usage.image_count,
  });
}

async function handleGetImages(request: Request, env: Env): Promise<Response> {
  const db = new Database(env.DB);

  const authHeader = request.headers.get('Authorization');
  const token = Auth.extractBearerToken(authHeader);

  if (!token) {
    return json({ error: 'Unauthorized' }, 401);
  }

  const jwtSecret = env.JWT_SECRET || 'default-secret-change-in-production';
  const jwtPayload = await Auth.verifyJWT(token, jwtSecret);

  if (!jwtPayload || jwtPayload.type !== 'access') {
    return json({ error: 'Invalid token' }, 401);
  }

  const user = await db.getUserById(jwtPayload.sub);
  if (!user) {
    return json({ error: 'User not found' }, 401);
  }

  // Parse query params
  const url = new URL(request.url);
  const limit = parseInt(url.searchParams.get('limit') || '100');
  const offset = parseInt(url.searchParams.get('offset') || '0');

  const images = await db.getImagesByUserId(user.id, limit, offset);

  // Build full URLs for each image
  const host = url.origin;
  const imagesWithUrls = images.map(img => ({
    id: img.id,
    filename: img.filename,
    url: `${host}/${img.r2_key}`,
    size_bytes: img.size_bytes,
    content_type: img.content_type,
    created_at: img.created_at,
  }));

  return json({
    images: imagesWithUrls,
    count: images.length,
  });
}

async function handleAbuseReport(request: Request, env: Env): Promise<Response> {
  const db = new Database(env.DB);
  const moderator = new ContentModerator(env.DB);
  const clientIp = getClientIp(request);

  // Get optional user auth (abuse reports can be anonymous)
  const authHeader = request.headers.get('Authorization');
  const token = Auth.extractBearerToken(authHeader);
  let reporterUserId: string | null = null;

  if (token) {
    const jwtSecret = env.JWT_SECRET || 'default-secret-change-in-production';
    const jwtPayload = await Auth.verifyJWT(token, jwtSecret);
    if (jwtPayload && jwtPayload.type === 'access') {
      const user = await db.getUserById(jwtPayload.sub);
      if (user) {
        reporterUserId = user.id;
      }
    }
  }

  try {
    const body = await request.json() as {
      image_id: string;
      reason: 'nsfw' | 'copyright' | 'malware' | 'spam' | 'other';
      description?: string;
    };

    const { image_id, reason, description } = body;

    if (!image_id || !reason) {
      return json({ error: 'image_id and reason are required' }, 400);
    }

    // Get image to find the reported user
    const image = await db.getImageById(image_id);
    if (!image) {
      return json({ error: 'Image not found' }, 404);
    }

    // Submit abuse report
    const report = await moderator.submitAbuseReport(
      image_id,
      image.user_id,
      reporterUserId,
      clientIp,
      reason,
      description || null
    );

    return json({
      report_id: report.id,
      status: report.status,
      message: 'Thank you for your report. We will review it shortly.',
    }, 201);
  } catch (error) {
    console.error('Abuse report error:', error);
    return json({ error: 'Invalid request body' }, 400);
  }
}

function handleHealth(): Response {
  return json({ status: 'ok' });
}

async function handleExportInitiate(request: Request, env: Env): Promise<Response> {
  const db = new Database(env.DB);

  const authHeader = request.headers.get('Authorization');
  const token = Auth.extractBearerToken(authHeader);

  if (!token) {
    return json({ error: 'Unauthorized' }, 401);
  }

  const jwtSecret = env.JWT_SECRET || 'default-secret-change-in-production';
  const jwtPayload = await Auth.verifyJWT(token, jwtSecret);

  if (!jwtPayload || jwtPayload.type !== 'access') {
    return json({ error: 'Invalid token' }, 401);
  }

  const user = await db.getUserById(jwtPayload.sub);
  if (!user) {
    return json({ error: 'User not found' }, 401);
  }

  // Check rate limit (1 per hour)
  const canExport = await db.checkExportRateLimit(user.id);
  if (!canExport) {
    return json({ error: 'Rate limit exceeded. You can only export once per hour.' }, 429);
  }

  // Create export job
  const job = await db.createExportJob(user.id);

  // Update rate limit
  await db.updateExportRateLimit(user.id);

  // Process export asynchronously
  const exportService = new ExportService(db, env.IMAGES);

  // In a production environment, you'd want to use Cloudflare Queues or Durable Objects
  // for background processing. For now, we'll use ctx.waitUntil() for fire-and-forget
  // This is passed via the execution context which we'll handle in the fetch handler

  const url = new URL(request.url);
  const host = url.origin;

  const response: ExportJobResponse = {
    jobId: job.id,
    status: job.status,
    imageCount: job.image_count,
  };

  return json(response, 202); // 202 Accepted - processing started
}

async function handleExportStatus(request: Request, env: Env, jobId: string): Promise<Response> {
  const db = new Database(env.DB);

  const authHeader = request.headers.get('Authorization');
  const token = Auth.extractBearerToken(authHeader);

  if (!token) {
    return json({ error: 'Unauthorized' }, 401);
  }

  const jwtSecret = env.JWT_SECRET || 'default-secret-change-in-production';
  const jwtPayload = await Auth.verifyJWT(token, jwtSecret);

  if (!jwtPayload || jwtPayload.type !== 'access') {
    return json({ error: 'Invalid token' }, 401);
  }

  const user = await db.getUserById(jwtPayload.sub);
  if (!user) {
    return json({ error: 'User not found' }, 401);
  }

  // Get export job
  const job = await db.getExportJob(jobId);
  if (!job) {
    return json({ error: 'Export job not found' }, 404);
  }

  // Verify ownership
  if (job.user_id !== user.id) {
    return json({ error: 'Forbidden' }, 403);
  }

  const url = new URL(request.url);
  const host = url.origin;

  const response: ExportJobResponse = {
    jobId: job.id,
    status: job.status,
    imageCount: job.image_count,
    archiveSize: job.archive_size > 0 ? job.archive_size : undefined,
    downloadUrl: job.download_url ? `${host}/api/export/${job.id}/download` : undefined,
    expiresAt: job.expires_at ? new Date(job.expires_at).toISOString() : undefined,
    errorMessage: job.error_message || undefined,
  };

  return json(response);
}

async function handleExportDownload(request: Request, env: Env, jobId: string): Promise<Response> {
  const db = new Database(env.DB);

  const authHeader = request.headers.get('Authorization');
  const token = Auth.extractBearerToken(authHeader);

  if (!token) {
    return json({ error: 'Unauthorized' }, 401);
  }

  const jwtSecret = env.JWT_SECRET || 'default-secret-change-in-production';
  const jwtPayload = await Auth.verifyJWT(token, jwtSecret);

  if (!jwtPayload || jwtPayload.type !== 'access') {
    return json({ error: 'Invalid token' }, 401);
  }

  const user = await db.getUserById(jwtPayload.sub);
  if (!user) {
    return json({ error: 'User not found' }, 401);
  }

  // Get export job
  const job = await db.getExportJob(jobId);
  if (!job) {
    return json({ error: 'Export job not found' }, 404);
  }

  // Verify ownership
  if (job.user_id !== user.id) {
    return json({ error: 'Forbidden' }, 403);
  }

  // Check if job is completed
  if (job.status !== 'completed') {
    return json({ error: 'Export is not ready yet', status: job.status }, 400);
  }

  // Check if expired
  if (job.expires_at && job.expires_at < Date.now()) {
    return json({ error: 'Export has expired' }, 410); // 410 Gone
  }

  // Get archive from R2
  if (!job.download_url) {
    return json({ error: 'Download URL not available' }, 500);
  }

  const object = await env.IMAGES.get(job.download_url);
  if (!object) {
    return json({ error: 'Archive not found' }, 404);
  }

  // Return the ZIP file
  const headers = new Headers();
  headers.set('Content-Type', 'application/zip');
  headers.set('Content-Disposition', `attachment; filename="export_${jobId}.zip"`);
  headers.set('Content-Length', object.size.toString());

  return new Response(object.body, { headers });
}

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;
    const method = request.method;

    try {
      // POST /auth/register - Enhanced with JWT and email verification
      if (method === 'POST' && path === '/auth/register') {
        return await handleRegisterV2(request, env);
      }

      // POST /auth/login - Enhanced with JWT tokens
      if (method === 'POST' && path === '/auth/login') {
        return await handleLoginV2(request, env);
      }

      // POST /auth/refresh - Refresh access token
      if (method === 'POST' && path === '/auth/refresh') {
        return await handleRefreshToken(request, env);
      }

      // POST /auth/forgot-password - Request password reset
      if (method === 'POST' && path === '/auth/forgot-password') {
        return await handleForgotPassword(request, env);
      }

      // POST /auth/reset-password - Reset password with token
      if (method === 'POST' && path === '/auth/reset-password') {
        return await handleResetPassword(request, env);
      }

      // POST /auth/verify-email - Verify email address
      if (method === 'POST' && path === '/auth/verify-email' || (method === 'GET' && path === '/auth/verify-email')) {
        return await handleVerifyEmail(request, env);
      }

      // POST /auth/resend-verification - Resend verification email
      if (method === 'POST' && path === '/auth/resend-verification') {
        return await handleResendVerification(request, env);
      }

      // POST /auth/apple - Sign in with Apple
      if (method === 'POST' && path === '/auth/apple') {
        return await handleAppleSignIn(request, env);
      }

      // GET /user
      if (method === 'GET' && path === '/user') {
        return await handleGetUser(request, env);
      }

      // GET /images
      if (method === 'GET' && path === '/images') {
        return await handleGetImages(request, env);
      }

      // POST /upload
      if (method === 'POST' && path === '/upload') {
        return await handleUpload(request, env);
      }

      // POST /api/abuse-report - Submit abuse report
      if (method === 'POST' && path === '/api/abuse-report') {
        return await handleAbuseReport(request, env);
      }

      // POST /api/export - Initiate export job
      if (method === 'POST' && path === '/api/export') {
        return await handleExportInitiate(request, env);
      }

      // GET /api/export/{job_id}/status - Check export status
      if (method === 'GET' && path.startsWith('/api/export/')) {
        const parts = path.split('/');
        if (parts.length === 5 && parts[4] === 'status') {
          const jobId = parts[3];
          return await handleExportStatus(request, env, jobId);
        }
        if (parts.length === 5 && parts[4] === 'download') {
          const jobId = parts[3];
          return await handleExportDownload(request, env, jobId);
        }
      }

      // GET /health
      if (method === 'GET' && path === '/health') {
        return handleHealth();
      }

      // DELETE /delete/<id>
      if (method === 'DELETE' && path.startsWith('/delete/')) {
        const id = path.slice('/delete/'.length);
        if (!id) {
          return json({ error: 'Missing id' }, 400);
        }
        return await handleDelete(request, env, id);
      }

      // GET /<id>.<ext> - serve image
      if (method === 'GET') {
        const match = path.match(/^\/([a-zA-Z0-9]+\.[a-zA-Z0-9]+)$/);
        if (match) {
          return await handleGet(request, env, match[1]);
        }
      }

      return json({ error: 'Not found' }, 404);
    } catch (error) {
      console.error('Error:', error);
      return json({ error: 'Internal server error' }, 500);
    }
  },
};
