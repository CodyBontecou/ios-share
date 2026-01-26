export interface Env {
  IMAGES: R2Bucket;
  UPLOAD_TOKEN: string;
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
  // Validate auth
  const authHeader = request.headers.get('Authorization');
  if (!authHeader || authHeader !== `Bearer ${env.UPLOAD_TOKEN}`) {
    return json({ error: 'Unauthorized' }, 401);
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

  // Validate file size
  if (file.size > MAX_FILE_SIZE) {
    return json({ error: 'File exceeds 10MB limit' }, 400);
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
    },
  });

  // Build response URLs
  const url = new URL(request.url);
  const host = url.origin;

  return json({
    url: `${host}/${key}`,
    id,
    deleteUrl: `${host}/delete/${id}?token=${deleteToken}`,
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
  const url = new URL(request.url);
  const token = url.searchParams.get('token');

  if (!token) {
    return json({ error: 'Missing token' }, 400);
  }

  // Find the object (we need to check all possible extensions)
  const extensions = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'svg', 'bmp', 'ico'];
  let foundKey: string | null = null;
  let foundObject: R2Object | null = null;

  for (const ext of extensions) {
    const key = `${id}.${ext}`;
    const object = await env.IMAGES.head(key);
    if (object) {
      foundKey = key;
      foundObject = object;
      break;
    }
  }

  if (!foundKey || !foundObject) {
    return json({ error: 'Not found' }, 404);
  }

  // Validate delete token
  const storedToken = foundObject.customMetadata?.deleteToken;
  if (!storedToken || storedToken !== token) {
    return json({ error: 'Invalid token' }, 403);
  }

  // Delete from R2
  await env.IMAGES.delete(foundKey);

  return json({ deleted: true });
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
