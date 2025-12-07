# Fixes Applied to WiFi Stress Test App

## Date: 2025-12-06

## Critical Fixes

### 1. **Missing INTERNET Permission (AndroidManifest.xml)**
- **Problem**: App couldn't make network connections because INTERNET permission was missing
- **Fix**: Added `<uses-permission android:name="android.permission.INTERNET"/>` and `ACCESS_NETWORK_STATE`
- **Impact**: This was likely the PRIMARY cause of "probe failed" errors

### 2. **Improved Probe Function (main.dart)**
- **Problem**: Basic probe didn't provide detailed error information
- **Fixes Applied**:
  - Added timeout handling for DNS lookups
  - Added specific exception types (SocketException, TimeoutException)
  - Improved logging with detailed error messages
  - Changed test payload from HTTP GET to simple "PING\r\n"
  - Properly close socket instead of destroy

### 3. **Added Connection Timeout (traffic_engine.dart)**
- **Problem**: Worker sockets had no timeout, could hang indefinitely
- **Fix**: Added `timeout: Duration(seconds: 10)` to Socket.connect in TCP worker

### 4. **Better Default Port (main.dart)**
- **Problem**: Default port 8080 is often closed/filtered
- **Fix**: Changed default port from 8080 to 80 (HTTP, more commonly open)

### 5. **Enhanced UI Feedback**
- Added diagnostic internet connectivity check before probe
- Added helpful error messages suggesting test targets (example.com:80, 1.1.1.1:80)
- Added "Test: example.com:80" quick-fill button
- Added detailed console logging with markers (=== PROBE START ===, etc.)

## How to Test

1. **Rebuild the app completely**:
   ```bash
   flutter clean
   flutter pub get
   flutter run
   ```

2. **Test with known-good targets** (in order):
   - Click "Test: example.com:80" button and press START
   - Try: `1.1.1.1` port `80` (Cloudflare DNS)
   - Try: `8.8.8.8` port `443` (Google DNS HTTPS)
   - Try: Your router IP (auto-detected) port `80`

3. **Watch console output** for:
   ```
   DIAGNOSTIC: Basic internet connectivity OK
   === CONNECTIVITY PROBE START ===
   PROBE: Starting probe to example.com:80
   PROBE: Resolved example.com -> 93.184.216.34
   PROBE: Connected to 93.184.216.34:80
   PROBE: Write succeeded
   PROBE: Success - endpoint reachable
   === PROBE RESULT: true ===
   === STARTING TRAFFIC ENGINE ===
   WORKER 0 resolved host -> 93.184.216.34
   WORKER 0 connected (tcp) -> 93.184.216.34:80
   WORKER 1 resolved host -> 93.184.216.34
   WORKER 1 connected (tcp) -> 93.184.216.34:80
   ```

## Troubleshooting

### If probe still fails:

1. **Check Wi-Fi is active** (not cellular, not airplane mode)
2. **Disable VPN** if running
3. **Check phone's internet** - open a browser, visit google.com
4. **Try the diagnostic targets** in order above
5. **Check console output** - paste the PROBE and WORKER lines

### If probe succeeds but no throughput:

1. Check for `WORKER ERROR` messages in console
2. Target may be dropping connections after accept (rate limiting)
3. Try different targets to isolate issue

## Expected Behavior After Fixes

- ✅ Basic internet diagnostic should show "OK"
- ✅ Probe to example.com:80 should succeed
- ✅ Workers should connect and show "WORKER X connected"
- ✅ Chart should show throughput data
- ✅ Console should have detailed logs for debugging

## Files Modified

1. `android/app/src/main/AndroidManifest.xml` - Added INTERNET permission
2. `lib/main.dart` - Improved probe, diagnostics, UI, error handling
3. `lib/engine/traffic_engine.dart` - Added socket timeout

## Next Steps

If probe continues to fail even with example.com:80:
- Check Android system logs: `adb logcat | grep -i "permission\|network\|denied"`
- Verify app is using Wi-Fi: Settings → Apps → wifistresstest → Permissions
- Try running on a different device or emulator to isolate device-specific issues
