# PlantPal Technical Report

## Introduction

Our initial idea was to build PlantPal with a machine learning model
that predicts whether a plant is healthy or unhealthy from IoT sensor
readings. After experimenting with the dataset, we found that the data
was not suitable for a reliable classifier. Instead of forcing the model
into the app, we changed to a rule-based approach that is more accurate
for the available data.

## Machine Learning Exploration

We first trained a Random Forest model using the provided dataset.

| Result | Value |
| --- | --- |
| Accuracy | 100% |
| Recall (Unhealthy) | 1.00 |

The result looked excellent, but feature importance showed that almost
every prediction came from the `Health_Score` column instead of the real
sensor values.

| Feature | Importance |
| --- | --- |
| Health_Score | 87.5% |
| Light Intensity | 2.3% |
| Nutrient Level | 2.2% |
| Soil Moisture | 2.1% |
| Soil pH | 2.0% |
| Temperature | 2.0% |
| Humidity | 1.8% |

After removing this advantage, the remaining sensor readings were too
similar between healthy and unhealthy plants.

We also experimented with SMOTE to improve the imbalanced dataset.

| Method | Recall | False Alarms |
| --- | --- | --- |
| Baseline | 0.03 | 3 |
| SMOTE | 0.46 | 62 |
| SMOTE + Tomek | 0.43 | 63 |
| SMOTE + ENN | 0.46 | 82 |

Although recall improved, the number of false alarms became too high.
Because of this, we decided not to use the CoreML model.

## Architecture Changes

Originally, the ESP32 communicated directly with the iPhone using
Bluetooth. This only works when the user is nearby.

The final design uses WiFi instead. The ESP32 uploads sensor readings to
a cloud endpoint every 15 minutes. The iPhone retrieves the data through
the internet, allowing remote monitoring.

Bluetooth is still used once during setup to send WiFi credentials from
the phone to the ESP32.

A single ESP32 sensor is shared across every plant, so checking on a
specific plant means physically moving the sensor next to it before
opening its details in the app.

## Final Solution

Instead of machine learning, PlantPal compares incoming sensor readings
against species-specific thresholds.

When a user adds a plant, Gemini generates suitable ranges for
temperature, humidity, soil moisture and light. These values are stored
locally in SwiftData.

If the readings are outside the safe range, Apple's Foundation Model
creates a short explanation that is shown in the notification.

PlantPal also supports Dynamic Type, VoiceOver, and spoken
announcements through AVFoundation, so the app stays usable for
people with visual impairments.

## Frameworks Used

| Framework | Core Feature | Purpose in PlantPal |
| --- | --- | --- |
| SwiftUI | Declarative UI | Build the application's interface |
| SwiftData | Local persistence | Store plant profiles, thresholds and latest status |
| FoundationModels | On-device language model | Generate natural-language explanations for alerts |
| PhotosUI | Photo Picker | Allow users to choose plant images |
| CoreBluetooth | BLE communication | Initial ESP32 WiFi provisioning |
| AVFoundation | Speech synthesis | Read important updates aloud for accessibility |
| BackgroundTasks | Background execution | Periodically check plant status |
| UserNotifications | Local notifications | Notify users when a plant needs attention |
| URLSession | HTTP networking | Retrieve sensor data and call Gemini API |

## Limitations

-   The dataset is synthetic, so it is not suitable for training a
    reliable classifier.
-   Background tasks on iOS do not execute at fixed intervals.
-   A production system should use real sensor data collected over
    several weeks and server-side notifications.
-   The cloud endpoint is not deployed yet, so live readings are
    unavailable until a real backend replaces the placeholder URL.

## Conclusion

Even though we did not use CoreML in the final application, the
experimentation helped us understand the dataset's limitations. The
final application combines IoT sensors, WiFi communication, Gemini for
plant-specific thresholds, and Apple's Foundation Model to provide
reliable plant health monitoring.
