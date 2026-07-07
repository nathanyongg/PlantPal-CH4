# PlantPal Technical Report

## Introduction

PlantPal is an IoT-powered plant monitoring system designed to help
users maintain healthy plants by monitoring the environmental conditions
that directly influence **photosynthesis**. Instead of predicting plant
health using machine learning alone, PlantPal continuously measures the
most important environmental factors affecting plant growth and provides
actionable recommendations when conditions fall outside suitable ranges.

Our initial idea was to build PlantPal with a machine learning model
that predicts whether a plant is healthy or unhealthy from IoT sensor
readings. After experimenting with the dataset, we found that it was not
suitable for a reliable classifier because the dataset was
**synthetic**, **imbalanced**, and contained a pre-calculated
**Health_Score** that effectively revealed the correct answer. As a
result, the model learned to rely on this score instead of identifying
meaningful relationships between actual sensor readings.

Instead of forcing the model into the application, we adopted a
**rule-based monitoring approach**. Live sensor readings are compared
against **species-specific environmental thresholds**, producing
transparent and explainable recommendations based on measurable
environmental conditions rather than unreliable predictions.

## Machine Learning Exploration

We first trained a Random Forest model using the provided dataset.

  Result                 Value
  -------------------- -------
  Accuracy                100%
  Recall (Unhealthy)      1.00

The result looked excellent, but feature importance showed that almost
every prediction came from the `Health_Score` column instead of the real
sensor values.

  Feature             Importance
  ----------------- ------------
  Health_Score             87.5%
  Light Intensity           2.3%
  Nutrient Level            2.2%
  Soil Moisture             2.1%
  Soil pH                   2.0%
  Temperature               2.0%
  Humidity                  1.8%

After removing this advantage, the remaining sensor readings were too
similar between healthy and unhealthy plants for the model to reliably
distinguish them.

We also experimented with SMOTE to improve the imbalanced dataset.

  Method            Recall   False Alarms
  --------------- -------- --------------
  Baseline            0.03              3
  SMOTE               0.46             62
  SMOTE + Tomek       0.43             63
  SMOTE + ENN         0.46             82

Although recall improved, the number of false alarms became too high.
This would result in many incorrect notifications being sent to users,
reducing confidence in the application. Because of this trade-off, we
decided not to use the Core ML model.

## IoT Sensor Selection

PlantPal focuses on monitoring the environmental conditions that have
the greatest impact on photosynthesis.

  -----------------------------------------------------------------------
  Sensor                  Purpose                 Importance to
                                                  Photosynthesis
  ----------------------- ----------------------- -----------------------
  KY-018 Photoresistor    Measures ambient light  Light is the primary
                          intensity               energy source required
                                                  for photosynthesis.

  DHT11                   Measures air            Temperature affects
                          temperature and         photosynthetic enzyme
                          humidity                activity while humidity
                                                  influences
                                                  transpiration.

  YL-69 Soil Moisture     Measures soil water     Water is a key input
  Sensor                  content                 for photosynthesis and
                                                  healthy root function.

  DS1302 RTC              Provides accurate date  Records timestamps for
                          and time                sensor readings and
                                                  enables scheduled
                                                  sampling every 15
                                                  minutes.
  -----------------------------------------------------------------------

These sensors were selected because they monitor the environmental
factors with the greatest influence on photosynthesis while keeping the
hardware compact and cost-effective.

## Hardware Design Considerations

Proper sensor placement is essential for obtaining accurate
environmental measurements.

-   The **KY-018 photoresistor** should face the surrounding environment
    and not be covered by leaves. Otherwise, light readings may be lower
    than the light actually reaching the plant.
-   The **DHT11** should be positioned slightly away from the plant
    canopy and soil surface to measure ambient air temperature and
    humidity.
-   The **YL-69** should be inserted near the plant's root zone while
    avoiding direct contact with the stem.
-   Sensors should be spaced appropriately within the enclosure to
    minimise interference while maintaining a compact form factor.

## Architecture Changes

Originally, the ESP32 communicated directly with the iPhone using
Bluetooth, limiting communication to nearby devices.

The final architecture uses Wi-Fi instead. Each plant is equipped with
its own dedicated ESP32 monitoring device. Every ESP32 uploads sensor
readings to a cloud endpoint every 15 minutes, while the iPhone
retrieves the latest data through the internet, allowing users to
remotely monitor multiple plants simultaneously.

Bluetooth is still used during the initial setup process to securely
provision Wi-Fi credentials from the iPhone to the ESP32.

## Final Solution

Instead of machine learning, PlantPal compares incoming sensor readings
against **species-specific environmental thresholds**.

When adding a plant, the user enters its **species name**. The more
specific the species name (for example, *Monstera deliciosa* rather than
simply *Monstera*), the more accurately Gemini can generate suitable
environmental thresholds.

Gemini generates recommended ranges for:

-   Temperature
-   Humidity
-   Soil moisture
-   Light intensity

These thresholds are stored locally in SwiftData.

Each plant is paired with its own ESP32 device equipped with the KY-018,
DHT11, YL-69 and DS1302 sensors. Sensor readings are uploaded every 15
minutes and compared against the stored thresholds.

If readings fall outside the safe range, Apple's Foundation Model
generates a concise explanation and suggested actions that are displayed
through local notifications.

PlantPal also supports Dynamic Type, VoiceOver and spoken announcements
through AVFoundation, making the application accessible to users with
visual impairments.

## Frameworks Used

  -----------------------------------------------------------------------
  Framework               Core Feature            Purpose in PlantPal
  ----------------------- ----------------------- -----------------------
  SwiftUI                 Declarative UI          Build the application's
                                                  interface

  SwiftData               Local persistence       Store plant profiles,
                                                  thresholds and latest
                                                  sensor status

  FoundationModels        On-device language      Generate
                          model                   natural-language
                                                  explanations for alerts

  PhotosUI                Photo Picker            Allow users to choose
                                                  plant images

  CoreBluetooth           BLE communication       Initial ESP32 Wi-Fi
                                                  provisioning

  AVFoundation            Speech synthesis        Read important updates
                                                  aloud for accessibility

  BackgroundTasks         Background execution    Periodically check
                                                  plant status

  UserNotifications       Local notifications     Notify users when a
                                                  plant needs attention

  URLSession              HTTP networking         Retrieve sensor data
                                                  and communicate with
                                                  Gemini and cloud
                                                  services
  -----------------------------------------------------------------------

## Limitations

-   The dataset is synthetic and therefore unsuitable for training a
    production-quality machine learning classifier.
-   The ESP32 supports **2.4 GHz Wi-Fi only** and cannot connect to 5
    GHz-only wireless networks.
-   Background Tasks on iOS do not execute at fixed intervals.
-   The YL-69 soil moisture sensor may corrode over time and require
    periodic calibration or replacement.
-   Incorrect sensor placement (such as leaves blocking the
    photoresistor) can reduce measurement accuracy.
-   A production deployment would require a secure cloud backend and
    long-term real-world sensor data for validation.

## Conclusion

Although Core ML was not used in the final application, the
experimentation highlighted the limitations of the available dataset and
demonstrated that a rule-based monitoring approach was more suitable.

The final application combines ESP32 IoT devices, environmental sensors,
Wi-Fi communication, Gemini-generated species-specific thresholds and
Apple's Foundation Model to help users maintain the environmental
conditions required for effective photosynthesis. By focusing on
measurable environmental factors rather than unreliable predictions,
PlantPal provides a transparent, reliable and extensible plant
monitoring solution.
