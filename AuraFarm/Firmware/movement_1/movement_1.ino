// Bluetooth Low Energy control of the X/Y stage plus the Z (focus) servo, ESP32-C3 Super Mini.
// X servo GPIO3, Y servo GPIO4, Z servo GPIO5. Board: ESP32-C3 Super Mini, core 3.x,
// USB CDC On Boot: Enabled.
// C3 runs from the Mac's USB. Servos run from the HW-131 rail (separate power, shared ground).
//
// Z (focus): JOG/GOTO Z only, in MANUAL. Z is NOT attached at boot (no startup jump): it starts
// from its last angle, saved in flash once it has stopped with no Z move queued. HOME, END, PATH, START and TRAVERSE
// never move Z. Replies keep the X/Y format; Z is reported on its own line, "ZPOS Z=n", after a Z
// move and after HELLO, RESUMED and STATUS.
//
// BLE: advertises as "terraloka_stage" using the Nordic UART Service (BLE only, no classic
// Bluetooth). The phone WRITES text commands to the RX characteristic and receives text replies
// as NOTIFY on the TX characteristic. The same commands also work from the Serial Monitor.
//
// Modes: AUTO (runs a path sent by the phone, or the standard traverse) and MANUAL (jog/goto).
// Motion rules from Phase 1: one servo at a time, 2 deg every 20 ms, signal off after every move,
// 500 ms rest between moves. Moves run in small slices so STOP or a BLE disconnect stops a
// servo immediately (signal off). AUTO resumes on reconnect.

#include <Preferences.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include "esp_system.h"

// ---------------- Settings ----------------
const char* BLE_NAME = "terraloka_stage";
#define SERVICE_UUID "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"  // Nordic UART Service
#define RX_UUID      "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"  // phone -> C3 (write)
#define TX_UUID      "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"  // C3 -> phone (notify)

const int  NUM_SERVOS = 3;
const int  SERVO_PINS[NUM_SERVOS]  = {3, 4, 5};
const char SERVO_NAMES[NUM_SERVOS] = {'X', 'Y', 'Z'};
const int  Z_SERVO = 2;               // index of the focus servo
const int  STAGE_SERVOS = 2;          // X and Y: homed at boot and by HOME / END
const unsigned long Z_SAVE_DELAY_MS = 500;   // flash write this long after the last Z move ends

const int DEFAULT_MIN  = 0;     // used when no calibration is saved
const int DEFAULT_MAX  = 180;   // (0-180 checked clean on these servos with 'sweep')
const int DEFAULT_HOME = 90;

const int STEP_DEG     = 2;     // move 2 deg ...
const int STEP_MS      = 20;    // ... every 20 ms
const int SETTLE_MS    = 300;   // hold after reaching target, before signal off
const int GAP_MS       = 500;   // rest with signal off after every move (also between servos)
const int BOOT_WAIT_MS = 500;   // pause after boot before first attach

const int PULSE_MIN_US = 500;   // pulse width at 0 deg (typical SG90)
const int PULSE_MAX_US = 2400;  // pulse width at 180 deg
const int PWM_FREQ_HZ  = 50;
const int PWM_BITS     = 14;

const int MAX_POINTS = 50;                    // path points accepted by PATH
const int QUEUE_SIZE = MAX_POINTS * 2 + 4;    // queued single-servo moves
const int MAX_JOG_QUEUE = 10;                 // MANUAL: moves allowed to wait in line

const unsigned long SERIAL_WAIT_MS = 5000;    // wait this long for Serial Monitor at boot

// ---------------- State ----------------
enum Mode { MODE_AUTO, MODE_MANUAL };
enum Phase { PH_IDLE, PH_STEP, PH_SETTLE };

struct Move { uint8_t servo; int16_t target; };

Mode  mode = MODE_MANUAL;
Phase phase = PH_IDLE;
Move  queue[QUEUE_SIZE];
int   qHead = 0, qCount = 0;
bool  paused = false;              // STOP or BLE disconnect (AUTO)
bool  pausedByDisconnect = false;
bool  jobActive = false;           // a TRAVERSE / START / HOME / END is running
unsigned long phaseMs = 0;         // when the current phase started / last step
unsigned long lastOffMs = 0;       // when the last move switched its signal off

int minAngle[NUM_SERVOS], maxAngle[NUM_SERVOS], homeAngle[NUM_SERVOS];
int currentAngle[NUM_SERVOS];      // last commanded angle per servo
int projected[NUM_SERVOS];         // angle each servo will have after the queued moves

bool zSavePending = false;         // Z moved: save its angle once it has been still a while
unsigned long zSaveAt = 0;

int pathX[MAX_POINTS], pathY[MAX_POINTS];
int pathLen = 0;

BLEServer* bleServer = nullptr;
BLECharacteristic* txChar = nullptr;
volatile bool bleConnected = false;
volatile bool connectEvent = false;
volatile bool disconnectEvent = false;
QueueHandle_t cmdQueue;            // commands from the BLE task, handled in loop()
const int CMD_LEN = 256;
String serialLine;

// ---------------- Helpers ----------------
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

void stamp() {
  Serial.printf("[%9.3f s] ", millis() / 1000.0);
}

// Reply to the phone (BLE notify) and the Serial Monitor.
void reply(const String& msg) {
  stamp();
  Serial.print("> ");
  Serial.println(msg);
  if (bleConnected && txChar) {
    txChar->setValue(msg.c_str());
    txChar->notify();
  }
}

uint32_t angleToDuty(int angle) {
  uint32_t us = PULSE_MIN_US + (uint32_t)(PULSE_MAX_US - PULSE_MIN_US) * angle / 180;
  uint32_t periodUs = 1000000UL / PWM_FREQ_HZ;
  return us * ((1UL << PWM_BITS) - 1) / periodUs;
}

const char* modeName() { return mode == MODE_AUTO ? "AUTO" : "MANUAL"; }

const char* stateName() {
  if (paused) return "PAUSED";
  if (phase != PH_IDLE || qCount > 0) return "MOVING";
  return "IDLE";
}

String posText() {
  return String("X=") + currentAngle[0] + " Y=" + currentAngle[1];
}

// Z on a line of its own, so the X/Y replies keep their format for older app versions.
void replyZ() {
  reply(String("ZPOS Z=") + currentAngle[Z_SERVO]);
}

// The X and Y limits on a line of its own, so the other replies keep their format.
void replyLimits() {
  reply(String("LIMITS XMIN=") + minAngle[0] + " XMAX=" + maxAngle[0] + " YMIN=" + minAngle[1] +
        " YMAX=" + maxAngle[1]);
}

// ---------------- Z angle in flash ----------------
int loadSavedZ() {
  Preferences zp;
  zp.begin("zpos", false);  // read-write so a first boot creates the namespace (no error line)
  int z = zp.getInt("z", -1);
  zp.end();
  return z;
}

void scheduleZSave() {
  zSavePending = true;
  zSaveAt = millis() + Z_SAVE_DELAY_MS;
}

// True while a Z move runs or waits in the queue: its angle is not final yet.
bool zBusy() {
  for (int k = 0; k < qCount; k++) {
    if (queue[(qHead + k) % QUEUE_SIZE].servo == Z_SERVO) return true;
  }
  return false;
}

// Saves Z only once it is still with nothing queued, so the saved angle is always one the servo
// really stopped at (never a point in the middle of a move).
void saveZIfDue() {
  if (!zSavePending || (long)(millis() - zSaveAt) < 0) return;
  if (zBusy()) return;
  zSavePending = false;
  Preferences zp;
  zp.begin("zpos", false);
  zp.putInt("z", currentAngle[Z_SERVO]);
  zp.end();
  stamp();
  Serial.printf("servo Z (GPIO%d) | saved angle %d deg\n", SERVO_PINS[Z_SERVO], currentAngle[Z_SERVO]);
}

// ---------------- Limits and home (from calibration) ----------------
void loadLimits() {
  Preferences cal;
  cal.begin("calib", true);  // read-only; missing values fall back to defaults
  const char* minKeys[NUM_SERVOS]  = {"xmin", "ymin", "zmin"};
  const char* maxKeys[NUM_SERVOS]  = {"xmax", "ymax", "zmax"};
  const char* homeKeys[NUM_SERVOS] = {"xhome", "yhome", "zhome"};
  for (int i = 0; i < NUM_SERVOS; i++) {
    int mn = cal.getInt(minKeys[i], -1);
    int mx = cal.getInt(maxKeys[i], -1);
    int hm = cal.getInt(homeKeys[i], -1);
    bool limitsOk = mn >= DEFAULT_MIN && mx <= DEFAULT_MAX && mn < mx;
    minAngle[i] = limitsOk ? mn : DEFAULT_MIN;
    maxAngle[i] = limitsOk ? mx : DEFAULT_MAX;
    bool homeOk = hm >= minAngle[i] && hm <= maxAngle[i];
    homeAngle[i] = homeOk ? hm : DEFAULT_HOME;
    Serial.printf("servo %c (GPIO%d) | min %d, max %d (%s) | home %d (%s)\n",
                  SERVO_NAMES[i], SERVO_PINS[i], minAngle[i], maxAngle[i],
                  limitsOk ? "saved" : "default", homeAngle[i], homeOk ? "saved" : "default");
  }
  cal.end();
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

// ---------------- Move queue ----------------
bool enqueue(int servo, int target) {
  if (qCount >= QUEUE_SIZE) return false;
  queue[(qHead + qCount) % QUEUE_SIZE] = {(uint8_t)servo, (int16_t)target};
  qCount++;
  projected[servo] = target;
  return true;
}

void popMove() {
  qHead = (qHead + 1) % QUEUE_SIZE;
  qCount--;
}

// Stop the move in progress at once (signal off). The move stays at the front of the queue,
// so RESUME continues it from where it stopped.
void haltCurrentMove() {
  if (phase == PH_STEP || phase == PH_SETTLE) {
    int s = queue[qHead].servo;
    servoOff(s);
    lastOffMs = millis();
    if (s == Z_SERVO) scheduleZSave();
    stamp();
    Serial.printf("servo %c (GPIO%d) | stopped at %d deg (signal off)\n", SERVO_NAMES[s], SERVO_PINS[s], currentAngle[s]);
  }
  phase = PH_IDLE;
}

void clearQueue() {
  haltCurrentMove();
  qHead = 0;
  qCount = 0;
  paused = false;
  pausedByDisconnect = false;
  jobActive = false;
  for (int i = 0; i < NUM_SERVOS; i++) projected[i] = currentAngle[i];
}

void enqueueHome() {
  enqueue(0, homeAngle[0]);
  enqueue(1, homeAngle[1]);
}

// Runs a little of the current move every loop() pass, so commands and disconnects are seen
// between every 2 deg step.
void runEngine() {
  if (paused) return;
  unsigned long now = millis();

  if (phase == PH_IDLE) {
    if (qCount == 0) return;
    if (now - lastOffMs < (unsigned long)GAP_MS) return;  // rest between moves
    Move& m = queue[qHead];
    if (currentAngle[m.servo] == m.target) {  // already there: nothing to do
      popMove();
    } else {
      stamp();
      Serial.printf("servo %c (GPIO%d) | %d -> %d deg | start\n", SERVO_NAMES[m.servo], SERVO_PINS[m.servo],
                    currentAngle[m.servo], m.target);
      servoOn(m.servo);
      phase = PH_STEP;
      phaseMs = now;
      return;
    }
  } else if (phase == PH_STEP) {
    if (now - phaseMs < (unsigned long)STEP_MS) return;
    phaseMs = now;
    Move& m = queue[qHead];
    currentAngle[m.servo] += constrain(m.target - currentAngle[m.servo], -STEP_DEG, STEP_DEG);
    ledcWrite(SERVO_PINS[m.servo], angleToDuty(currentAngle[m.servo]));
    if (currentAngle[m.servo] == m.target) {
      phase = PH_SETTLE;
      phaseMs = now;
    }
    return;
  } else if (phase == PH_SETTLE) {
    if (now - phaseMs < (unsigned long)SETTLE_MS) return;
    Move& m = queue[qHead];
    servoOff(m.servo);
    lastOffMs = now;
    stamp();
    Serial.printf("servo %c (GPIO%d) | at %d deg | end\n", SERVO_NAMES[m.servo], SERVO_PINS[m.servo], currentAngle[m.servo]);
    int movedServo = m.servo;  // read before popMove frees the slot
    popMove();
    phase = PH_IDLE;
    if (movedServo == Z_SERVO) {
      scheduleZSave();
      replyZ();
    } else {
      if (currentAngle[movedServo] == minAngle[movedServo]) reply(String("LIMIT ") + SERVO_NAMES[movedServo] + " MIN");
      if (currentAngle[movedServo] == maxAngle[movedServo]) reply(String("LIMIT ") + SERVO_NAMES[movedServo] + " MAX");
      reply("POS " + posText());
    }
  }

  if (qCount == 0 && phase == PH_IDLE && jobActive) {
    jobActive = false;
    reply("DONE " + posText());
  }
}

// ---------------- Commands ----------------
int axisIndex(const String& a) {
  if (a == "X") return 0;
  if (a == "Y") return 1;
  if (a == "Z") return Z_SERVO;
  return -1;
}

// Whole number with optional sign; false for anything else (so a typo never becomes 0 deg).
bool parseInt(const String& s, int& out) {
  if (s.length() == 0) return false;
  int start = (s[0] == '-' || s[0] == '+') ? 1 : 0;
  if (start == (int)s.length()) return false;
  for (unsigned int k = start; k < s.length(); k++) if (!isDigit(s[k])) return false;
  out = s.toInt();
  return true;
}

bool inLimits(int servo, int a) {
  return a >= minAngle[servo] && a <= maxAngle[servo];
}

void handleCommand(String cmd) {
  cmd.trim();
  cmd.toUpperCase();
  if (cmd.length() == 0) return;
  stamp();
  Serial.printf("< %s\n", cmd.c_str());

  int sp1 = cmd.indexOf(' ');
  String word = sp1 < 0 ? cmd : cmd.substring(0, sp1);
  String rest = sp1 < 0 ? "" : cmd.substring(sp1 + 1);
  rest.trim();

  if (word == "STATUS") {
    reply(String(modeName()) + " " + stateName() + " " + posText() + " Q=" + qCount);
    replyLimits();
    replyZ();

  } else if (word == "MODE") {
    if (qCount > 0 || phase != PH_IDLE) { reply("ERR BUSY (STOP or wait)"); return; }
    if (rest == "AUTO")        mode = MODE_AUTO;
    else if (rest == "MANUAL") mode = MODE_MANUAL;
    else { reply("ERR MODE AUTO|MANUAL"); return; }
    clearQueue();
    reply(String("OK MODE ") + modeName());

  } else if (word == "JOG" || word == "GOTO") {
    if (mode != MODE_MANUAL) { reply("ERR NOT MANUAL"); return; }
    if (paused) { reply("ERR PAUSED"); return; }
    int sp2 = rest.indexOf(' ');
    int servo = axisIndex(sp2 < 0 ? rest : rest.substring(0, sp2));
    int value;
    if (servo < 0 || sp2 < 0 || !parseInt(rest.substring(sp2 + 1), value)) {
      reply(String("ERR ") + word + " X|Y|Z <deg>");
      return;
    }
    int target = (word == "JOG") ? projected[servo] + value : value;
    if (!inLimits(servo, target)) {
      reply(String("ERR LIMIT ") + minAngle[servo] + "-" + maxAngle[servo]);
      return;
    }
    if (qCount >= MAX_JOG_QUEUE) { reply("ERR BUSY"); return; }
    enqueue(servo, target);
    reply(String("OK ") + SERVO_NAMES[servo] + "->" + target);

  } else if (word == "PATH") {
    if (mode != MODE_AUTO) { reply("ERR NOT AUTO"); return; }
    if (qCount > 0 || paused) { reply("ERR BUSY (STOP/END first)"); return; }
    int n = 0;
    int pos = 0;
    while (pos < (int)rest.length()) {
      int semi = rest.indexOf(';', pos);
      String pt = rest.substring(pos, semi < 0 ? rest.length() : semi);
      pt.trim();
      pos = semi < 0 ? rest.length() : semi + 1;
      if (pt.length() == 0) continue;
      int comma = pt.indexOf(',');
      int x, y;
      if (comma < 0 || !parseInt(pt.substring(0, comma), x) || !parseInt(pt.substring(comma + 1), y)) {
        reply(String("ERR PATH point ") + (n + 1));
        return;
      }
      if (!inLimits(0, x) || !inLimits(1, y)) {
        reply(String("ERR PATH point ") + (n + 1) + " outside limits");
        return;
      }
      if (n >= MAX_POINTS) { reply(String("ERR PATH max ") + MAX_POINTS); return; }
      pathX[n] = x;
      pathY[n] = y;
      n++;
    }
    if (n == 0) { reply("ERR PATH x,y;x,y;..."); return; }
    pathLen = n;
    reply(String("OK PATH ") + n + " points");

  } else if (word == "START") {
    if (mode != MODE_AUTO) { reply("ERR NOT AUTO"); return; }
    if (pathLen == 0) { reply("ERR NO PATH"); return; }
    if (qCount > 0 || paused) { reply("ERR BUSY (STOP/END first)"); return; }
    for (int k = 0; k < pathLen; k++) {
      enqueue(0, pathX[k]);  // X first, then Y, never together
      enqueue(1, pathY[k]);
    }
    enqueueHome();
    jobActive = true;
    reply(String("OK START ") + pathLen + " points");

  } else if (word == "TRAVERSE") {
    if (mode != MODE_AUTO) { reply("ERR NOT AUTO"); return; }
    if (qCount > 0 || paused) { reply("ERR BUSY (STOP/END first)"); return; }
    enqueue(0, minAngle[0]);  // full X
    enqueue(0, maxAngle[0]);
    enqueue(1, minAngle[1]);  // full Y
    enqueue(1, maxAngle[1]);
    enqueueHome();            // back home, X then Y
    jobActive = true;
    reply("OK TRAVERSE");

  } else if (word == "STOP") {
    if (mode == MODE_MANUAL) {
      clearQueue();           // MANUAL: stop and drop any waiting jogs
    } else {
      haltCurrentMove();      // AUTO: keep the rest of the path for RESUME
      if (qCount > 0) paused = true;
    }
    reply("OK STOP " + posText());

  } else if (word == "RESUME") {
    if (!paused) { reply("ERR NOT PAUSED"); return; }
    paused = false;
    pausedByDisconnect = false;
    reply("OK RESUME");

  } else if (word == "HOME" || word == "END") {
    clearQueue();
    enqueueHome();
    jobActive = true;
    reply(String("OK ") + word);

  } else {
    reply("ERR UNKNOWN " + word);
  }
}

// ---------------- BLE ----------------
class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer*) override {
    bleConnected = true;
    connectEvent = true;
  }
  void onDisconnect(BLEServer*) override {
    bleConnected = false;
    disconnectEvent = true;
  }
};

class RxCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* c) override {
    String v = c->getValue();
    char buf[CMD_LEN];
    strncpy(buf, v.c_str(), CMD_LEN - 1);
    buf[CMD_LEN - 1] = '\0';
    xQueueSend(cmdQueue, buf, 0);  // handled in loop(), not in the BLE task
  }
};

void setupBle() {
  BLEDevice::init(BLE_NAME);
  bleServer = BLEDevice::createServer();
  bleServer->setCallbacks(new ServerCallbacks());
  BLEService* service = bleServer->createService(SERVICE_UUID);
  // The C3 build uses NimBLE, which adds the notify descriptor (0x2902) automatically.
  txChar = service->createCharacteristic(TX_UUID, BLECharacteristic::PROPERTY_NOTIFY);
  BLECharacteristic* rxChar = service->createCharacteristic(
      RX_UUID, BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR);
  rxChar->setCallbacks(new RxCallbacks());
  service->start();
  bleServer->getAdvertising()->start();
  Serial.printf("BLE advertising as \"%s\" (Nordic UART Service)\n", BLE_NAME);
}

void handleBleEvents() {
  if (disconnectEvent) {
    disconnectEvent = false;
    stamp();
    Serial.println("BLE disconnected");
    if (mode == MODE_AUTO) {
      if (phase != PH_IDLE || qCount > 0) {
        haltCurrentMove();   // stop immediately, keep position and remaining path
        paused = true;
        pausedByDisconnect = true;
        stamp();
        Serial.printf("paused by disconnect at %s, %d moves left\n", posText().c_str(), qCount);
      }
    } else {
      clearQueue();          // MANUAL: stop and wait
    }
    delay(500);              // give the BLE stack a moment, then advertise again
    bleServer->startAdvertising();
    Serial.println("BLE advertising again");
  }
  if (connectEvent) {
    connectEvent = false;
    stamp();
    Serial.println("BLE connected");
    delay(300);              // let the phone subscribe before the first message
    if (pausedByDisconnect) {
      // Position was kept while paused; the next move re-attaches at the saved angle
      // (pulling the servo back there if it was nudged) and the path carries on.
      paused = false;
      pausedByDisconnect = false;
      reply("RESUMED " + posText() + " Q=" + qCount);
    } else {
      reply(String("HELLO ") + modeName() + " " + stateName() + " " + posText());
    }
    replyLimits();
    replyZ();
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
  Serial.println();
  Serial.println("=== Stage control X/Y/Z (ESP32-C3 Super Mini) ===");
  Serial.printf("Reset reason: %s (%d)\n", resetName(reason), reason);
  loadLimits();

  // Z is not attached at boot: it starts from its saved angle, and its first move begins there.
  int savedZ = loadSavedZ();
  bool zOk = inLimits(Z_SERVO, savedZ);
  currentAngle[Z_SERVO] = zOk ? savedZ : homeAngle[Z_SERVO];
  projected[Z_SERVO] = currentAngle[Z_SERVO];
  Serial.printf("startup | servo Z (GPIO%d) | not attached, last angle %d deg (%s)\n",
                SERVO_PINS[Z_SERVO], currentAngle[Z_SERVO], zOk ? "saved" : "home, nothing saved");

  // Attach X, then Y, each with one jump to its home (position unknown after power-up).
  delay(BOOT_WAIT_MS);
  for (int i = 0; i < STAGE_SERVOS; i++) {
    stamp();
    Serial.printf("startup | servo %c (GPIO%d) | attach at home %d deg (one direct jump)\n",
                  SERVO_NAMES[i], SERVO_PINS[i], homeAngle[i]);
    currentAngle[i] = homeAngle[i];
    projected[i] = homeAngle[i];
    servoOn(i);
    delay(SETTLE_MS);
    servoOff(i);
    delay(GAP_MS);
  }
  lastOffMs = millis();

  cmdQueue = xQueueCreate(8, CMD_LEN);
  setupBle();
  Serial.println("Ready. Mode MANUAL. Commands: STATUS, MODE AUTO|MANUAL, JOG X|Y|Z n, GOTO X|Y|Z n,");
  Serial.println("PATH x,y;x,y;..., START, TRAVERSE, STOP, RESUME, HOME, END (HOME/END: X and Y only)");
}

void loop() {
  handleBleEvents();

  char buf[CMD_LEN];
  while (xQueueReceive(cmdQueue, buf, 0) == pdTRUE) handleCommand(String(buf));

  while (Serial.available()) {
    char c = Serial.read();
    if (c == '\n' || c == '\r') {
      handleCommand(serialLine);
      serialLine = "";
    } else {
      serialLine += c;
    }
  }

  runEngine();
  saveZIfDue();
  delay(1);
}
