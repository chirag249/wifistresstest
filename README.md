# wifistresstest

A Flutter-based Cross-Platform Wi-Fi Stress Tester. This tool generates high-volume TCP/UDP traffic to test the throughput and stability of local networks and routers.

## Features
*   **Pure Dart Engine**: Custom `TrafficEngine` using Isolates for high-performance load generation without native code.
*   **Protocols**: Supports TCP and UDP traffic modes.
*   **Control**: Adjustable threads, bitrate pacing, and duration limits.
*   **Visualization**: Real-time throughput metrics and live charting.
*   **Cross-Platform**: Runs on Android and iOS.

## Phone-Only Wi-Fi Load Testing (Auto-Router Target)

This app supports a **Phone-Only Load Test** workflow, allowing you to stress-test your Wi-Fi router directly from your mobile device without any external server or laptop.

### How it Works
1.  **Auto-Detection**: On startup, the app attempts to detect your Wi-Fi interface and automatically fills the **Target IP** with your router's Gateway IP (e.g., `192.168.1.1`).
2.  **Load Generation**: When you press **START**, the TrafficEngine spins up Dart Isolates (threads) to generate legitimate TCP/UDP traffic directed purely at the router's interface.
3.  **No Packet Injection**: This tool **does not** perform de-authentication attacks, packet injection, or monitor mode jamming. It generates standard, high-volume IP traffic to test router processing capacity (throughput/PPS).

### Testing Steps
1.  Connect your phone to the target Wi-Fi network.
2.  Open the app. Grant **Location** or **Network** permissions if prompted (required for Gateway auto-detection on some Android versions).
3.  Ensure the **Target IP** matches your router's gateway.
4.  Configure the load:
    *   **Protocol**: UDP is recommended for raw throughput testing.
    *   **Bitrate**: Set to `0` for maximum stress.
    *   **Threads**: Start with 2, increase if throughput is not saturated.
5.  Unlock the safety mechanism by typing `I OWN THIS NETWORK`.
6.  Press **START LOAD**.

### Expected Router Behavior
Under heavy load (especially UDP flood), a typical consumer router may exhibit:
*   **High CPU Usage**: The router's processor struggles to route the flood of packets.
*   **Latency Spikes**: Pings to the router from other devices may jump from <5ms to >500ms.
*   **Wi-Fi Slowdown**: Other devices on the network may experience slow internet speeds or temporary disconnection.
*   **Web Interface Lag**: The router's admin page may become unresponsive.

### Understanding the Graphs
*   **Throughput (Mbps)**: Shows the rate of traffic successfully sent by the engine.
    *   If the graph plateaus (e.g., at 300 Mbps), you have likely hit the **Wi-Fi link speed limit** or the router's airtime saturation point.
    *   If the graph fluctuates wildly, it may indicate **congestion control** (TCP) or packet queuing issues.

### Troubleshooting Auto-Detection
If the Target IP is not auto-filled:
*   **Permissions**: Ensure the app has "Precise Location" permission (Android requirement to read Wi-Fi SSID/Gateway).
*   **VPN**: Disable any active VPNs, as they mask the local gateway.
*   **Manual Entry**: You can always manually type the router IP (check your phone's Wi-Fi details, usually labeled `Gateway` or `Router Service`).

### Safety & Legal Disclaimer
*   **Authorized Use Only**: You must have ownership or explicit written permission to test the network.
*   **DoS Risk**: High-bitrate tests can effectively DOS (Denial of Service) the local network for the duration of the test.
*   **Heat Generation**: Use short durations (e.g., 60 seconds). Continuous high-load generation will heat up the mobile device and drain the battery rapidly.
