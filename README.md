# PlantPal Technical Report

## Introduction

PlantPal is an IoT-powered plant monitoring system that helps users grow
healthier plants by monitoring environmental conditions that directly
influence **photosynthesis**. Instead of estimating overall plant health
from images alone, PlantPal continuously measures the environmental
factors that have the greatest impact on plant growth and provides
timely recommendations when conditions move outside healthy ranges.

Our initial idea was to build PlantPal using a machine learning model to
predict whether a plant was healthy or unhealthy from IoT sensor
readings. After experimenting with the dataset, we found that it was
unsuitable for training a reliable classifier because it was synthetic,
imbalanced, and contained a pre-calculated `Health_Score` that
effectively revealed the correct label. The model therefore learned to
depend on this score instead of meaningful relationships between the
sensor readings.

Rather than forcing a machine learning solution, we adopted a
**rule-based monitoring approach**. Live sensor readings are compared
against plant-specific environmental thresholds, providing transparent,
explainable, and more reliable recommendations for the available data.

## Machine Learning Exploration

We trained a Random Forest classifier using the provided dataset.

  Result                 Value
  -------------------- -------
  Accuracy                100%
  Recall (Unhealthy)      1.00

Although the results appeared excellent, feature importance analysis
showed that almost every prediction depended on `Health_Score`.

  Feature             Importance
  ----------------- ------------
  Health_Score             87.5%
  Light Intensity           2.3%
  Nutrient Level            2.2%
  Soil Moisture             2.1%
  Soil pH                   2.0%
  Temperature               2.0%
  Humidity                  1.8%

After removing `Health_Score`, healthy and unhealthy samples overlapped
considerably.

We also evaluated oversampling techniques.

  Method            Recall   False Alarms
  --------------- -------- --------------
  Baseline            0.03              3
  SMOTE               0.46             62
  SMOTE + Tomek       0.43             63
  SMOTE + ENN         0.46             82

While recall improved, false alarms increased dramatically, making the
model unsuitable for real-world notifications. Consequently, Core ML was
not included in the final application.

## IoT Sensor Selection

PlantPal monitors the environmental conditions that most directly affect
photosynthesis.

  -----------------------------------------------------------------------
  Sensor                  Purpose                 Impact
  ----------------------- ----------------------- -----------------------
  KY-018 Photoresistor    Measure ambient light   Light provides the
                          intensity               energy required for
                                                  photosynthesis.

  DHT11                   Measure air temperature Temperature influences
                          and humidity            photosynthetic enzymes
                                                  while humidity affects
                                                  transpiration.

  YL-69                   Measure soil moisture   Water is essential for
                                                  photosynthesis and
                                                  healthy root function.

  DS1302 RTC              Timestamp readings      Enables historical
                                                  tracking and scheduled
                                                  sampling every 15
                                                  minutes.
  -----------------------------------------------------------------------

These sensors were selected because they provide the highest impact on
photosynthesis while keeping the hardware affordable and compact.

## Hardware Design Considerations

Correct sensor placement is essential for accurate measurements.

-   The KY-018 should face the surrounding environment and not be
    covered by leaves, otherwise light readings may be underestimated.
-   The DHT11 should be positioned away from leaves and the soil surface
    to measure ambient air rather than localised humidity.
-   The YL-69 should be inserted near the root zone while avoiding
    direct contact with the main stem.
-   The enclosure should provide enough spacing between sensors to
    minimise interference while remaining compact.

## Architecture Changes

The original prototype used Bluetooth communication between the ESP32
and iPhone, limiting monitoring to Bluetooth range.

The final architecture uses Wi-Fi. Each plant has its own dedicated
ESP32 device that uploads sensor readings to a cloud endpoint every 15
minutes. The iPhone retrieves the latest readings over the internet,
enabling continuous remote monitoring for multiple plants.

Bluetooth is only used during initial setup to provision Wi-Fi
credentials securely.

## Final Solution

PlantPal compares live sensor readings against plant-specific
environmental thresholds instead of relying on machine learning
predictions.

When adding a plant, the user enters its **species name**. The more
specific the species (for example, *Monstera deliciosa* instead of
simply *Monstera*), the more accurately Gemini can generate recommended
threshold ranges for:

-   Temperature
-   Humidity
-   Soil moisture
-   Light intensity

These thresholds are stored locally using SwiftData.

Each plant is paired with its own ESP32 device containing a KY-018,
DHT11, YL-69 and DS1302 RTC. The ESP32 uploads readings every 15
minutes, and the iPhone compares them against the stored thresholds.

If readings fall outside the recommended ranges, Apple's Foundation
Model generates a concise explanation and suggested actions.
Notifications are delivered locally, while the app also supports Dynamic
Type, VoiceOver and spoken announcements using AVFoundation.

## Frameworks Used

  Framework           Purpose
  ------------------- ------------------------------------------------------
  SwiftUI             User interface
  SwiftData           Store plant profiles, thresholds and latest readings
  FoundationModels    Generate natural-language explanations
  PhotosUI            Select plant images
  CoreBluetooth       ESP32 Wi-Fi provisioning
  AVFoundation        Speech synthesis
  BackgroundTasks     Background monitoring
  UserNotifications   Local notifications
  URLSession          Cloud communication and Gemini requests

## Limitations

-   The dataset is synthetic and unsuitable for training a
    production-quality classifier.
-   ESP32 supports **2.4 GHz Wi-Fi only** and cannot connect to 5
    GHz-only networks.
-   iOS Background Tasks cannot execute at guaranteed intervals.
-   The YL-69 sensor may corrode over time and require replacement or
    calibration.
-   Incorrect sensor placement, particularly blocked light sensors, can
    reduce measurement accuracy.
-   The current cloud endpoint is a placeholder and should be replaced
    with a secure production backend.
-   Additional long-term real-world data would improve future threshold
    validation and machine learning research.

## Conclusion

Although Core ML was ultimately excluded, the machine learning
investigation highlighted the limitations of the available dataset and
guided the project toward a more reliable solution.

PlantPal combines dedicated ESP32 IoT devices, environmental sensing,
cloud connectivity, Gemini-generated species-specific thresholds, and
Apple's Foundation Model to help users maintain the conditions required
for effective photosynthesis. By focusing on measurable environmental
factors instead of unreliable predictions, PlantPal delivers
transparent, practical, and extensible plant health monitoring.
