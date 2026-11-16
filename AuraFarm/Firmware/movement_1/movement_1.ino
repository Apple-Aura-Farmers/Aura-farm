// Phase 1 / Test 1: one servo endurance test (servo Z on GPIO20).
// Board: ESP32-C6 Super Mini, Arduino-ESP32 core 3.x, USB CDC On Boot: Enabled.
// PWM: built-in LEDC API (ledcAttach / ledcWrite / ledcDetach). No Bluetooth, no Wi-Fi.

#include <Preferences.h>
#include "esp_system.h"

// ---------------- Settings ----------------
const int  SERVO_PIN  = 20;
const char SERVO_NAME = 'Z';

const int MIN_ANGLE    = 30;    // sweep range (deg)
const int MAX_ANGLE    = 150;
const int START_ANGLE  = 90;    // first position after boot
const int STEP_DEG     = 2;     // move 2 deg ...
const int STEP_MS      = 20;    // ... every 20 ms
const int SETTLE_MS    = 300;   // hold after reaching target, before PWM off
const int GAP_MS       = 500;   // rest with PWM off between moves
const int BOOT_WAIT_MS = 500;   // pause after boot before first attach
const int CYCLES       = 200;   // 1 cycle = MIN->MAX then MAX->MIN

const int PULSE_MIN_US = 500;   // pulse width at 0 deg (typical SG90)
const int PULSE_MAX_US = 2400;  // pulse width at 180 deg

const int PWM_FREQ_HZ = 50;
const int PWM_BITS    = 14;

const unsigned long SERIAL_WAIT_MS = 5000;  // wait this long for Serial Monitor at boot
const int LOG_SIZE = 10;                    // boots kept in the saved boot log

// ---------------- State ----------------
int  currentAngle = START_ANGLE;  // last commanded angle
int  cycle = 0;
bool done = false;
int  thisReason = 0;

struct BootLog {
  uint32_t boots;
  uint8_t  reason[LOG_SIZE];
  uint16_t cycle[LOG_SIZE];
};
BootLog bootLog;
Preferences prefs;

// ---------------- Reset reason ----------------
const char* resetName(int r) {
  switch (r) {
    case ESP_RST_POWERON:   return "ESP_RST_POWERON";
    case ESP_RST_BROWNOUT:  return "ESP_RST_BROWNOUT";
    case ESP_RST_EXT:       return "ESP_RST_EXT";
    case ESP_RST_SW:        return "ESP_RST_SW";
    case ESP_RST_PANIC:     return "ESP_RST_PANIC";
    case ESP_RST_INT_WDT:   return "ESP_RST_INT_WDT";
    case ESP_RST_TASK_WDT:  return "ESP_RST_TASK_WDT";
    case ESP_RST_WDT:       return "ESP_RST_WDT";
    case ESP_RST_DEEPSLEEP: return "ESP_RST_DEEPSLEEP";
    case ESP_RST_SDIO:      return "ESP_RST_SDIO";
    case ESP_RST_USB:       return "ESP_RST_USB";
    case ESP_RST_JTAG:      return "ESP_RST_JTAG";
    case ESP_RST_UNKNOWN:   return "ESP_RST_UNKNOWN";
    default:                return "OTHER";
  }
}

// ---------------- Saved boot log (flash) ----------------
void saveLog() {
  prefs.putBytes("log", &bootLog, sizeof(bootLog));
}

void printLog() {
  Serial.println("---- saved boot log (oldest first) ----");
  uint32_t first = bootLog.boots > LOG_SIZE ? bootLog.boots - LOG_SIZE + 1 : 1;
  for (uint32_t b = first; b <= bootLog.boots; b++) {
    int i = b % LOG_SIZE;
    Serial.printf("boot %lu | reset reason: %s | reached cycle %u/%d\n",
                  (unsigned long)b, resetName(bootLog.reason[i]), bootLog.cycle[i], CYCLES);
  }
  Serial.println("(send any key to reprint, 'c' to clear)");
  Serial.println("---------------------------------------");
}

// Called between cycles: any key reprints the boot log, 'c' clears it first.
void checkSerial() {
  bool any = false, clear = false;
  while (Serial.available()) {
    char c = Serial.read();
    if (c == 'c' || c == 'C') clear = true;
    if (c != '\n' && c != '\r') any = true;
  }
  if (!any) return;
  if (clear) {
    memset(&bootLog, 0, sizeof(bootLog));
    bootLog.boots = 1;  // keep only the current boot
    bootLog.reason[1] = thisReason;
    bootLog.cycle[1] = cycle;
    saveLog();
    Serial.println("Boot log cleared.");
  }
  printLog();
}

// ---------------- Servo ----------------
uint32_t angleToDuty(int angle) {
  uint32_t us = PULSE_MIN_US + (uint32_t)(PULSE_MAX_US - PULSE_MIN_US) * angle / 180;
  uint32_t periodUs = 1000000UL / PWM_FREQ_HZ;
  return us * ((1UL << PWM_BITS) - 1) / periodUs;
}

// Start PWM at the last commanded angle so the servo does not twitch.
void servoOn() {
  if (!ledcAttach(SERVO_PIN, PWM_FREQ_HZ, PWM_BITS)) {
    Serial.println("ERROR: ledcAttach failed");
  }
  ledcWrite(SERVO_PIN, angleToDuty(currentAngle));
}

// Stop PWM and hold the signal line low (no pulses = servo idle).
void servoOff() {
  ledcDetach(SERVO_PIN);
  pinMode(SERVO_PIN, OUTPUT);
  digitalWrite(SERVO_PIN, LOW);
}

void logMove(const char* phase, int target) {
  Serial.printf("[%9.3f s] T1 cycle %d/%d | servo %c (GPIO%d) | -> %d deg | %s\n",
                millis() / 1000.0, cycle, CYCLES, SERVO_NAME, SERVO_PIN, target, phase);
}

// One full move: PWM on, small steps to target, settle, PWM off, rest.
void moveTo(int target) {
  logMove("start", target);
  servoOn();
  while (currentAngle != target) {
    delay(STEP_MS);
    currentAngle += constrain(target - currentAngle, -STEP_DEG, STEP_DEG);
    ledcWrite(SERVO_PIN, angleToDuty(currentAngle));
  }
  delay(SETTLE_MS);
  servoOff();
  logMove("end", target);
  delay(GAP_MS);
}

// ---------------- Main ----------------
void setup() {
  Serial.begin(115200);
  unsigned long t0 = millis();
  while (!Serial && millis() - t0 < SERIAL_WAIT_MS) delay(10);

  thisReason = esp_reset_reason();

  // Record this boot in the saved boot log.
  prefs.begin("t1log", false);
  if (prefs.getBytes("log", &bootLog, sizeof(bootLog)) != sizeof(bootLog)) {
    memset(&bootLog, 0, sizeof(bootLog));
  }
  bootLog.boots++;
  bootLog.reason[bootLog.boots % LOG_SIZE] = thisReason;
  bootLog.cycle[bootLog.boots % LOG_SIZE] = 0;
  saveLog();

  Serial.println();
  Serial.println("=== Phase 1 / Test 1: one servo ===");
  Serial.printf("Reset reason: %s (%d)\n", resetName(thisReason), thisReason);
  Serial.printf("Servo %c on GPIO%d | range %d-%d deg | step %d deg / %d ms | settle %d ms | gap %d ms | cycles %d\n",
                SERVO_NAME, SERVO_PIN, MIN_ANGLE, MAX_ANGLE, STEP_DEG, STEP_MS, SETTLE_MS, GAP_MS, CYCLES);
  printLog();

  // Attach the servo (only one in this test), after a pause.
  delay(BOOT_WAIT_MS);
  Serial.printf("[%9.3f s] startup | servo %c (GPIO%d) | attach at %d deg (one direct jump, position unknown)\n",
                millis() / 1000.0, SERVO_NAME, SERVO_PIN, START_ANGLE);
  servoOn();
  delay(SETTLE_MS);
  servoOff();
  delay(GAP_MS);
}

void loop() {
  checkSerial();
  if (done) {
    delay(100);
    return;
  }

  cycle++;
  moveTo(MAX_ANGLE);
  moveTo(MIN_ANGLE);

  bootLog.cycle[bootLog.boots % LOG_SIZE] = cycle;
  saveLog();

  if (cycle >= CYCLES) {
    done = true;
    Serial.printf("[%9.3f s] TEST 1 DONE: %d cycles, no restart during this boot\n",
                  millis() / 1000.0, CYCLES);
  }
}
