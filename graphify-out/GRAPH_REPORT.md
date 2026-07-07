# Graph Report - .  (2026-07-06)

## Corpus Check
- cluster-only mode — file stats not available

## Summary
- 413 nodes · 788 edges · 23 communities
- Extraction: 96% EXTRACTED · 4% INFERRED · 0% AMBIGUOUS · INFERRED: 35 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `b3fe3b67`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- [[_COMMUNITY_Community 0|Community 0]]
- [[_COMMUNITY_Community 1|Community 1]]
- [[_COMMUNITY_Community 2|Community 2]]
- [[_COMMUNITY_Community 3|Community 3]]
- [[_COMMUNITY_Community 4|Community 4]]
- [[_COMMUNITY_Community 5|Community 5]]
- [[_COMMUNITY_Community 6|Community 6]]
- [[_COMMUNITY_Community 7|Community 7]]
- [[_COMMUNITY_Community 8|Community 8]]
- [[_COMMUNITY_Community 9|Community 9]]
- [[_COMMUNITY_Community 10|Community 10]]
- [[_COMMUNITY_Community 11|Community 11]]
- [[_COMMUNITY_Community 12|Community 12]]
- [[_COMMUNITY_Community 13|Community 13]]
- [[_COMMUNITY_Community 14|Community 14]]
- [[_COMMUNITY_Community 15|Community 15]]
- [[_COMMUNITY_Community 16|Community 16]]

## God Nodes (most connected - your core abstractions)
1. `View` - 36 edges
2. `PlantProfile` - 29 edges
3. `ESP32BLEManager` - 28 edges
4. `SensorReading` - 26 edges
5. `AlertLevel` - 21 edges
6. `DetectionResult` - 19 edges
7. `PlantHealthTestView` - 18 edges
8. `SwiftUI` - 17 edges
9. `SensorStatus` - 16 edges
10. `PlantCardData` - 15 edges

## Surprising Connections (you probably didn't know these)
- `ContentView` --references--> `View`  [EXTRACTED]
  PlantPal-CH4/ios/ContentView.swift → PlantPal-CH4/ios/Views/Utility/TextSize.swift
- `PlantHealthMonitor` --calls--> `PlantHealthDetector`  [INFERRED]
  PlantPal-CH4/ios/Monitoring/PlantHealthMonitor.swift → PlantPal-CH4/ios/Detection/PlantHealthDetector.swift
- `PlantHealthTestView` --calls--> `PlantHealthDetector`  [INFERRED]
  PlantPal-CH4/ios/Test/PlantHealthTestView.swift → PlantPal-CH4/ios/Detection/PlantHealthDetector.swift
- `PlantPipelineViewModel` --calls--> `PlantHealthDetector`  [INFERRED]
  PlantPal-CH4/ios/Views/PlantDetailView.swift → PlantPal-CH4/ios/Detection/PlantHealthDetector.swift
- `PlantHealthMonitor` --calls--> `PlantDataService`  [INFERRED]
  PlantPal-CH4/ios/Monitoring/PlantHealthMonitor.swift → PlantPal-CH4/ios/Networking/PlantDataService.swift

## Import Cycles
- None detected.

## Communities (23 total, 0 thin omitted)

### Community 0 - "Community 0"
Cohesion: 0.07
Nodes (33): CBCentralManager, CBCentralManagerDelegate, CBCharacteristic, CBManagerState, CBPeripheral, CBPeripheralDelegate, CBService, Combine (+25 more)

### Community 1 - "Community 1"
Cohesion: 0.13
Nodes (18): MetricRow, PlantCardData, PlantDetailView, PlantMetric, PlantPipelineViewModel, SensorKind, humidity, light (+10 more)

### Community 2 - "Community 2"
Cohesion: 0.10
Nodes (21): FoundationModels, LocalizedError, DetectionResult, Bool, Date, PlantHealthMonitor, Bool, Date (+13 more)

### Community 3 - "Community 3"
Cohesion: 0.07
Nodes (25): App, CaseIterable, Content, DynamicTypeSize, ContentView, PlantPalApp, ModelContainer, SettingsView (+17 more)

### Community 4 - "Community 4"
Cohesion: 0.10
Nodes (18): Binding, ButtonStyle, Configuration, PlantHealthTestView, ClosedRange, Color, Double, String (+10 more)

### Community 5 - "Community 5"
Cohesion: 0.10
Nodes (22): CodingKey, Decodable, Decoder, KeyedDecodingContainer, String, CodingKeys, createdAt, h (+14 more)

### Community 6 - "Community 6"
Cohesion: 0.09
Nodes (17): AVFoundation, PhotosPickerItem, PhotosUI, PlantSetupView, SetupPhase, done, fetchingThresholds, idle (+9 more)

### Community 7 - "Community 7"
Cohesion: 0.15
Nodes (17): PlantClassifier, PlantHealthDetector, Double, PlantProfile, Bool, Data, Date, String (+9 more)

### Community 8 - "Community 8"
Cohesion: 0.17
Nodes (14): Comparable, Int, AlertLevel, critical, healthy, warning, Bool, PlantHealthLogEntry (+6 more)

### Community 9 - "Community 9"
Cohesion: 0.18
Nodes (13): Codable, PlantThresholds, Double, GeminiService, GeminiServiceError, apiError, emptyResponse, invalidResponse (+5 more)

### Community 10 - "Community 10"
Cohesion: 0.18
Nodes (10): Context, NSObject, CameraView, Coordinator, Any, UIImage, UIImagePickerController, UIImagePickerControllerDelegate (+2 more)

### Community 11 - "Community 11"
Cohesion: 0.17
Nodes (7): BackgroundTasks, Foundation, SecretsManager, String, RootTabView, SwiftData, UserNotifications

### Community 12 - "Community 12"
Cohesion: 0.20
Nodes (7): BGAppRefreshTask, ModelContext, AutoRefreshScheduler, Bool, ModelContainer, TimeInterval, Timer

### Community 13 - "Community 13"
Cohesion: 0.21
Nodes (10): PlantDataService, PlantDataServiceError, invalidResponse, noReadingsYet, serverError, unauthorized, Int, String (+2 more)

### Community 14 - "Community 14"
Cohesion: 0.17
Nodes (10): Encodable, ProvisioningStatus, connected, connecting, failed, idle, Data, String (+2 more)

### Community 15 - "Community 15"
Cohesion: 0.24
Nodes (7): OnboardingPage, OnboardingView, Bool, Color, Int, String, Void

### Community 16 - "Community 16"
Cohesion: 0.24
Nodes (8): Font, Colors, Radius, Spacing, CGFloat, Color, ColorScheme, Typography

## Knowledge Gaps
- **54 isolated node(s):** `idle`, `connecting`, `connected`, `failed`, `disconnected` (+49 more)
  These have ≤1 connection - possible missing edges or undocumented components.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `SensorReading` connect `Community 5` to `Community 0`, `Community 1`, `Community 2`, `Community 7`, `Community 8`, `Community 9`, `Community 13`?**
  _High betweenness centrality (0.191) - this node is a cross-community bridge._
- **Why does `View` connect `Community 4` to `Community 1`, `Community 3`, `Community 6`, `Community 7`, `Community 8`, `Community 11`, `Community 15`?**
  _High betweenness centrality (0.170) - this node is a cross-community bridge._
- **Why does `ESP32BLEManager` connect `Community 0` to `Community 10`, `Community 2`, `Community 4`, `Community 5`?**
  _High betweenness centrality (0.153) - this node is a cross-community bridge._
- **What connects `idle`, `connecting`, `connected` to the rest of the system?**
  _54 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Community 0` be split into smaller, more focused modules?**
  _Cohesion score 0.0666049953746531 - nodes in this community are weakly interconnected._
- **Should `Community 1` be split into smaller, more focused modules?**
  _Cohesion score 0.13086770981507823 - nodes in this community are weakly interconnected._
- **Should `Community 2` be split into smaller, more focused modules?**
  _Cohesion score 0.1036036036036036 - nodes in this community are weakly interconnected._