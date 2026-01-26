# Build Configuration Setup

This document explains how to configure the iOS app for SaaS backend URL using Xcode build settings.

## Overview

The app supports two hosting modes:
- **SaaS Mode**: Backend URL automatically configured from build settings
- **Self-Hosted Mode**: User manually enters their own backend URL

The build configuration allows you to set the default SaaS backend URL at build time.

## Files Created

### Configuration Files
- `/Config/Debug.xcconfig` - Debug build configuration
- `/Config/Release.xcconfig` - Release build configuration

### Modified Files
- `Shared/Config.swift` - Added hosting mode detection and backend URL logic
- `ImageHost/Info.plist` - Added BackendURL key to read from build settings
- `ShareExtension/Info.plist` - Added BackendURL key for share extension
- `Shared/Services/UploadService.swift` - Updated to use Config.effectiveBackendURL
- `ImageHost/Views/SettingsView.swift` - Updated to display correct URL based on mode

## Xcode Setup Instructions

### Step 1: Add xcconfig Files to Xcode Project

1. Open `ImageHost.xcodeproj` in Xcode
2. Right-click on the project root in the Navigator
3. Select "Add Files to ImageHost..."
4. Navigate to the `Config` folder
5. Select both `Debug.xcconfig` and `Release.xcconfig`
6. Check "Copy items if needed" and "Create groups"
7. Click "Add"

### Step 2: Assign Configuration Files to Build Configurations

1. Select the project in the Navigator (top-level blue icon)
2. In the project settings, select the "Info" tab
3. Under "Configurations", expand "Debug"
4. For both "ImageHost" and "ShareExtension" targets, select `Debug` from the dropdown
5. Repeat for "Release" configuration:
   - Assign `Release.xcconfig` to both targets

### Step 3: Verify Build Settings

1. Select the "ImageHost" target
2. Go to "Build Settings" tab
3. Search for "BACKEND_URL"
4. You should see the setting inherited from the xcconfig file
5. Repeat for "ShareExtension" target

## Customizing the Backend URL

### Option 1: Edit xcconfig Files (Recommended)

Edit the `.xcconfig` files directly:

```bash
# Config/Release.xcconfig
BACKEND_URL = https://your-production-backend.com
```

```bash
# Config/Debug.xcconfig
BACKEND_URL = https://your-dev-backend.com
```

**Note**: The `$(/)` in the xcconfig files is intentional - it's a way to escape the `//` in URLs for xcconfig file format.

### Option 2: Override in Xcode Build Settings

1. Select the target (ImageHost or ShareExtension)
2. Go to "Build Settings"
3. Search for "BACKEND_URL"
4. Click the "+" to add a custom value
5. This will override the xcconfig file setting

### Option 3: Hardcoded Fallback

If build configuration is not set, the app falls back to the hardcoded URL in `Config.swift`:

```swift
return "https://img.yourdomain.com"
```

Edit this line in `Shared/Config.swift` to change the fallback URL.

## How It Works

### Build Time
1. Xcode reads `BACKEND_URL` from the xcconfig file
2. Injects it into `Info.plist` as `BackendURL` key
3. Both main app and share extension receive the configuration

### Runtime
1. `Config.saasBackendURL` reads `BackendURL` from Bundle's Info.plist
2. `Config.hostingMode` detects if user has custom URL in UserDefaults
   - If custom URL exists and differs from SaaS URL → Self-Hosted mode
   - Otherwise → SaaS mode
3. `Config.effectiveBackendURL` returns the appropriate URL:
   - SaaS mode: Returns build-configured URL
   - Self-Hosted mode: Returns user's custom URL from settings

### Upload Flow
1. `UploadService` calls `Config.effectiveBackendURL`
2. Gets SaaS URL or user's custom URL based on mode
3. Makes API call to the effective backend

## Migration Path

### New Users
- App defaults to SaaS mode
- Backend URL pre-configured from build settings
- User only needs to enter upload token

### Existing Self-Hosted Users
- Custom URL detected in UserDefaults
- Automatically switches to Self-Hosted mode
- No changes to existing configuration
- Can switch to SaaS mode via Settings (future enhancement)

## Testing

### Test SaaS Mode
1. Clear app data (delete app and reinstall)
2. Launch app
3. Settings should show the build-configured backend URL
4. Enter only the upload token
5. Upload should use the build-configured URL

### Test Self-Hosted Mode
1. Go to Settings
2. Change backend URL to a different value
3. App switches to Self-Hosted mode
4. Upload uses custom URL

### Test Share Extension
1. Share an image from Photos app
2. Share extension should use same backend URL as main app
3. Configuration is shared via App Group UserDefaults

## Troubleshooting

### Backend URL not showing in app
- **Cause**: xcconfig files not assigned to build configuration
- **Solution**: Follow Step 2 above to assign config files

### Build error: "BackendURL not found"
- **Cause**: BACKEND_URL not defined in build settings
- **Solution**: Ensure xcconfig files are properly assigned, or add BACKEND_URL manually in Build Settings

### Share extension uses wrong URL
- **Cause**: ShareExtension target not assigned to xcconfig file
- **Solution**: Assign xcconfig to ShareExtension target in project settings

### URL shows as "$(BACKEND_URL)"
- **Cause**: Build setting not expanding properly
- **Solution**: Check xcconfig syntax - use `https:/$()/domain.com` format

## Build Configurations for Different Environments

You can create additional xcconfig files for different environments:

```bash
Config/
  ├── Debug.xcconfig          # Development/local testing
  ├── Release.xcconfig        # Production SaaS
  ├── Staging.xcconfig        # Staging environment (optional)
  └── TestFlight.xcconfig     # TestFlight builds (optional)
```

Then create corresponding build configurations in Xcode:
1. Project Settings → Info → Configurations
2. Click "+" to duplicate "Release"
3. Rename to "Staging"
4. Assign `Staging.xcconfig` to both targets

## Security Notes

- Backend URLs are not sensitive and can be committed to git
- Upload tokens are stored securely in Keychain (not in build configuration)
- HTTPS required for production builds (validated in SettingsView)
- HTTP only allowed for localhost testing

## Next Steps

See issue `ios-share-1ht` for SettingsView UI enhancements:
- Show hosting mode indicator
- Make URL field read-only in SaaS mode
- Add "Switch to Self-Hosted" button
- Add mode-aware validation
