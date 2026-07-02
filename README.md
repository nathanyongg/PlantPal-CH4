# PlantPal-CH4 — Tech Report

> An iOS app that monitors plant health in real time using IoT sensors, on-device AI, and cloud-based intelligence — so your plant can tell you when it needs help, even when you're not home.

---

## Team
Agustinus Juan Kurniawan
Farhan Fatich Ridwan
Huy Bao Tran
Nathan Josh Yong
Poh Jun Heng

---

## 1. Starting Assumption

Before writing a single line of Swift, our assumption was straightforward:

> **"We have a dataset. We train a classifier on it. The model predicts healthy or unhealthy. Done."**

We had a CSV with 1,000 plant readings, seven features (`Temperature_C`, `Humidity_%`, `Soil_Moisture_%`, `Soil_pH`, `Nutrient_Level`, `Light_Intensity_lux`, `Health_Score`), and a binary `Health_Status` target. The plan was to train a Random Forest, export it to CoreML, drop it into the app, and ship.

The architecture we imagined:

```
ESP32 sensors → iPhone (CoreML) → alert if unhealthy
```

Simple. Clean. Wrong.

---

## 2. The Exploration Log

### Step 1 — Running the baseline model

We trained a `RandomForestClassifier` on the full dataset with `class_weight='balanced'` and an 80/20 train-test split. The result looked great on paper:

```
Accuracy: 100%
Recall (unhealthy): 1.00
```

Too good. We dug into feature importances and found the problem immediately:

```
Health_Score        0.875  ███████████████████████████████████
Light_Intensity     0.023  █
Nutrient_Level      0.022  █
Soil_Moisture       0.021  █
Soil_pH             0.020  █
Temperature         0.020  █
Humidity            0.018  █
```

`Health_Score` — a pre-computed composite column — accounted for 87.5% of the model's decisions. The model wasn't learning plant biology. It was reading a label that was already in the data. A cactus and a Monstera looked identical to it because the sensor features barely separated the two classes at all:

| Feature | Healthy mean | Unhealthy mean | Difference |
|---|---|---|---|
| Temperature | 24.98°C | 25.43°C | 0.45°C |
| Humidity | 60.80% | 60.25% | 0.55% |
| Soil moisture | 44.83% | 46.30% | 1.47% |
| Light | 19,874 lux | 19,792 lux | 82 lux |

The four real IoT sensor features — the ones our ESP32 actually produces — had nearly identical distributions between healthy and unhealthy plants. The dataset was synthetic, and `Health_Score` was the true label. The sensors were never the cause of anything in it.

### Step 2 — Trying to fix it with resampling

We tried SMOTE and its variants to address the class imbalance (4.7:1, healthy to unhealthy):

| Strategy | Unhealthy recall | False alarms | Missed sick plants |
|---|---|---|---|
| No resampling (baseline) | 0.03 | 3 | 34/35 |
| SMOTE | **0.46** | 62 | 19/35 |
| SMOTE + Tomek links | 0.43 | 63 | 20/35 |
| SMOTE + ENN | 0.46 | 82 | 19/35 |

SMOTE improved recall from 0.03 to 0.46 — but precision collapsed to 0.21, meaning 62 false alarms for every 200 predictions. Worse, the threshold tuning table revealed the model had learned inverted probabilities:

```
Threshold 0.50 → recall 0.54   (best recall is at the highest threshold)
Threshold 0.40 → recall 0.43   (drops as threshold lowers — backwards)
Threshold 0.25 → recall 0.14   (completely wrong direction)
```

In a working classifier, lowering the decision threshold always increases recall. Ours did the opposite — a mathematical sign that the features don't separate the classes. SMOTE can only amplify signal that already exists. There was no signal to amplify.

### Step 3 — Rethinking the connectivity layer

In parallel, we designed the hardware pipeline assuming the user's phone would always be nearby. The original architecture used **CoreBluetooth as the primary data transport** — the ESP32 would continuously broadcast sensor readings over BLE and the iPhone would read them in the foreground.

Then we asked the obvious question: what if the owner isn't home?

BLE range is ~10 metres. If the phone isn't in the room, the ESP32 has no one to talk to. The alert never fires. The plant dies.

We changed the data transport to **WiFi + cloud relay**: the ESP32 connects to home WiFi, POSTs readings to a cloud endpoint every 15 minutes independently of phone proximity, and the iPhone fetches from that endpoint from anywhere with internet.

BLE wasn't removed — it was repurposed. We still use it for **one-time WiFi provisioning**: when the user first sets up a new ESP32, the iPhone sends the WiFi SSID and password to the device over BLE. The ESP32 joins the network, the BLE session ends, and all subsequent communication is over HTTPS. This is the standard pattern for consumer IoT hardware.

---

## 3. What We Tried and Dropped

### CoreML model from the synthetic dataset

**Why we tried it:** standard supervised learning pipeline — train offline, export to `.mlmodel`, run on-device.

**Why we dropped it:** the four real sensor features (`Temperature`, `Humidity`, `Soil_Moisture`, `Light_Intensity`) have near-identical distributions between healthy and unhealthy plants in this dataset. No ML technique — SMOTE, GridSearchCV, threshold tuning, XGBoost — can learn a boundary that doesn't exist in the features. The model would spam users with false alarms (62 per 200 predictions) or miss almost every sick plant (34/35 with no resampling). Either outcome is worse than no model at all.

**What replaced it:** a rule-based detector using species-specific thresholds fetched from Gemini, combined with the Apple Foundation Model for natural-language explanations.

### Revised: CoreBluetooth role — WiFi provisioning only

**The problem we hit:** the original architecture used CoreBluetooth as the primary data transport — ESP32 advertises sensor readings over BLE, iPhone reads them continuously. This fails the moment the owner isn't nearby.

**What we changed:** BLE is no longer the data transport. The ESP32 connects to home WiFi and POSTs readings to a cloud endpoint every 15 minutes independently of phone proximity. The iPhone fetches from that endpoint from anywhere with internet.

**What BLE is still used for:** first-time device setup. When the user adds a new ESP32 to the app, the phone doesn't know the home WiFi credentials. We use BLE for a one-time provisioning handshake — the iPhone connects to the ESP32 over BLE and writes the WiFi SSID and password to a characteristic. The ESP32 joins the network, disconnects from BLE, and from that point on communicates entirely over WiFi + HTTPS. BLE is never used again after setup.

```
First-time setup:   iPhone → BLE → ESP32 (send WiFi SSID + password)
                    ESP32 joins WiFi, BLE session ends

Runtime (always):   ESP32 → WiFi → Cloud → iPhone (from anywhere)
```

This is the standard pattern for IoT WiFi provisioning — the same approach used by Philips Hue, IKEA Tradfri, and most consumer smart home hardware.

### SMOTE and threshold tuning on the imbalanced dataset

**Why we tried it:** the dataset was 82.5% healthy vs 17.5% unhealthy — a classic imbalance problem. SMOTE is the standard fix. We tested SMOTE, SMOTE + Tomek links, and SMOTE + ENN with GridSearchCV over Random Forest hyperparameters.

**Why we dropped it:** threshold tuning revealed the model had learned inverted class probabilities — the signal the resampler was trying to amplify didn't exist in the raw sensor columns. Best recall achieved was 0.54 at threshold 0.5, dropping to 0.14 at threshold 0.25 (backwards from expected behaviour). This is not a resampling problem; it's a data problem. The synthetic dataset was generated from `Health_Score`, not from sensor physics.

---

## 4. Real Limitations Hit

**The synthetic dataset couldn't be fixed.** No amount of resampling, tuning, or model selection recovers from features that don't separate the classes. The correct fix is collecting real labelled data from an actual plant over 2–4 weeks and retraining. The app's `PlantProfile` in SwiftData already persists every threshold and status update — that history becomes the seed for a future real training dataset.

**Apple Foundation Model has no internet access.** It is a fully local, on-device model with no ability to fetch external data. We worked around this with tool calling — the FM can invoke a `PlantSearchTool` that runs a real HTTPS search, then reasons over the returned text. The FM does the language synthesis; Swift does the fetching.

**Background App Refresh is not a real-time scheduler.** `BGAppRefreshTask` is opportunistic — iOS decides when to run it based on usage patterns, not a strict 15-minute clock. For production-grade alerting, a server-side check would need to trigger an APNs push when a reading crosses a threshold, rather than relying on the app to pull on schedule.

**`Health_Score` in the dataset is a leaking label.** We didn't catch this until running feature importances. In a real ML project, any feature that is a composite of the others or a proxy for the target must be removed before training — otherwise you're evaluating the model's ability to read the answer key, not learn the problem.

**Apple Intelligence availability is not guaranteed.** The Foundation Model requires Apple Intelligence to be enabled and fully downloaded on the device. We handle this with `PlantExplainer.isAvailable()` — when the FM is unavailable, the app falls back to the rule-based detector's plain-text summary, so the notification still fires with useful content.

---

## 5. The Revised Decision

Our starting assumption — train a classifier, export to CoreML, ship — was wrong in two ways at once.

**The data was wrong.** The synthetic dataset's sensor features don't separate healthy from unhealthy plants. A real model requires real data from a real plant, labelled over time. That data doesn't exist yet, so CoreML is a future milestone, not a current component.

**The architecture was wrong.** BLE assumes proximity. Our use case requires remote monitoring. WiFi + cloud is the only architecture that works when the owner isn't home.

The revised architecture:

```
First-time setup:
  iPhone → BLE → ESP32 (send WiFi SSID + password) → ESP32 joins WiFi

Runtime:
  ESP32 (DHT11 + photoresistor + soil probe)
    → WiFi → HTTPS POST every 15 min → Cloud endpoint
    → iPhone fetches from anywhere
    → Rule-based detector (species thresholds from Gemini, persisted in SwiftData)
    → Healthy: SwiftData updated silently, no notification
    → Unhealthy: Apple Foundation Model generates explanation
    → Push notification with plain-language action
    → Dashboard: multi-plant summary (healthy / warning / critical)
```

**What Gemini replaced CoreML for:** on first setup, the user types a plant species name. Gemini 2.5 Flash returns species-specific threshold ranges (ideal temperature, humidity, soil moisture, light). These are persisted to SwiftData via `PlantProfile` and used by the detector at runtime — so a cactus at 10% soil moisture is healthy, while a Monstera at 10% is critical. Gemini is called once per plant, never again.

**What the Foundation Model does:** it never predicts. The rule-based detector handles the binary decision. When something is wrong, the FM receives the labeled sensor findings and generates a two-sentence explanation in plain language — cause and action — which becomes the notification body. The FM's only job is language synthesis over already-diagnosed facts, which is the task small on-device models do reliably.

**CoreML is still in the architecture** — as `Detection/CoreMLClassifier.swift`, an empty stub conforming to the `PlantClassifier` protocol. Once real labelled sensor data is collected, the SMOTE + GridSearchCV pipeline can be retrained on that data and exported via `coremltools`. The swap requires changing one line in `PlantHealthMonitor` — everything else stays identical.

---

## 6. App Addendum

### Frameworks used

| Framework | Purpose |
|---|---|
| `FoundationModels` | On-device Apple Intelligence — plant health explanation |
| `SwiftData` | Persisting `PlantProfile` (species name + Gemini thresholds + last status) |
| `CoreBluetooth` | One-time WiFi provisioning — sends SSID + password to ESP32 on first setup |
| `BackgroundTasks` | 15-minute sensor polling via `BGAppRefreshTask` |
| `UserNotifications` | Push alerts — warning (default sound) and critical (bypasses Focus Mode) |
| `Network` / `URLSession` | HTTPS fetch from cloud endpoint, Gemini API calls |
| `SwiftUI` + `Charts` | Dashboard, setup flow, trend card, sensor reading cards |

### Privacy

- **No sensor data leaves the device except to your own cloud endpoint.** The ESP32 POSTs to your Cloudflare Worker; no third party sees the readings.
- **Gemini API is called once per plant at setup**, with only the plant species name as input. No user data, no sensor readings.
- **Apple Foundation Model runs entirely on-device.** No prompt text, sensor values, or explanations are sent to Apple or any server.
- **BLE provisioning transmits only WiFi credentials**, sent directly from iPhone to ESP32 over an encrypted BLE characteristic. Credentials are never stored in the app or sent to any server.
- **API keys are stored in `Secrets.xcconfig`**, excluded from version control via `.gitignore`, and accessed at runtime through `Info.plist` variable substitution. No key appears as a string literal in source code.

### The CoreML upgrade path

When real labelled data is available:

```bash
# 1. Collect sensor readings + manual health labels over 2-4 weeks
# 2. Run the training pipeline
python plant_smote_pipeline.py

# 3. Export to CoreML
import coremltools as ct
model = ct.converters.sklearn.convert(best_rf,
    input_features=['Temperature_C','Humidity_%','Soil_Moisture_%','Light_Intensity_lux'],
    output_feature_names='Health_Status')
model.save("PlantHealthClassifier.mlmodel")

# 4. Drag .mlmodel into Xcode → Resources/
# 5. In PlantHealthMonitor.swift, change one line:
# let detector = PlantHealthDetector()   ← before
# let detector = CoreMLClassifier()      ← after
```

Everything else — `PlantExplainer`, `DashboardView`, notifications, SwiftData — stays exactly the same.
