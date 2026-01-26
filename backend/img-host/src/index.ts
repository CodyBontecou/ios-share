import { Database } from './database';
import { Auth } from './auth';

export interface Env {
  IMAGES: R2Bucket;
  DB: D1Database;
  UPLOAD_TOKEN: string; // Legacy - kept for backward compatibility
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

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

async function handleUpload(request: Request, env: Env): Promise<Response> {
  const db = new Database(env.DB);

  // Validate auth - check for API token
  const authHeader = request.headers.get('Authorization');
  const apiToken = Auth.extractBearerToken(authHeader);

  if (!apiToken) {
    return json({ error: 'Unauthorized' }, 401);
  }

  // Get user by API token
  const user = await db.getUserByApiToken(apiToken);
  if (!user) {
    return json({ error: 'Invalid API token' }, 401);
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

  // Upload to R2
  await env.IMAGES.put(key, file.stream(), {
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

  // Log API usage
  await db.logApiUsage(user.id, '/upload', 'POST', 200);

  // Build response URLs
  const url = new URL(request.url);
  const host = url.origin;

  return json({
    url: `${host}/${key}`,
    id: image.id,
    deleteUrl: `${host}/delete/${image.id}?token=${deleteToken}`,
  });
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

  try {
    const body = await request.json() as { email: string; password: string };
    const { email, password } = body;

    if (!email || !password) {
      return json({ error: 'Email and password required' }, 400);
    }

    // Validate email format
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(email)) {
      return json({ error: 'Invalid email format' }, 400);
    }

    // Check if user already exists
    const existingUser = await db.getUserByEmail(email);
    if (existingUser) {
      return json({ error: 'Email already registered' }, 409);
    }

    // Hash password and generate API token
    const passwordHash = await Auth.hashPassword(password);
    const apiToken = Auth.generateApiToken();

    // Create user
    const user = await db.createUser(email, passwordHash, apiToken, 'free');

    // Create free subscription
    await db.createSubscription(user.id, 'free', 'active');

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

  try {
    const body = await request.json() as { email: string; password: string };
    const { email, password } = body;

    if (!email || !password) {
      return json({ error: 'Email and password required' }, 400);
    }

    // Get user
    const user = await db.getUserByEmail(email);
    if (!user) {
      return json({ error: 'Invalid credentials' }, 401);
    }

    // Verify password
    const isValid = await Auth.verifyPassword(password, user.password_hash);
    if (!isValid) {
      return json({ error: 'Invalid credentials' }, 401);
    }

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

  // Validate auth
  const authHeader = request.headers.get('Authorization');
  const apiToken = Auth.extractBearerToken(authHeader);

  if (!apiToken) {
    return json({ error: 'Unauthorized' }, 401);
  }

  const user = await db.getUserByApiToken(apiToken);
  if (!user) {
    return json({ error: 'Invalid API token' }, 401);
  }

  // Get storage usage
  const usage = await db.getStorageUsage(user.id);

  return json({
    user_id: user.id,
    email: user.email,
    subscription_tier: user.subscription_tier,
    storage_limit_bytes: user.storage_limit_bytes,
    storage_used_bytes: usage.total_bytes_used,
    image_count: usage.image_count,
  });
}

async function handleGetImages(request: Request, env: Env): Promise<Response> {
  const db = new Database(env.DB);

  // Validate auth
  const authHeader = request.headers.get('Authorization');
  const apiToken = Auth.extractBearerToken(authHeader);

  if (!apiToken) {
    return json({ error: 'Unauthorized' }, 401);
  }

  const user = await db.getUserByApiToken(apiToken);
  if (!user) {
    return json({ error: 'Invalid API token' }, 401);
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

function handleHealth(): Response {
  return json({ status: 'ok' });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;
    const method = request.method;

    try {
      // POST /auth/register
      if (method === 'POST' && path === '/auth/register') {
        return await handleRegister(request, env);
      }

      // POST /auth/login
      if (method === 'POST' && path === '/auth/login') {
        return await handleLogin(request, env);
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
