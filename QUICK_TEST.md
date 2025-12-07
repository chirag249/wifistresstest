# Quick Test Guide

## Before Testing - MUST DO

1. **Completely rebuild the app** (permissions require reinstall):
   ```bash
   flutter clean
   flutter run
   ```
   OR uninstall from phone and reinstall

2. **Verify phone setup**:
   - ✅ Wi-Fi is ON and connected
   - ✅ Airplane mode is OFF
   - ✅ VPN is disabled
   - ✅ Can browse internet in Chrome/browser

## Test Sequence

### Step 1: Verify App Launches
- App should open without crashes
- Should show "Detecting gateway..." then auto-fill router IP

### Step 2: Click Quick Test Button
- Click the "Test: example.com:80" button
- Fields should update to `example.com` and port `80`

### Step 3: Press START
- Watch the console (if running from Android Studio/VS Code)
- Should see:
  ```
  DIAGNOSTIC: Basic internet connectivity OK
  === CONNECTIVITY PROBE START ===
  PROBE: Starting probe to example.com:80
  PROBE: Resolved example.com -> [IP]
  PROBE: Connected to [IP]:80
  PROBE: Write succeeded
  === PROBE RESULT: true ===
  === STARTING TRAFFIC ENGINE ===
  WORKER 0 resolved host -> [IP]
  WORKER 0 connected (tcp) -> [IP]:80
  ```

### Step 4: Check Chart
- Should see throughput line rising
- Current Mbps value should be > 0

## If It Still Fails

### A. Check Console Output

Copy and paste these lines from your console:
- All lines starting with `DIAGNOSTIC:`
- All lines starting with `PROBE:`
- All lines starting with `WORKER`
- Any lines containing `ERROR` or `Exception`

### B. Try Alternative Targets

Try each one in order:

1. **Cloudflare DNS**:
   - Host: `1.1.1.1`
   - Port: `80`

2. **Google DNS**:
   - Host: `8.8.8.8`
   - Port: `443`

3. **IANA Example**:
   - Host: `example.org`
   - Port: `80`

4. **Your Router** (after auto-detect):
   - Host: (auto-filled, like `192.168.1.1`)
   - Port: `80` or `443`

### C. Check Phone Permissions

1. Open phone Settings
2. Go to Apps → wifistresstest
3. Check Permissions:
   - Should have Location enabled (for Wi-Fi info)
   - No other permissions needed (internet is automatic)

### D. Verify in Android Studio

If running from Android Studio:
1. Open Logcat (bottom panel)
2. Filter by package name: `wifistresstest`
3. Look for red errors related to:
   - Permission denied
   - Network unreachable
   - Security exceptions

## Success Indicators

✅ PROBE: Success - endpoint reachable
✅ WORKER X connected (tcp) -> ...
✅ Chart shows non-zero Mbps
✅ No WORKER ERROR messages

## Still Not Working?

Reply with:
1. Exact phone model and Android version
2. All console output (copy/paste)
3. Which test target you tried
4. Screenshot of the chart/UI

## Common Issues Solved

❌ "PROBE FAILED: SocketException" 
   → Fixed by adding INTERNET permission

❌ "No route to host"
   → Check Wi-Fi is active, not cellular

❌ "Connection refused"
   → Target port is closed, try alternative target

❌ "Timeout"
   → Network slow/blocked, try 1.1.1.1:80
