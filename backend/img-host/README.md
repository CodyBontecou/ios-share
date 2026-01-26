# img-host

Minimal image hosting backend using Cloudflare Workers and R2 storage.

## Setup

### 1. Install Wrangler

```bash
npm install -g wrangler
```

### 2. Login to Cloudflare

```bash
wrangler login
```

### 3. Create R2 Bucket

```bash
wrangler r2 bucket create images
```

### 4. Install Dependencies

```bash
cd img-host
npm install
```

### 5. Set Upload Token Secret

```bash
wrangler secret put UPLOAD_TOKEN
# Enter your secret token when prompted
```

### 6. Run Locally

```bash
npm run dev
# or
wrangler dev
```

For local development, create a `.dev.vars` file:

```
UPLOAD_TOKEN=test-token
```

### 7. Deploy

```bash
npm run deploy
# or
wrangler deploy
```

## API

### Upload Image

```bash
curl -X POST http://localhost:8787/upload \
  -H "Authorization: Bearer test-token" \
  -F "image=@test.png"
```

Response:
```json
{
  "url": "http://localhost:8787/abc12345.png",
  "id": "abc12345",
  "deleteUrl": "http://localhost:8787/delete/abc12345?token=<delete-token>"
}
```

### Fetch Image

```bash
curl -I http://localhost:8787/abc12345.png
```

### Delete Image

```bash
curl -X DELETE "http://localhost:8787/delete/abc12345?token=<delete-token>"
```

Response:
```json
{
  "deleted": true
}
```

### Health Check

```bash
curl http://localhost:8787/health
```

Response:
```json
{
  "status": "ok"
}
```

## Limits

- Max file size: 10MB
- Accepted types: `image/*`
