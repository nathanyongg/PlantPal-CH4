# PlantPal

PlantPal is an iOS app that pairs with a dedicated IoT sensor for each of your houseplants. It reads the plant's temperature, humidity, soil moisture and light, compares those readings against species-specific ideal ranges, and gives your plant a "mood" and plain-language care advice whenever something needs attention.

For the machine learning exploration, sensor selection rationale, architecture decisions, and other technical write-up, see [Tech Report.md](Tech%20Report.md).

## Features

- **Species-aware thresholds** — enter a plant's species and Gemini generates suitable temperature, humidity, soil moisture and light ranges for it.
- **One sensor per plant** — each plant is paired with its own ESP32 device, so readings are never ambiguous about which plant they belong to.
- **Plant mood & AI insights** — Apple's on-device Foundation Model turns sensor readings into a short mood, a message "from" the plant, and actionable care advice when a reading falls outside the ideal range.
- **Conditions dashboard** — a per-plant screen showing temperature, humidity, soil moisture and light against their ideal ranges at a glance.
- **Local notifications** — get notified when a plant needs attention, plus an optional daily care reminder.
- **Paired device management** — see every sensor and which plant it's attached to, and unpair one without deleting the plant.
- **Accessibility** — Dynamic Type, VoiceOver support, and optional spoken announcements via AVFoundation.

## Requirements

- Xcode 26.5 or later
- iOS 26.5+ (device or simulator)
- A [Gemini API key](https://ai.google.dev/) for generating species thresholds
- A Firebase project (for Firestore sync) — `GoogleService-Info.plist` is already included in the repo
- One ESP32 board per plant you want to monitor, wired with:
  - KY-018 photoresistor (light)
  - DHT11 (temperature & humidity)
  - YL-69 soil moisture sensor
  - DS1302 real-time clock

The ESP32 firmware sketch is at [`PlantPal-CH4/firmware/PlantPal-Iot/PlantPal-Iot.ino`](PlantPal-CH4/firmware/PlantPal-Iot/PlantPal-Iot.ino).

## Getting started

1. Clone the repo and open `PlantPal-CH4/PlantPal-CH4.xcodeproj` in Xcode.
2. Copy `PlantPal-CH4/SecretsExample.xcconfig` to `PlantPal-CH4/Secrets.xcconfig` and fill in your `GEMINI_API_KEY`. This file is gitignored — never commit it.
3. Flash `firmware/PlantPal-Iot/PlantPal-Iot.ino` onto an ESP32 for each plant you want to monitor.
4. Select the `PlantPal-CH4` scheme and run on a device or simulator.

## Using the app

1. **Onboarding** walks through what PlantPal does and asks for notification permission.
2. **Add a plant** from the "+" button on the Collections screen: pair a nearby ESP32 over Bluetooth, provision it onto your home Wi-Fi, then fill in the plant's nickname, species, and photo. Gemini fills in the ideal environmental ranges based on the species.
3. Tap into a plant to see its **conditions**, mood, and the latest AI-generated insight. Pull to refresh or tap the refresh button to take a fresh reading and log a check-in.
4. **Settings** lets you manage appearance, text size, notifications, spoken announcements, and paired devices — including unpairing a sensor without losing the plant's history.

## Project structure

- `PlantPal-CH4/ios/` — the SwiftUI app (Views, Models, Networking, Bluetooth, Detection/Reasoning pipeline, Notifications)
- `PlantPal-CH4/firmware/` — the ESP32 Arduino sketch
- `Tech Report.md` — the technical write-up (ML exploration, sensor/hardware rationale, architecture, limitations)
