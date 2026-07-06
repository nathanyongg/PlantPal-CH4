#include <DHT.h>
#include <ThreeWire.h>
#include <RtcDS1302.h>
#include <WiFi.h>
#include <WebServer.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

#define DHT_PIN 4
#define DHT_TYPE DHT11

#define SOIL_PIN 34
#define LIGHT_PIN 35

#define DS1302_CLK 18
#define DS1302_DAT 19
#define DS1302_RST 5

// ESP32 Access Point Wi-Fi
const char* apSSID = "PlantMonitor";
const char* apPassword = "12345678";

// PlantPal BLE provisioning UUIDs. These must match BLEProtocol.swift.
#define PLANTPAL_SERVICE_UUID "7E570001-0000-1000-8000-00805F9B34FB"
#define WIFI_CREDENTIALS_CHAR_UUID "7E570002-0000-1000-8000-00805F9B34FB"
#define PROVISIONING_STATUS_CHAR_UUID "7E570003-0000-1000-8000-00805F9B34FB"
#define SENSOR_READING_CHAR_UUID "7E570004-0000-1000-8000-00805F9B34FB"

#define PROVISIONING_IDLE 0
#define PROVISIONING_CONNECTING 1
#define PROVISIONING_CONNECTED 2
#define PROVISIONING_FAILED 3

// Web server on port 80
WebServer server(80);
BLECharacteristic* provisioningStatusCharacteristic = nullptr;
BLECharacteristic* sensorReadingCharacteristic = nullptr;
bool bleClientConnected = false;
unsigned long lastBleReadingSentAt = 0;

// Soil calibration
const int DRY_SOIL = 4095;
const int WET_SOIL = 1200;

// Light calibration
const int BRIGHT_LIGHT = 0;
const int DARK_LIGHT = 4095;

DHT dht(DHT_PIN, DHT_TYPE);

ThreeWire myWire(DS1302_DAT, DS1302_CLK, DS1302_RST);
RtcDS1302<ThreeWire> rtc(myWire);

void setupBLE();
void setProvisioningStatus(uint8_t status);
void sendSensorReadingOverBLE();
void connectToWiFi(const String& ssid, const String& password);
String extractJsonString(const String& json, const String& key);
String getSensorReadingJson();
String getISODateTimeString(const RtcDateTime& dt);

class PlantPalServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* server) {
    bleClientConnected = true;
    Serial.println("BLE client connected");
  }

  void onDisconnect(BLEServer* server) {
    bleClientConnected = false;
    Serial.println("BLE client disconnected; restarting advertising");
    BLEDevice::startAdvertising();
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

  Serial.println("Starting ESP32 PlantPal sensor system...");

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

  // After first successful upload, you can comment this out
  rtc.SetDateTime(compiled);

  setupBLE();

  // Web page route
  server.on("/", handleRoot);

  // JSON API route
  server.on("/data", handleData);

  server.begin();
  Serial.println("Web server started");
}

void loop() {
  server.handleClient();

  if (bleClientConnected && millis() - lastBleReadingSentAt > 2000) {
    sendSensorReadingOverBLE();
    lastBleReadingSentAt = millis();
  }

  delay(10);
}

void setupBLE() {
  BLEDevice::init("PlantPal Sensor");

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

  service->start();

  BLEAdvertising* advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(PLANTPAL_SERVICE_UUID);
  advertising->setScanResponse(true);
  advertising->setMinPreferred(0x06);
  advertising->setMinPreferred(0x12);

  BLEDevice::startAdvertising();
  Serial.println("BLE advertising started as PlantPal Sensor");
  Serial.print("BLE service UUID: ");
  Serial.println(PLANTPAL_SERVICE_UUID);
}

void setProvisioningStatus(uint8_t status) {
  if (provisioningStatusCharacteristic == nullptr) {
    return;
  }

  provisioningStatusCharacteristic->setValue(&status, 1);
  provisioningStatusCharacteristic->notify();
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

void connectToWiFi(const String& ssid, const String& password) {
  Serial.print("Connecting to Wi-Fi SSID: ");
  Serial.println(ssid);
  setProvisioningStatus(PROVISIONING_CONNECTING);

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
    setProvisioningStatus(PROVISIONING_CONNECTED);
  } else {
    Serial.println("Wi-Fi connection failed");
    WiFi.disconnect(false);
    setProvisioningStatus(PROVISIONING_FAILED);
  }
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
  float humidity = dht.readHumidity();
  float temperature = dht.readTemperature();

  int soilValue = analogRead(SOIL_PIN);
  int lightValue = analogRead(LIGHT_PIN);

  int soilPercent = map(soilValue, DRY_SOIL, WET_SOIL, 0, 100);
  soilPercent = constrain(soilPercent, 0, 100);

  int lightPercent = map(lightValue, BRIGHT_LIGHT, DARK_LIGHT, 100, 0);
  lightPercent = constrain(lightPercent, 0, 100);

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
  html += String(temperature);
  html += " &deg;C</p>";

  html += "<p><b>Humidity:</b> ";
  html += String(humidity);
  html += " %</p>";

  html += "<p><b>Soil Raw:</b> ";
  html += String(soilValue);
  html += "</p>";

  html += "<p><b>Soil Moisture:</b> ";
  html += String(soilPercent);
  html += " %</p>";

  html += "<p><b>Light Raw:</b> ";
  html += String(lightValue);
  html += "</p>";

  html += "<p><b>Light Level:</b> ";
  html += String(lightPercent);
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

String getSensorReadingJson() {
  float humidity = dht.readHumidity();
  float temperature = dht.readTemperature();

  if (isnan(humidity)) {
    humidity = 0;
  }
  if (isnan(temperature)) {
    temperature = 0;
  }

  int soilValue = analogRead(SOIL_PIN);
  int lightValue = analogRead(LIGHT_PIN);

  int soilPercent = map(soilValue, DRY_SOIL, WET_SOIL, 0, 100);
  soilPercent = constrain(soilPercent, 0, 100);

  RtcDateTime now = rtc.GetDateTime();

  String json = "{";
  json += "\"rtc_timestamp\":\"" + getISODateTimeString(now) + "\",";
  json += "\"t\":" + String(temperature, 1) + ",";
  json += "\"h\":" + String(humidity, 1) + ",";
  json += "\"m\":" + String(soilPercent) + ",";
  json += "\"l\":" + String(lightValue);
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
  char datestring[25];

  snprintf_P(
    datestring,
    sizeof(datestring),
    PSTR("%04u-%02u-%02uT%02u:%02u:%02uZ"),
    dt.Year(),
    dt.Month(),
    dt.Day(),
    dt.Hour(),
    dt.Minute(),
    dt.Second()
  );

  return String(datestring);
}
