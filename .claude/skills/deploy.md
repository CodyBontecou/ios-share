# Deploy to Production

Deploy the Cloudflare Worker backend to production.

## Instructions

1. Navigate to the backend directory and deploy:
   ```bash
   cd /Users/codybontecou/dev/ios-share/backend/img-host && wrangler deploy
   ```

2. Verify the deployment was successful by checking the health endpoint:
   ```bash
   curl -s https://img-host.costream.workers.dev/health
   ```

3. If testing a specific endpoint, verify it responds:
   ```bash
   # Example: test auth/apple endpoint
   curl -s -X POST https://img-host.costream.workers.dev/auth/apple -H "Content-Type: application/json" -d '{}'
   ```

## When to Use

Run this skill (`/deploy`) after:
- Making any changes to files in `backend/img-host/src/`
- Adding new API endpoints
- Modifying database migrations
- Changing wrangler.toml configuration

## Troubleshooting

If deployment fails:
1. Check for TypeScript errors: `cd backend/img-host && npx tsc --noEmit`
2. Verify wrangler is authenticated: `wrangler whoami`
3. Check the Cloudflare dashboard for deployment status
