#include <DHT.h>
#include <ThreeWire.h>
#include <RtcDS1302.h>
#include <WiFi.h>
#include <WebServer.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// ESP32-C3 Super Mini wiring
#define DHT_PIN 3
#define DHT_TYPE DHT11

#define SOIL_PIN 0      // YL-69 AO
#define LIGHT_PIN 1     // KY-018 S/AO

#define DS1302_CLK 4
#define DS1302_DAT 5
#define DS1302_RST 6

// ESP32 Access Point Wi-Fi
const char* apSSID = "PlantMonitor";
const char* apPassword = "12345678";

// PlantPal BLE provisioning UUIDs. These must match BLEProtocol.swift.
#define PLANTPAL_SERVICE_UUID "7E570001-0000-1000-8000-00805F9B34FB"
#define WIFI_CREDENTIALS_CHAR_UUID "7E570002-0000-1000-8000-00805F9B34FB"
#define PROVISIONING_STATUS_CHAR_UUID "7E570003-0000-1000-8000-00805F9B34FB"
#define SENSOR_READING_CHAR_UUID "7E570004-0000-1000-8000-00805F9B34FB"
#define NETWORK_INFO_CHAR_UUID "7E570005-0000-1000-8000-00805F9B34FB"

#define PROVISIONING_IDLE 0
#define PROVISIONING_CONNECTING 1
#define PROVISIONING_CONNECTED 2
#define PROVISIONING_FAILED 3

// Web server on port 80
WebServer server(80);
BLECharacteristic* provisioningStatusCharacteristic = nullptr;
BLECharacteristic* sensorReadingCharacteristic = nullptr;
BLECharacteristic* networkInfoCharacteristic = nullptr;
bool bleClientConnected = false;
unsigned long lastBleReadingSentAt = 0;

// Soil calibration
const int DRY_SOIL = 4095;
const int WET_SOIL = 1200;

// Light calibration for the KY-018 on this ESP32-C3 setup.
// The raw ADC value rises as the room gets brighter, so the app-facing
// percentage should rise with it too: dark = 0%, bright = 100%.
const int DARK_LIGHT = 0;
const int BRIGHT_LIGHT = 4095;

const unsigned long DHT_SAMPLE_INTERVAL_MS = 2000;
float cachedTemperature = NAN;
float cachedHumidity = NAN;
bool hasTemperatureReading = false;
bool hasHumidityReading = false;
unsigned long lastDhtReadAt = 0;

int cachedSoilRaw = 0;
int cachedLightRaw = 0;
int cachedSoilPercent = 0;
int cachedLightPercent = 0;

DHT dht(DHT_PIN, DHT_TYPE);

ThreeWire myWire(DS1302_DAT, DS1302_CLK, DS1302_RST);
RtcDS1302<ThreeWire> rtc(myWire);

void setupBLE();
void setProvisioningStatus(uint8_t status);
void sendSensorReadingOverBLE();
void sendNetworkInfoOverBLE();
void connectToWiFi(const String& ssid, const String& password);
String extractJsonString(const String& json, const String& key);
String getSensorReadingJson();
String getNetworkInfoJson();
String getISODateTimeString(const RtcDateTime& dt);
void updateSensorCache(bool forceDht);
String formatFloatOrNull(float value, int decimals);

class PlantPalServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* server) {
    bleClientConnected = true;
    Serial.println("BLE client connected");
  }

  void onDisconnect(BLEServer* server) {
    bleClientConnected = false;
    Serial.println("BLE client disconnected; restarting advertising");
    BLEDevice::getAdvertising()->start();
  }
};

class WiFiCredentialsCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* characteristic) {
    String payload = String(characteristic->getValue().c_str());

    Serial.print("Received BLE Wi-Fi credentials payload: ");
    Serial.println(payload);

    String ssid = extractJsonString(payload, "ssid");
    String password = extractJsonString(payload, "password");

    if (ssid.length() == 0) {
      Serial.println("BLE credentials missing SSID");
      setProvisioningStatus(PROVISIONING_FAILED);
      return;
    }

    connectToWiFi(ssid, password);
  }
};

void setup() {
  Serial.begin(115200);
  delay(1000);

  Serial.println("Starting PlantPal on ESP32-C3 Super Mini...");

  // Start ESP32 as Wi-Fi Access Point
  WiFi.mode(WIFI_AP_STA);
  WiFi.softAP(apSSID, apPassword);

  Serial.println("Access Point started!");
  Serial.print("Wi-Fi Name: ");
  Serial.println(apSSID);
  Serial.print("Password: ");
  Serial.println(apPassword);
  Serial.print("Open this in browser: http://");
  Serial.println(WiFi.softAPIP());

  // Start sensors
  dht.begin();
  delay(1500);
  updateSensorCache(true);

  // Start RTC
  rtc.Begin();

  RtcDateTime compiled = RtcDateTime(__DATE__, __TIME__);

  if (rtc.GetIsWriteProtected()) {
    Serial.println("RTC write protection disabled");
    rtc.SetIsWriteProtected(false);
  }

  if (!rtc.GetIsRunning()) {
    Serial.println("RTC started");
    rtc.SetIsRunning(true);
  }

  // Sets the DS1302 to the upload computer's current Bali/WITA time.
  // After one successful upload, comment this out so every reboot does
  // not reset the RTC back to the old compile time.
  // rtc.SetDateTime(compiled);

  setupBLE();

  // Web page route
  server.on("/", handleRoot);

  // JSON API route
  server.on("/data", handleData);
  server.on("/latest", handleData);

  server.begin();
  Serial.println("Web server started");
}

void loop() {
  updateSensorCache(false);
  server.handleClient();

  if (bleClientConnected && millis() - lastBleReadingSentAt > 1000) {
    sendSensorReadingOverBLE();
    lastBleReadingSentAt = millis();
  }

  delay(10);
}

void setupBLE() {
  BLEDevice::init("PlantPal Sensor");
  BLEDevice::setMTU(185);

  BLEServer* server = BLEDevice::createServer();
  server->setCallbacks(new PlantPalServerCallbacks());

  BLEService* service = server->createService(PLANTPAL_SERVICE_UUID);

  BLECharacteristic* credentialsCharacteristic = service->createCharacteristic(
    WIFI_CREDENTIALS_CHAR_UUID,
    BLECharacteristic::PROPERTY_WRITE
  );
  credentialsCharacteristic->setCallbacks(new WiFiCredentialsCallbacks());

  provisioningStatusCharacteristic = service->createCharacteristic(
    PROVISIONING_STATUS_CHAR_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  provisioningStatusCharacteristic->addDescriptor(new BLE2902());
  setProvisioningStatus(PROVISIONING_IDLE);

  sensorReadingCharacteristic = service->createCharacteristic(
    SENSOR_READING_CHAR_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  sensorReadingCharacteristic->addDescriptor(new BLE2902());
  sensorReadingCharacteristic->setValue(getSensorReadingJson().c_str());

  networkInfoCharacteristic = service->createCharacteristic(
    NETWORK_INFO_CHAR_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  networkInfoCharacteristic->addDescriptor(new BLE2902());
  networkInfoCharacteristic->setValue(getNetworkInfoJson().c_str());

  service->start();

  BLEAdvertising* advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(PLANTPAL_SERVICE_UUID);
  advertising->setScanResponse(true);
  advertising->setMinPreferred(0x06);
  advertising->setMinPreferred(0x12);

  advertising->start();
  Serial.println("BLE advertising started as PlantPal Sensor");
  Serial.print("BLE service UUID: ");
  Serial.println(PLANTPAL_SERVICE_UUID);
}

void setProvisioningStatus(uint8_t status) {
  if (provisioningStatusCharacteristic == nullptr) {
    return;
  }

  provisioningStatusCharacteristic->setValue(&status, 1);
  if (bleClientConnected) {
    provisioningStatusCharacteristic->notify();
  }
}

void sendSensorReadingOverBLE() {
  if (sensorReadingCharacteristic == nullptr) {
    return;
  }

  String json = getSensorReadingJson();
  sensorReadingCharacteristic->setValue(json.c_str());
  sensorReadingCharacteristic->notify();

  Serial.print("Sent BLE sensor reading: ");
  Serial.println(json);
}

void sendNetworkInfoOverBLE() {
  if (networkInfoCharacteristic == nullptr) {
    return;
  }

  String json = getNetworkInfoJson();
  networkInfoCharacteristic->setValue(json.c_str());
  if (bleClientConnected) {
    networkInfoCharacteristic->notify();
  }

  Serial.print("Sent BLE network info: ");
  Serial.println(json);
}

void connectToWiFi(const String& ssid, const String& password) {
  Serial.print("Connecting to Wi-Fi SSID: ");
  Serial.println(ssid);
  setProvisioningStatus(PROVISIONING_CONNECTING);

  WiFi.disconnect(false, false);
  delay(100);
  WiFi.begin(ssid.c_str(), password.c_str());

  unsigned long startedAt = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - startedAt < 20000) {
    delay(500);
    Serial.print(".");
  }
  Serial.println();

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("Wi-Fi connected!");
    Serial.print("Station IP address: ");
    Serial.println(WiFi.localIP());
    sendNetworkInfoOverBLE();
    setProvisioningStatus(PROVISIONING_CONNECTED);
  } else {
    Serial.println("Wi-Fi connection failed");
    WiFi.disconnect(false);
    setProvisioningStatus(PROVISIONING_FAILED);
  }
}

String getNetworkInfoJson() {
  IPAddress ip = WiFi.status() == WL_CONNECTED ? WiFi.localIP() : WiFi.softAPIP();
  String baseURL = "http://" + ip.toString();

  String json = "{";
  json += "\"ip\":\"" + ip.toString() + "\",";
  json += "\"base_url\":\"" + baseURL + "\",";
  json += "\"data_url\":\"" + baseURL + "/latest\"";
  json += "}";

  return json;
}

String extractJsonString(const String& json, const String& key) {
  String quotedKey = "\"" + key + "\"";
  int keyIndex = json.indexOf(quotedKey);
  if (keyIndex < 0) {
    return "";
  }

  int colonIndex = json.indexOf(':', keyIndex + quotedKey.length());
  if (colonIndex < 0) {
    return "";
  }

  int startQuote = json.indexOf('"', colonIndex + 1);
  if (startQuote < 0) {
    return "";
  }

  String value = "";
  bool escaped = false;
  for (int i = startQuote + 1; i < json.length(); i++) {
    char c = json.charAt(i);

    if (escaped) {
      value += c;
      escaped = false;
      continue;
    }

    if (c == '\\') {
      escaped = true;
      continue;
    }

    if (c == '"') {
      return value;
    }

    value += c;
  }

  return "";
}

void handleRoot() {
  updateSensorCache(false);

  RtcDateTime now = rtc.GetDateTime();

  String html = "";
  html += "<!DOCTYPE html>";
  html += "<html>";
  html += "<head>";
  html += "<meta name='viewport' content='width=device-width, initial-scale=1.0'>";
  html += "<meta http-equiv='refresh' content='2'>";
  html += "<title>Plant Monitor</title>";
  html += "<style>";
  html += "body{font-family:Arial;background:#f4f7f2;padding:20px;}";
  html += ".card{background:white;padding:20px;border-radius:12px;max-width:400px;margin:auto;box-shadow:0 2px 10px rgba(0,0,0,0.1);}";
  html += "h1{color:#2f5d50;}";
  html += "p{font-size:18px;}";
  html += "</style>";
  html += "</head>";
  html += "<body>";
  html += "<div class='card'>";
  html += "<h1>Plant Monitor</h1>";

  html += "<p><b>Time:</b> ";
  html += getDateTimeString(now);
  html += "</p>";

  html += "<p><b>Temperature:</b> ";
  html += hasTemperatureReading ? String(cachedTemperature, 1) : "Waiting for DHT";
  html += " &deg;C</p>";

  html += "<p><b>Humidity:</b> ";
  html += hasHumidityReading ? String(cachedHumidity, 1) : "Waiting for DHT";
  html += " %</p>";

  html += "<p><b>Soil Raw:</b> ";
  html += String(cachedSoilRaw);
  html += "</p>";

  html += "<p><b>Soil Moisture:</b> ";
  html += String(cachedSoilPercent);
  html += " %</p>";

  html += "<p><b>Light Raw:</b> ";
  html += String(cachedLightRaw);
  html += "</p>";

  html += "<p><b>Light Level:</b> ";
  html += String(cachedLightPercent);
  html += " %</p>";

  html += "<p><small>Auto-refreshes every 2 seconds</small></p>";
  html += "</div>";
  html += "</body>";
  html += "</html>";

  server.send(200, "text/html", html);
}

void handleData() {
  server.send(200, "application/json", getSensorReadingJson());
}

void updateSensorCache(bool forceDht) {
  cachedSoilRaw = analogRead(SOIL_PIN);
  cachedLightRaw = analogRead(LIGHT_PIN);

  cachedSoilPercent = map(cachedSoilRaw, DRY_SOIL, WET_SOIL, 0, 100);
  cachedSoilPercent = constrain(cachedSoilPercent, 0, 100);

  cachedLightPercent = map(cachedLightRaw, DARK_LIGHT, BRIGHT_LIGHT, 0, 100);
  cachedLightPercent = constrain(cachedLightPercent, 0, 100);

  unsigned long now = millis();
  bool shouldReadDht = forceDht
    || lastDhtReadAt == 0
    || now - lastDhtReadAt >= DHT_SAMPLE_INTERVAL_MS;

  if (!shouldReadDht) {
    return;
  }

  lastDhtReadAt = now;
  float humidity = dht.readHumidity();
  float temperature = dht.readTemperature();

  if (!isnan(humidity)) {
    cachedHumidity = humidity;
    hasHumidityReading = true;
  }

  if (!isnan(temperature)) {
    cachedTemperature = temperature;
    hasTemperatureReading = true;
  }

  if (isnan(humidity) || isnan(temperature)) {
    Serial.println("DHT read failed; keeping the last valid temperature/humidity.");
  }
}

String formatFloatOrNull(float value, int decimals) {
  if (isnan(value)) {
    return "null";
  }

  return String(value, decimals);
}

String getSensorReadingJson() {
  updateSensorCache(false);

  RtcDateTime now = rtc.GetDateTime();

  String json = "{";
  json += "\"firmware_version\":2,";
  json += "\"rtc_timestamp\":\"" + getISODateTimeString(now) + "\",";
  json += "\"t\":" + formatFloatOrNull(cachedTemperature, 1) + ",";
  json += "\"h\":" + formatFloatOrNull(cachedHumidity, 1) + ",";
  json += "\"m\":" + String(cachedSoilPercent) + ",";
  json += "\"l\":" + String(cachedLightPercent) + ",";
  json += "\"soil_raw\":" + String(cachedSoilRaw) + ",";
  json += "\"light_raw\":" + String(cachedLightRaw) + ",";
  json += "\"dht_ok\":";
  json += (hasTemperatureReading && hasHumidityReading) ? "true" : "false";
  json += "}";

  return json;
}

String getDateTimeString(const RtcDateTime& dt) {
  char datestring[25];

  snprintf_P(
    datestring,
    sizeof(datestring),
    PSTR("%04u-%02u-%02u %02u:%02u:%02u"),
    dt.Year(),
    dt.Month(),
    dt.Day(),
    dt.Hour(),
    dt.Minute(),
    dt.Second()
  );

  return String(datestring);
}

String getISODateTimeString(const RtcDateTime& dt) {
  char datestring[32];

  snprintf_P(
    datestring,
    sizeof(datestring),
    PSTR("%04u-%02u-%02uT%02u:%02u:%02u+08:00"),
    dt.Year(),
    dt.Month(),
    dt.Day(),
    dt.Hour(),
    dt.Minute(),
    dt.Second()
  );

  return String(datestring);
}
