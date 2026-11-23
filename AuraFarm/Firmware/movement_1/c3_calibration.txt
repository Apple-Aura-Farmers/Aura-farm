// Phase 1b: calibrate how far X and Y can travel on the linear actuator (X GPIO3, Y GPIO4),
// and record a home position each axis returns to.
// Board: ESP32-C3 Super Mini, Arduino-ESP32 core 3.x, USB CDC On Boot: Enabled.
// C3 runs from the Mac's USB. Servos run from the HW-131 rail (separate power, shared ground).
// PWM: built-in LEDC API (ledcAttach / ledcWrite / ledcDetach). No Bluetooth, no Wi-Fi.
// Nothing moves at startup. Servos only move on commands typed in the Serial Monitor
// (line ending: Newline). Only the selected servo ever moves, one move at a time,
// signal off after every move, then a rest before the next command is handled.

#include <Preferences.h>
#include "esp_system.h"

// ---------------- Settings ----------------
const int  NUM_SERVOS = 2;
const int  SERVO_PINS[NUM_SERVOS]  = {3, 4};
const char SERVO_NAMES[NUM_SERVOS] = {'X', 'Y'};

const int CENTER_ANGLE = 90;    // middle of the servo range
const int SAFE_MIN     = 0;     // absolute limits: no command can go outside these
const int SAFE_MAX     = 180;   // (0-180 checked clean on these two servos with 'sweep')
const int SMALL_NUDGE  = 1;     // '+' / '-'
const int BIG_NUDGE    = 5;     // '>' / '<'
const int STEP_DEG     = 2;     // longer moves: 2 deg ...
const int STEP_MS      = 20;    // ... every 20 ms
const int SETTLE_MS    = 300;   // hold after reaching target, before signal off
const int GAP_MS       = 500;   // rest with signal off after every move

const int PULSE_MIN_US = 500;   // pulse width at 0 deg (typical SG90)
const int PULSE_MAX_US = 2400;  // pulse width at 180 deg

const int PWM_FREQ_HZ = 50;
const int PWM_BITS    = 14;

const unsigned long SERIAL_WAIT_MS = 5000;  // wait this long for Serial Monitor at boot

// 'sweep' test: slowly checks a servo's full 0-180 deg range (run it on any new servo before
// trusting 0-180). Any key typed during the sweep stops it immediately (signal off).
const int SWEEP_MIN     = 0;
const int SWEEP_MAX     = 180;
const int SWEEP_STEP_MS = 50;   // 1 deg every 50 ms (about 9 s for 0 -> 180)

// ---------------- State ----------------
int  selected = -1;                          // -1 = no servo selected yet
int  currentAngle[NUM_SERVOS] = {CENTER_ANGLE, CENTER_ANGLE};
bool known[NUM_SERVOS]        = {false, false};  // position unknown until 'center'
int  minAngle[NUM_SERVOS]     = {-1, -1};        // -1 = not recorded
int  maxAngle[NUM_SERVOS]     = {-1, -1};
int  homeAngle[NUM_SERVOS]    = {-1, -1};        // -1 = not set (home defaults to CENTER_ANGLE)
Preferences prefs;
String line;

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

// ---------------- Helpers ----------------
void stamp() {
  Serial.printf("[%9.3f s] ", millis() / 1000.0);
}

uint32_t angleToDuty(int angle) {
  uint32_t us = PULSE_MIN_US + (uint32_t)(PULSE_MAX_US - PULSE_MIN_US) * angle / 180;
  uint32_t periodUs = 1000000UL / PWM_FREQ_HZ;
  return us * ((1UL << PWM_BITS) - 1) / periodUs;
}

void printStatus() {
  Serial.println("---- status ----");
  for (int i = 0; i < NUM_SERVOS; i++) {
    Serial.printf("servo %c (GPIO%d) | angle: ", SERVO_NAMES[i], SERVO_PINS[i]);
    if (known[i]) Serial.printf("%d deg", currentAngle[i]);
    else          Serial.print("unknown (use 'center')");
    Serial.print(" | min: ");
    if (minAngle[i] >= 0) Serial.printf("%d", minAngle[i]); else Serial.print("-");
    Serial.print(" | max: ");
    if (maxAngle[i] >= 0) Serial.printf("%d", maxAngle[i]); else Serial.print("-");
    Serial.print(" | home: ");
    if (homeAngle[i] >= 0) Serial.printf("%d", homeAngle[i]); else Serial.printf("- (default %d)", CENTER_ANGLE);
    Serial.println(selected == i ? "  <- selected" : "");
  }
  Serial.println("----------------");
}

void printHelp() {
  Serial.println("Commands (one per line):");
  Serial.println("  x / y      select servo X or Y");
  Serial.println("  center     selected servo jumps to 90 deg (do this first after every power-up)");
  Serial.println("  + / -      move selected servo 1 deg");
  Serial.println("  > / <      move selected servo 5 deg");
  Serial.println("  g 120      go to 120 deg in small steps");
  Serial.println("  min / max  record current angle as this servo's limit");
  Serial.println("  home       record current angle as this servo's home (must be between min and max)");
  Serial.println("  gohome     X returns to its home, then Y (one at a time)");
  Serial.println("  sweep      slow full-range test: to 0, then 0 -> 180, then back to 90 (horn free!)");
  Serial.println("             press any key + Enter during the sweep to stop it immediately");
  Serial.println("  p          print angles, limits and home");
  Serial.println("  save       store limits and home in flash");
  Serial.println("  help       show this list");
}

// ---------------- Servo ----------------
void servoOn(int i) {
  if (!ledcAttach(SERVO_PINS[i], PWM_FREQ_HZ, PWM_BITS)) {
    Serial.println("ERROR: ledcAttach failed");
  }
  ledcWrite(SERVO_PINS[i], angleToDuty(currentAngle[i]));
}

void servoOff(int i) {
  ledcDetach(SERVO_PINS[i]);
  pinMode(SERVO_PINS[i], OUTPUT);
  digitalWrite(SERVO_PINS[i], LOW);
}

// One move of one servo: signal on at the current angle, small steps to target,
// settle, signal off, rest.
void moveTo(int i, int target) {
  target = constrain(target, SAFE_MIN, SAFE_MAX);
  stamp();
  Serial.printf("servo %c (GPIO%d) | %d -> %d deg | start\n", SERVO_NAMES[i], SERVO_PINS[i], currentAngle[i], target);
  servoOn(i);
  while (currentAngle[i] != target) {
    delay(STEP_MS);
    currentAngle[i] += constrain(target - currentAngle[i], -STEP_DEG, STEP_DEG);
    ledcWrite(SERVO_PINS[i], angleToDuty(currentAngle[i]));
  }
  delay(SETTLE_MS);
  servoOff(i);
  stamp();
  Serial.printf("servo %c (GPIO%d) | at %d deg | end\n", SERVO_NAMES[i], SERVO_PINS[i], currentAngle[i]);
  delay(GAP_MS);
}

// First move after power-up: position is unknown, so this is one direct jump to 90 deg.
void center(int i) {
  stamp();
  Serial.printf("servo %c (GPIO%d) | center: direct jump to %d deg (position was unknown)\n",
                SERVO_NAMES[i], SERVO_PINS[i], CENTER_ANGLE);
  currentAngle[i] = CENTER_ANGLE;
  servoOn(i);
  delay(SETTLE_MS);
  servoOff(i);
  known[i] = true;
  delay(GAP_MS);
}

// Slow move, 1 deg every SWEEP_STEP_MS, printing every 10 deg. Any key typed stops it at once
// (signal off). Returns false if stopped early.
bool slowMove(int i, int target) {
  stamp();
  Serial.printf("servo %c (GPIO%d) | sweep %d -> %d deg | start\n", SERVO_NAMES[i], SERVO_PINS[i], currentAngle[i], target);
  servoOn(i);
  while (currentAngle[i] != target) {
    delay(SWEEP_STEP_MS);
    if (Serial.available()) {
      servoOff(i);
      while (Serial.available()) Serial.read();
      line = "";
      stamp();
      Serial.printf("servo %c (GPIO%d) | STOPPED by key at %d deg (signal off)\n", SERVO_NAMES[i], SERVO_PINS[i], currentAngle[i]);
      delay(GAP_MS);
      return false;
    }
    currentAngle[i] += (target > currentAngle[i]) ? 1 : -1;
    ledcWrite(SERVO_PINS[i], angleToDuty(currentAngle[i]));
    if (currentAngle[i] % 10 == 0) {
      stamp();
      Serial.printf("servo %c (GPIO%d) | %d deg\n", SERVO_NAMES[i], SERVO_PINS[i], currentAngle[i]);
    }
  }
  delay(SETTLE_MS);
  servoOff(i);
  stamp();
  Serial.printf("servo %c (GPIO%d) | at %d deg | end\n", SERVO_NAMES[i], SERVO_PINS[i], currentAngle[i]);
  delay(GAP_MS);
  return true;
}

// Full-range test: to 0, then 0 -> 180, then back to 90. Each part is its own move
// (signal off and a rest between parts).
void sweepTest(int i) {
  if (!slowMove(i, SWEEP_MIN)) return;
  if (!slowMove(i, SWEEP_MAX)) return;
  if (!slowMove(i, CENTER_ANGLE)) return;
  Serial.println("Sweep done. Did the servo buzz or strain near 0 or 180 deg?");
}

int homeOf(int i) {
  return homeAngle[i] >= 0 ? homeAngle[i] : CENTER_ANGLE;
}

// Return X, then Y, to home. A servo whose position is unknown (after power-up) makes
// one direct jump to home, which is always inside its calibrated travel.
void goHome() {
  for (int i = 0; i < NUM_SERVOS; i++) {
    if (known[i]) {
      if (currentAngle[i] != homeOf(i)) moveTo(i, homeOf(i));
    } else {
      stamp();
      Serial.printf("servo %c (GPIO%d) | gohome: direct jump to home %d deg (position was unknown)\n",
                    SERVO_NAMES[i], SERVO_PINS[i], homeOf(i));
      currentAngle[i] = homeOf(i);
      servoOn(i);
      delay(SETTLE_MS);
      servoOff(i);
      known[i] = true;
      delay(GAP_MS);
    }
  }
  Serial.println("Both servos at home.");
}

// A home angle is only valid between that servo's recorded min and max.
bool homeInsideLimits(int i) {
  if (homeAngle[i] < 0) return true;
  if (minAngle[i] < 0 || maxAngle[i] < 0) return false;
  return homeAngle[i] >= minAngle[i] && homeAngle[i] <= maxAngle[i];
}

// ---------------- Commands ----------------
bool needServo() {
  if (selected < 0) { Serial.println("Select a servo first: x or y"); return false; }
  return true;
}

bool needKnown() {
  if (!needServo()) return false;
  if (!known[selected]) { Serial.println("Position unknown: type 'center' first"); return false; }
  return true;
}

void handle(String cmd) {
  cmd.trim();
  cmd.toLowerCase();
  if (cmd.length() == 0) return;

  if (cmd == "x" || cmd == "y") {
    selected = (cmd == "x") ? 0 : 1;
    Serial.printf("Selected servo %c (GPIO%d)\n", SERVO_NAMES[selected], SERVO_PINS[selected]);
  } else if (cmd == "center") {
    if (needServo()) center(selected);
  } else if (cmd == "+" || cmd == "-" || cmd == ">" || cmd == "<") {
    if (!needKnown()) return;
    int delta = (cmd == "+") ? SMALL_NUDGE : (cmd == "-") ? -SMALL_NUDGE
              : (cmd == ">") ? BIG_NUDGE : -BIG_NUDGE;
    int target = currentAngle[selected] + delta;
    if (target < SAFE_MIN || target > SAFE_MAX) {
      Serial.printf("Refused: %d deg is outside the safe range %d-%d\n", target, SAFE_MIN, SAFE_MAX);
      return;
    }
    moveTo(selected, target);
  } else if (cmd.startsWith("g ")) {
    if (!needKnown()) return;
    String arg = cmd.substring(2);
    arg.trim();
    bool digitsOnly = arg.length() > 0;
    for (unsigned int k = 0; k < arg.length(); k++) {
      if (!isDigit(arg[k])) digitsOnly = false;
    }
    if (!digitsOnly) {  // a typo like 'g x' must not become 0 deg
      Serial.printf("Refused: '%s' is not a whole number of degrees\n", arg.c_str());
      return;
    }
    int target = arg.toInt();
    if (target < SAFE_MIN || target > SAFE_MAX) {
      Serial.printf("Refused: %d deg is outside the safe range %d-%d\n", target, SAFE_MIN, SAFE_MAX);
      return;
    }
    moveTo(selected, target);
  } else if (cmd == "min" || cmd == "max") {
    if (!needKnown()) return;
    if (cmd == "min") minAngle[selected] = currentAngle[selected];
    else              maxAngle[selected] = currentAngle[selected];
    Serial.printf("Recorded servo %c %s = %d deg\n", SERVO_NAMES[selected], cmd.c_str(), currentAngle[selected]);
    if (minAngle[selected] >= 0 && maxAngle[selected] >= 0 && minAngle[selected] >= maxAngle[selected]) {
      Serial.println("Warning: min is not below max for this servo");
    }
  } else if (cmd == "home") {
    if (!needKnown()) return;
    if (minAngle[selected] < 0 || maxAngle[selected] < 0) {
      Serial.println("Refused: record this servo's min and max first");
      return;
    }
    int a = currentAngle[selected];
    if (a < minAngle[selected] || a > maxAngle[selected]) {
      Serial.printf("Refused: %d deg is outside this servo's limits %d-%d\n", a, minAngle[selected], maxAngle[selected]);
      return;
    }
    homeAngle[selected] = a;
    Serial.printf("Recorded servo %c home = %d deg\n", SERVO_NAMES[selected], a);
  } else if (cmd == "gohome") {
    goHome();
  } else if (cmd == "sweep") {
    if (needKnown()) sweepTest(selected);
  } else if (cmd == "p") {
    printStatus();
  } else if (cmd == "save") {
    for (int i = 0; i < NUM_SERVOS; i++) {
      if (!homeInsideLimits(i)) {
        Serial.printf("Not saved: servo %c home %d deg is outside its limits. Set home again.\n",
                      SERVO_NAMES[i], homeAngle[i]);
        return;
      }
    }
    prefs.putInt("xmin", minAngle[0]);
    prefs.putInt("xmax", maxAngle[0]);
    prefs.putInt("ymin", minAngle[1]);
    prefs.putInt("ymax", maxAngle[1]);
    prefs.putInt("xhome", homeAngle[0]);
    prefs.putInt("yhome", homeAngle[1]);
    Serial.println("Limits and home saved to flash.");
    printStatus();
  } else if (cmd == "help") {
    printHelp();
  } else {
    Serial.printf("Unknown command: '%s' (type help)\n", cmd.c_str());
  }
}

// ---------------- Main ----------------
void setup() {
  for (int i = 0; i < NUM_SERVOS; i++) {
    pinMode(SERVO_PINS[i], OUTPUT);
    digitalWrite(SERVO_PINS[i], LOW);
  }

  Serial.begin(115200);
  unsigned long t0 = millis();
  while (!Serial && millis() - t0 < SERIAL_WAIT_MS) delay(10);

  int reason = esp_reset_reason();

  prefs.begin("calib", false);
  minAngle[0] = prefs.getInt("xmin", -1);
  maxAngle[0] = prefs.getInt("xmax", -1);
  minAngle[1] = prefs.getInt("ymin", -1);
  maxAngle[1] = prefs.getInt("ymax", -1);
  homeAngle[0] = prefs.getInt("xhome", -1);
  homeAngle[1] = prefs.getInt("yhome", -1);

  Serial.println();
  Serial.println("=== Phase 1b: X/Y travel calibration (ESP32-C3 Super Mini) ===");
  Serial.printf("Reset reason: %s (%d)\n", resetName(reason), reason);
  Serial.printf("Servos X (GPIO3), Y (GPIO4) | safe range %d-%d deg | nothing moves until you type a command\n",
                SAFE_MIN, SAFE_MAX);
  printStatus();
  printHelp();
}

void loop() {
  while (Serial.available()) {
    char c = Serial.read();
    if (c == '\n' || c == '\r') {
      handle(line);
      line = "";
    } else {
      line += c;
    }
  }
  delay(10);
}
