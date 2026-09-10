# MHub — Mobile Hub Flutter Plugin

## Description

MHub is a Flutter plugin that exposes the LAC/PUC-Rio **MobileHub** middleware to Flutter applications on Android. It turns a smartphone into a gateway ("hub") between nearby **BLE (Bluetooth Low Energy)** devices/sensors and a remote server, handling:

- **WPAN (BLE) scanning** — discovering and receiving advertisement data from BLE devices.
- **WLAN transport** — forwarding collected data to a remote endpoint over **mrUDP** (reliable UDP), with **MQTT** support also available in the underlying native library.
- **CEP (Complex Event Processing)** — processing incoming sensor/context data through the bundled **Asper** CEP engine before it is dispatched as `MobileHubEvent`s.
- **Context updates** — periodically pushing the set of currently-visible device identifiers (e.g. sorted by RSSI) to the hub for context-aware processing.

The plugin is structured as a standard federated-style Flutter plugin (`lib/` Dart API + `android/` native Kotlin implementation) and ships with a working `example/` app that demonstrates BLE scanning, a device whitelist, starting/stopping the hub, and displaying messages received from the middleware.

> **Platform support:** Android only. No iOS, web, or desktop implementation is included in this package.

## Dataset Information

This repository does not ship a static dataset. Instead, it produces **live sensor/context data at runtime**:

- **Source of data:** BLE advertisement packets broadcast by nearby devices (name, UUID, RSSI) captured through the Android BLE stack, plus any sensor payloads defined by the connected BLE devices' drivers (Lua-based transcoders under `android/src/main/resources` and `android/src/test/resources`).
- **Format:** Data is surfaced to Dart as `Map<dynamic, dynamic>` events (`onBleDataReceived`) and `String` payloads (`onMessageReceived`), and internally modeled as `SensorData` / `MobileObject` entities (see `android/.../domain/entities/`).
- **Persistence:** Locally buffered/queued (see `data/local` and `data/buffer` packages) before transmission to the configured WLAN endpoint; no bundled sample dataset file is included in this package.
- **Reproducing a dataset:** if you need a static dataset for offline analysis, run the app against real or simulated BLE devices and log the stream — see [Reproduction Script](#reproduction-script) below for a starting point.

## Code Information

```
MHub-package-main/
├── lib/                                  # Public Dart API (federated plugin front-end)
│   ├── plugin.dart                       # Plugin class — the API consumed by app code
│   ├── plugin_platform_interface.dart    # Platform interface (contract for platform impls)
│   └── plugin_method_channel.dart        # Default MethodChannel/EventChannel implementation
├── android/
│   ├── src/main/kotlin/br/pucrio/inf/lac/
│   │   ├── Plugin.kt                     # FlutterPlugin entry point / method call routing
│   │   ├── NotificationHelper.kt         # Foreground-service notification helper
│   │   ├── ble/                          # BLE scanning (BleWPAN, BleMessageReceiver, Lua transcoders)
│   │   ├── mrudp/                        # mrUDP-based WLAN transport
│   │   ├── mqtt/                         # MQTT-based WLAN transport (alternative to mrUDP)
│   │   ├── asper/                        # Asper CEP engine integration
│   │   ├── cdp/android/                  # Android context/sensor data providers (accelerometer, etc.)
│   │   └── mobilehub/core/               # MobileHub middleware core (DI, use cases, repositories,
│   │                                        local DB, remote buffer/worker, domain entities)
│   ├── libs/                             # Bundled native jars (ClientLib.jar, asper-4.9.0.jar, ExchangeData-1.0.jar)
│   └── build.gradle / versions.gradle    # Native build & dependency configuration
├── example/                              # Runnable Flutter demo app (lib/main.dart)
├── apks/                                 # Pre-built release APKs of the example app (v1–v4)
├── test/                                 # Dart unit tests for the plugin API
└── pubspec.yaml                          # Package manifest
```

**Key native classes:**
- `Plugin.kt` — implements `getPlatformVersion`, `startMobileHub`, `updateContext`, `stopMobileHub`, `isMobileHubStarted`, `startListening`, `stopListening`, and streams `onMessageReceived` / `onBleDataReceived` / `onScanningStateChanged` back to Dart.
- `MobileHub.kt` — singleton orchestrator; wires together the WLAN technology, WPAN technology, CEP engine, buffering strategy, and local Room database via Dagger 2.
- `BleWPAN.kt` / `BleMessageReceiver.kt` — BLE scanning and device-data parsing (via `RxAndroidBle`).
- `MrudpWLAN.kt` / `MqttWLAN.kt` — the two interchangeable transport implementations for sending data to the remote hub.
- `AsperCEP.kt` — wraps the bundled Asper CEP engine (`android/libs/asper-4.9.0.jar`) for complex event processing.

## Usage Instructions

### 1. Add the dependency

Add the plugin as a path or git dependency in your app's `pubspec.yaml`:

```yaml
dependencies:
  plugin:
    path: ../MHub-package-main   # or a git: reference
```

Then fetch packages:

```bash
flutter pub get
```

### 2. Configure Android permissions

The plugin's own `AndroidManifest.xml` already declares the BLE/location/notification permissions it needs. In your **app's** manifest, request the same runtime permissions (see `example/android/app/src/main/AndroidManifest.xml` for a working reference):

```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
```

At runtime, request BLE + location permissions before scanning (handled for you in `example/lib/main.dart` via `startListening`, which surfaces a `NO_ACTIVITY` error if permissions/activity aren't ready).

### 3. Basic Dart API usage

```dart
import 'package:plugin/plugin.dart';

final plugin = Plugin();

// Start BLE scanning (optionally restrict to a UUID whitelist)
await plugin.startListening(uuids: ['0000180d-0000-1000-8000-00805f9b34fb']);

// Listen for discovered devices
plugin.onBleDataReceived.listen((device) {
  print('Found ${device['name']} (${device['uuid']}) RSSI=${device['rssi']}');
});

// Start the Mobile Hub (WLAN transport + CEP) pointing at your server
await plugin.startMobileHub(ipAddress: '192.168.0.154', port: 6200);

// Push the currently visible device UUIDs as context
await plugin.updateContext(devices: ['uuid-1', 'uuid-2']);

// Listen for processed messages coming back from the hub
plugin.onMessageReceived.listen((message) => print('Message: $message'));

// Tear down
await plugin.stopListening();
await plugin.stopMobileHub();
```

### 4. Run the example app

```bash
cd example
flutter pub get
flutter run
```

The example app (`example/lib/main.dart`) demonstrates BLE scanning with a UUID whitelist, periodic context updates every 2 seconds while scanning, and a settings screen to start/stop the Mobile Hub against a given IP/port. Pre-built release APKs of the example are also available under `apks/`.

## Requirements

**Tooling**
- Flutter SDK `>=3.3.0`, Dart SDK `^3.7.2`
- Android SDK: `minSdk 23`, `targetSdk`/`compileSdk 33`
- JDK 17 (Kotlin `jvmToolchain` is set to 17)
- Kotlin `1.9.21`

**Dart/Flutter dependencies** (`pubspec.yaml`)
- `plugin_platform_interface: ^2.0.2`
- `flutter_lints: ^5.0.0` (dev)

**Native Android dependencies** (`android/build.gradle`, resolved via `versions.gradle`)
- Bundled jars in `android/libs/`: `ClientLib.jar`, `asper-4.9.0.jar` (Asper CEP engine), `ExchangeData-1.0.jar`
- AndroidX: `core-ktx`, `work-runtime-ktx`, `room-runtime`/`room-rxjava2`, `localbroadcastmanager`
- Dagger 2 (`dagger`, `dagger-compiler`) + assisted-inject for dependency injection
- RxJava2 / RxKotlin / RxAndroid
- `com.polidea.rxandroidble2:rxandroidble` for BLE
- `org.luaj:luaj-jse` for Lua-based device driver transcoding
- `org.eclipse.paho` (`paho.mqtt.android`, `paho.client.mqttv3`) for the MQTT transport option
- Gson, Jackson (`jackson-databind`/`core`/`annotations`), Timber
- Test-only: JUnit, Robolectric, Mockito, MockK, `androidx.test:core`

No Python or other non-JVM dependencies are required — this is a pure Flutter/Kotlin package.

## Methodology

Data flows through the plugin in four stages:

1. **Acquisition (WPAN):** `BleWPAN`/`BleMessageReceiver` scan for BLE advertisements via RxAndroidBle, optionally filtered by a UUID whitelist, and decode payloads using Lua-based device drivers (`transcoder/lua/`) when a matching driver is available.
2. **Local processing (CEP):** Collected samples are wrapped as `SensorData`/`MobileObject` domain entities and optionally routed through the Asper Complex Event Processing engine (`AsperCEP`), which evaluates registered event queries and emits `MobileHubEvent`s (e.g. `NewMessage`).
3. **Context aggregation:** The Flutter side periodically (e.g. every 2s in the example app) sorts visible devices by RSSI and calls `updateContext`, which is buffered locally (Room database + `BufferStrategy`/`TrafficStatsStrategy`) to control transmission volume.
4. **Transmission (WLAN):** Buffered data/events are sent to a remote server over the configured transport — `MrudpWLAN` (reliable UDP, used by default in `Plugin.kt`) or `MqttWLAN` (available as an alternative) — with connection state exposed through `ConnectionStatus` and retried via a `WorkManager`-backed `BufferTransmissionWorker`.

Results (processed messages/events) are streamed back to the Flutter layer over an `EventChannel` (`onMessageReceived`) for display or further handling by the host app.

## Reproduction Script

There is no static dataset to regenerate; instead, use the example app (or the snippet below) to reproduce a live BLE + context-update session and capture it as a dataset for offline analysis:

```bash
# 1. Launch the example app on a device with Bluetooth enabled
cd example
flutter pub get
flutter run
```

```dart
// 2. Minimal script to log a BLE scan session to a local file for X seconds.
// Place in example/lib/ (or run ad hoc) — requires the `plugin` and `path_provider` packages.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:plugin/plugin.dart';

Future<void> reproduceDataset({Duration duration = const Duration(minutes: 5)}) async {
  final plugin = Plugin();
  final samples = <Map<String, dynamic>>[];

  final sub = plugin.onBleDataReceived.listen((event) {
    final data = Map<String, dynamic>.from(event);
    data['timestamp'] = DateTime.now().toIso8601String();
    samples.add(data);
  });

  await plugin.startListening(); // scan all nearby BLE devices
  await Future.delayed(duration);
  await plugin.stopListening();
  await sub.cancel();

  final file = File('ble_dataset_${DateTime.now().millisecondsSinceEpoch}.json');
  await file.writeAsString(jsonEncode(samples));
  print('Wrote ${samples.length} samples to ${file.path}');
}
```

Run `reproduceDataset()` from a button/hook in the example app (or a standalone integration test under `example/integration_test/`) to regenerate a comparable BLE dataset on demand. Adjust `duration` and the UUID whitelist passed to `startListening` to match the original collection conditions.

## Citations

If you use MHub / the MobileHub middleware in academic work, please cite the LAC/PUC-Rio MobileHub project (see the native package namespace `br.pucrio.inf.lac`, Laboratório de Sistemas Avançados de Computação, PUC-Rio). No published paper reference is bundled with this repository; consult the LAC/PUC-Rio group for the appropriate citation for the version of MobileHub used.

## License & Contribution Guidelines

- **License:** Not yet specified — `LICENSE` currently contains a placeholder (`TODO: Add your license here.`). Add the appropriate license text before distributing or publishing this package.
- **Contributions:** No formal contribution guide is defined yet. To contribute, open an issue describing the change, fork the repository, and submit a pull request against the native (`android/`) or Dart (`lib/`) code as appropriate; keep changes to the bundled native jars (`android/libs/`) and generated platform scaffolding (`example/android`, `example/ios`) to a minimum.
