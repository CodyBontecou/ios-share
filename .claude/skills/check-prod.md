# Check Production Configuration

Verify that both the iOS app and backend are correctly configured to use production.

## Instructions

1. **Check iOS Debug configuration**:
   ```bash
   cat /Users/codybontecou/dev/ios-share/frontend/ImageHost/Config/Debug.xcconfig | grep BACKEND_URL
   ```

   Expected output should contain:
   ```
   BACKEND_URL = https:/$()/img-host.costream.workers.dev
   ```

   If it shows a local IP (192.168.x.x) or localhost, fix it immediately.

2. **Verify production backend is responding**:
   ```bash
   curl -s https://img-host.costream.workers.dev/health
   ```

   Expected: `{"status":"ok"}`

3. **Check for any hardcoded local URLs in the codebase**:
   ```bash
   grep -r "192\.168\|localhost:8787" /Users/codybontecou/dev/ios-share/frontend/ImageHost --include="*.swift" --include="*.xcconfig"
   ```

   This should only show comments, not active code.

## When to Use

Run this skill (`/check-prod`) when:
- Starting a new development session
- Debugging network connectivity issues
- Before committing changes
- After pulling changes from remote

## Fixing Issues

If Debug.xcconfig has the wrong URL:
```bash
# Edit Debug.xcconfig to use production
sed -i '' 's|BACKEND_URL = http.*|BACKEND_URL = https:/$()/img-host.costream.workers.dev|' /Users/codybontecou/dev/ios-share/frontend/ImageHost/Config/Debug.xcconfig
```

After fixing, remind the user to:
1. Clean Xcode build folder (Cmd+Shift+K)
2. Delete the app from device/simulator
3. Rebuild and run
