# FHEM-Gartenbewaesserung

Intelligente Gartenbewässerung über FHEM mit IBC-Container, Regentonne, Pumpe, Magnetventilen und Regensensoren.

---

## Inhaltsverzeichnis

1. [Projektbeschreibung](#projektbeschreibung)
2. [Systemübersicht](#systemübersicht)
3. [Voraussetzungen](#voraussetzungen)
4. [Installation](#installation)
5. [Schnellstart](#schnellstart)
6. [Attribut-Referenz](#attribut-referenz)
7. [Set-Befehle](#set-befehle)
8. [Get-Befehle](#get-befehle)
9. [Readings](#readings)
10. [Automatische Pausen-Logik](#automatische-pausen-logik)
11. [Regen-Logik](#regen-logik)
12. [pumpStartDelay](#pumpstartdelay)
13. [startCircuit-Modus](#startcircuit-modus)
14. [Beispielkonfiguration (Tasmota 8-Kanal Relay)](#beispielkonfiguration)
15. [Versionsverlauf](#versionsverlauf)
16. [Lizenz](#lizenz)

---

## Projektbeschreibung

Das FHEM-Modul `98_Gartenbewaesserung.pm` steuert eine vollautomatische Gartenbewässerungsanlage mit bis zu **8 Magnetventilen**, einer **Regenpumpe**, einem **Regenwasserfass** und einem **IBC-Container** (1000-Liter-Tank).

Das Modul ist so ausgelegt, dass es **Regenwasser bevorzugt** und nur dann auf Hauswasser zurückgreift, wenn der IBC leer ist. Bei ausreichend Regen füllt es den IBC automatisch auf, sodass du nahezu autark bewässern kannst.

**Typischer Anwendungsfall:**
- Garten mit 8 Bewässerungszonen (Beete, Rasen, Gewächshaus, …)
- Regenwasserfass als Primärquelle für die Pumpe
- IBC-Container als Puffer für Regenwasser
- Automatische Bewässerung nach Zeitplan mit Feuchtigkeits- und Regenprüfung

---

## Systemübersicht

```
Hauswasseranschluss
        │
        ▼
  [barrelFillValveDevice]
        │
        ▼
    ┌───────┐        [ibcFillValveDevice]
    │ FASS  │ ──────────────────────────► IBC-Container
    │       │ ◄────────────────────────── [ibcToBarrelValveDevice]
    └───────┘        (+ ibcToBarrelPumpDevice optional)
        │
        ▼
  [pumpDevice]
        │
        ▼
  [valve1..8Device]
        │
        ▼
  Gartenzonen 1–8
```

**Sensoren:**
| Sensor | Attribut | Funktion |
|---|---|---|
| Fass-voll | `barrelFullSensorDevice` | Stoppt Fass-Befüllung vorzeitig |
| Fass-leer | `barrelEmptySensorDevice` | Pumpe-Not-Aus bei leerem Fass, startet automatischen Refill |
| IBC-voll | `ibcFullSensorDevice` | Stoppt IBC-Befüllung |
| IBC-leer | `ibcEmptySensorDevice` | Entscheidet ob Hauswasser statt IBC genutzt wird |
| Regensensor | `rainSensorDevice` | Startet IBC-Befüllung bei Dauerregen |
| Feuchtigkeitssensor | `moistureSensorDevice` | Überspringt Bewässerung bei ausreichend Bodenfeuchtigkeit |

---

## Voraussetzungen

- **FHEM** (getestet ab Version 6.x)
- **MQTT2_SERVER** oder **MQTT2_CLIENT** (für Tasmota-Geräte)
- Perl-Module `strict`, `warnings`, `POSIX` (FHEM-Standard)

---

## Installation

1. Datei `FHEM/98_Gartenbewaesserung.pm` in dein FHEM-Verzeichnis kopieren:
   ```bash
   cp FHEM/98_Gartenbewaesserung.pm /opt/fhem/FHEM/
   ```

2. Modul in FHEM neu laden:
   ```
   reload 98_Gartenbewaesserung
   ```

3. Device anlegen:
   ```
   define Garten Gartenbewaesserung
   ```

---

## Schnellstart

```
# Device anlegen
define Garten Gartenbewaesserung

# Ventile konfigurieren (Tasmota 8-Kanal: Device:Channel)
attr Garten valve1Device Tasmota_Relay:POWER1
attr Garten valve2Device Tasmota_Relay:POWER2
attr Garten valve3Device Tasmota_Relay:POWER3
attr Garten valve4Device Tasmota_Relay:POWER4

# Pumpe
attr Garten pumpDevice Tasmota_Relay:POWER5

# Fass auffüllen (Hauswasseranschluss → Fass)
attr Garten barrelFillValveDevice Tasmota_Relay:POWER6

# IBC-Ventile
attr Garten ibcFillValveDevice    Tasmota_Relay:POWER7
attr Garten ibcToBarrelValveDevice Tasmota_Relay:POWER8

# Zeitplan
attr Garten startTime1 06:00
attr Garten activeValves 1,2,3,4

# Konfiguration prüfen
get Garten validate
```

---

## Attribut-Referenz

### Ventile

| Attribut | Beschreibung | Standard |
|---|---|---|
| `valve1Device` … `valve8Device` | FHEM-Device oder `Device:Reading` für Ventil 1–8 | – |
| `valve1Duration` … `valve8Duration` | Bewässerungsdauer pro Ventil in Minuten (1–120) | 15 |
| `activeValves` | Kommagetrennte Liste der aktiven Ventile (z. B. `1,2,3,4`) | `1,2,3,4,5,6,7,8` |

### Pumpe

| Attribut | Beschreibung | Standard |
|---|---|---|
| `pumpDevice` | Hauptpumpe (Fass → Garten) | – |
| `ibcToBarrelPumpDevice` | Separate Pumpe für IBC→Fass-Transfer (optional, sonst Schwerkraft) | – |
| `pumpStartDelay` | Zeitversatz zwischen Pumpe und Ventil in Sekunden (−30 … +30) | 3 |
| `pumpMaxRuntime` | Maximale kontinuierliche Pumpenlaufzeit in Minuten (0 = deaktiviert, 1–240 aktiv) | 0 |

### Fass

| Attribut | Beschreibung | Standard |
|---|---|---|
| `barrelFillValveDevice` | Ventil am Hauswasseranschluss zum Auffüllen des Fasses | – |
| `barrelFullSensorDevice` | Schwimmerschalter / Füllstandssensor am Fass | – |
| `barrelEmptySensorDevice` | Sensor „Fass leer": Pumpe-Not-Aus, automatischer Refill aus IBC oder Hauswasser | – |
| `barrelFillDuration` | Maximale Befüllzeit des Fasses in Minuten (1–60) | 10 |
| `barrelFillThreshold` | Schwellwert (%) unter dem das Fass vor der Bewässerung aufgefüllt wird | 30 |
| `barrelFillTimeout` | Watchdog-Zeit in Minuten: Schlägt `barrelFullSensorDevice` innerhalb dieser Zeit nicht an, wird `barrelFillTimeoutAlert` gesetzt (0 = deaktiviert) | 0 |
| `barrelFullSensorActiveValue` | Eigener Wert für „Fass voll" (z. B. `ON`), sonst automatisch erkannt | – |
| `barrelFullSensorInactiveValue` | Eigener Wert für „Fass nicht voll" | – |
| `barrelEmptySensorActiveValue` | Eigener Wert für „Fass leer" | – |
| `barrelEmptySensorInactiveValue` | Eigener Wert für „Fass nicht leer" | – |

### IBC-Container

| Attribut | Beschreibung | Standard |
|---|---|---|
| `ibcFillValveDevice` | Ventil Fass→IBC (Regenwasser in IBC pumpen) | – |
| `ibcToBarrelValveDevice` | Ventil IBC→Fass (Wasser aus IBC ins Fass zurückleiten) | – |
| `ibcFullSensorDevice` | Sensor „IBC voll" | – |
| `ibcEmptySensorDevice` | Sensor „IBC leer" (optional, für Quellwahl in Pausen) | – |
| `ibcToBarrelDuration` | Dauer IBC→Fass-Transfer in Minuten (1–60) | 15 |
| `ibcFullSensorActiveValue` / `ibcFullSensorInactiveValue` | Eigene Sensorwerte | – |
| `ibcEmptySensorActiveValue` / `ibcEmptySensorInactiveValue` | Eigene Sensorwerte | – |

### Regen

| Attribut | Beschreibung | Standard |
|---|---|---|
| `rainSensorDevice` | Regensensor | – |
| `rainDurationForIBC` | Wie viele Minuten Regen bis IBC-Befüllung startet (5–180) | 30 |
| `rainCheckInterval` | Prüfintervall des Regensensors in Minuten (1–30) | 5 |
| `rainSensorActiveValue` / `rainSensorInactiveValue` | Eigene Sensorwerte | – |

### Bodenfeuchtigkeit

| Attribut | Beschreibung | Standard |
|---|---|---|
| `moistureSensorDevice` | Feuchtigkeitssensor (überspringt Bewässerung wenn Boden feucht) | – |
| `moistureSensorReading` | Reading-Name des Feuchtigkeitswerts | `moisture` |
| `moistureThreshold` | Schwellwert 0–100% (Bewässerung startet NUR wenn unter diesem Wert) | 40 |
| `moistureSensorInvert` | 1 = Logik umkehren (hoher Wert = trocken) | 0 |

### Pausen

| Attribut | Beschreibung | Standard |
|---|---|---|
| `wateringPauseInterval` | Pause alle X Minuten für Fass-Nachfüllung (0 = deaktiviert) | 8 |
| `wateringPauseDuration` | Dauer der Pause in Minuten | 20 |

### Zeitplan

| Attribut | Beschreibung | Standard |
|---|---|---|
| `startTime1` / `startTime2` / `startTime3` | Startzeiten im Format `HH:MM` (bis zu 3 pro Tag) | – |
| `weekdaysOnly` | 1 = Nur Mo–Fr bewässern | 0 |
| `manualMode` | 1 = Zeitplan deaktiviert (nur manuelle Befehle) | 0 |

### Gerätewerte

| Attribut | Beschreibung | Standard |
|---|---|---|
| `switchOnValue` | Wert um ein Gerät einzuschalten | `ON` |
| `switchOffValue` | Wert um ein Gerät auszuschalten | `OFF` |

### Sonstiges

| Attribut | Beschreibung |
|---|---|
| `disable` | 1 = Modul vollständig deaktivieren |

---

## Set-Befehle

| Befehl | Beschreibung |
|---|---|
| `set <name> start` | Startet den kompletten Bewässerungszyklus mit allen aktiven Ventilen (prüft Feuchtigkeit, Zeitplan, Pausen). |
| `set <name> stop` | Stoppt sofort **alle** laufenden Operationen: Ventile, Pumpen, Pausen, Transfer. |
| `set <name> startCircuit <1-8>` | Startet einen einzelnen Bewässerungskreis mit voller Logik (Pumpe, Ventil, Pausen). Wird **nicht** durch Regen oder Zeitplan unterbrochen. Ideal für Gewächshaus-Steuerung. |
| `set <name> startIBCFill` | Startet manuelle IBC-Befüllung aus dem Fass (mit Hauptpumpe + `ibcFillValveDevice`). |
| `set <name> stopIBCFill` | Stoppt die IBC-Befüllung sofort. |
| `set <name> startIBCtoBarrel` | Transferiert Wasser vom IBC zurück ins Fass (Schwerkraft oder `ibcToBarrelPumpDevice`). Stoppt automatisch nach `ibcToBarrelDuration` Minuten oder wenn der Fass-voll-Sensor anschlägt. |
| `set <name> stopIBCtoBarrel` | Stoppt den IBC→Fass-Transfer sofort. |
| `set <name> startValve <1-8>` | Öffnet ein einzelnes Ventil manuell (ohne Zeitbegrenzung, ohne Automatik). |
| `set <name> stopValve` | Schließt das aktuell geöffnete Ventil. |
| `set <name> resetPumpOverrunAlert` | Setzt das Reading `pumpOverrunAlert` manuell auf `no`. |
| `set <name> refreshSensors` | Liest alle konfigurierten Sensor-Readings sofort neu ein und aktualisiert die Readings (z. B. nach Neustart oder Gerätetausch). |
| `set <name> validate` | Prüft die komplette Konfiguration und gibt Fehler, Warnungen und Informationen aus. |

---

## Get-Befehle

| Befehl | Beschreibung |
|---|---|
| `get <name> status` | Zeigt den aktuellen Status aller Komponenten (Ventil, Phase, Restzeit, Sensoren, …). |
| `get <name> config` | Zeigt die vollständige Konfiguration übersichtlich formatiert. |
| `get <name> version` | Zeigt die aktuell installierte Modulversion. |

---

## Readings

| Reading | Beschreibung |
|---|---|
| `state` | Aktueller Zustand: `idle`, `watering`, `circuit mode`, `paused`, `ibc to barrel`, `stopped` |
| `phase` | Detailphase, z. B. `watering`, `pause - refilling`, `filling barrel` |
| `currentValve` | Aktuell aktives Ventil (1–8) oder `none` |
| `cycleProgress` | Fortschritt im Zyklus, z. B. `3/6` |
| `remainingTime` | Verbleibende Zeit des aktuellen Vorgangs (live) |
| `pauseActive` | `yes` / `no` — Pause gerade aktiv? |
| `pauseTimeRemaining` | Verbleibende Pausenzeit (live) |
| `ibcFilling` | `yes` / `no` — IBC-Befüllung aktiv? |
| `ibcFillStarted` | Zeitstempel des letzten IBC-Befüll-Starts |
| `ibcToBarrelActive` | `yes` / `no` — IBC→Fass-Transfer aktiv? |
| `pumpOverrunAlert` | `yes` / `no` — Pumpe wurde wegen überschrittener `pumpMaxRuntime` not-abgeschaltet |
| `barrelFull` | `yes` / `no` / `not configured` |
| `barrelEmpty` | `yes` / `no` / `not configured` — Fass-leer-Status; `yes` sperrt die Pumpe |
| `barrelLevel` | Simulierter Füllstand in % (wird durch Bewässerung reduziert, durch Pause zurückgesetzt) |
| `barrelFillTimeoutAlert` | `yes` / `no` — Befüllventil war länger als `barrelFillTimeout` Minuten offen ohne `barrelFull:yes` (IBC vermutlich leer oder Wasserzufuhr gestört). Reset automatisch bei `barrelFull:yes` oder `raining:yes`. |
| `ibcFull` | `yes` / `no` / `not configured` |
| `ibcEmpty` | `yes` / `no` / `not configured` |
| `raining` | `yes` / `no` / `not configured` |
| `rainDetectedSince` | Zeitstempel seit wann Regen erkannt wird |
| `soilMoisture` | Aktueller Feuchtigkeitswert des Bodens |
| `lastWatering` | Zeitstempel der letzten abgeschlossenen Bewässerung |
| `lastCircuitWatering` | Zeitstempel des letzten abgeschlossenen Einzelkreises |

---

## Automatische Pausen-Logik

Damit das Fass während einer langen Bewässerung nicht leer läuft, unterbricht das Modul den Zyklus regelmäßig zum Nachfüllen.

**Konfiguration:**
```
attr Garten wateringPauseInterval 8   # Alle 8 Minuten Pause
attr Garten wateringPauseDuration  20  # Pause dauert 20 Minuten
```

**Ablauf:**
1. Ventil läuft `wateringPauseInterval` Minuten
2. Ventil wird geschlossen, Pumpe gestoppt
3. Je nach `ibcEmpty`-Sensor:
   - IBC hat Wasser → `ibcToBarrelValveDevice` wird geöffnet (+ `ibcToBarrelPumpDevice` falls konfiguriert)
   - IBC ist leer → `barrelFillValveDevice` öffnet (Hauswasser)
4. Nach `wateringPauseDuration` Minuten (oder wenn Fass-voll-Sensor anschlägt) wird die Pause beendet
5. Ventil öffnet erneut für die Restzeit

Die Pausen gelten sowohl beim vollautomatischen `start`-Befehl als auch beim `startCircuit`-Befehl.

`wateringPauseInterval = 0` deaktiviert die Pausen (Dauerbetrieb).

---

## Regen-Logik

Der Regensensor steuert die automatische IBC-Befüllung aus dem Regenwasser:

1. `CheckRain` läuft alle `rainCheckInterval` Minuten
2. Sobald Regen erkannt wird, startet die Zeitmessung
3. Hat es `rainDurationForIBC` Minuten ununterbrochen geregnet, startet automatisch die IBC-Befüllung:
   - `pumpDevice` → `ibcFillValveDevice` öffnet (Wasser vom Fass in den IBC)
4. Sobald der Regen aufhört, wird die IBC-Befüllung gestoppt
5. Wenn `ibcFullSensorDevice` anspricht, stoppt die Befüllung ebenfalls

**Wichtig:** Die Regen-Logik **unterbricht keine** manuell gestarteten Bewässerungskreise (`startCircuit`). Sie greift nur im Leerlauf oder bei automatisch gestartetem Vollzyklus.

---

## pumpStartDelay

Das Attribut `pumpStartDelay` steuert das zeitliche Verhältnis zwischen Pumpe und Ventil:

| Wert | Verhalten |
|---|---|
| **positiv** (z. B. `3`) | Pumpe startet **3 Sekunden BEVOR** das Ventil öffnet → Leitungsdruck aufbauen |
| **negativ** (z. B. `-3`) | Ventil öffnet **3 Sekunden BEVOR** die Pumpe startet → Druckstoß vermeiden |
| **0** | Pumpe und Ventil starten **gleichzeitig** |

```
attr Garten pumpStartDelay 3    # Pumpe startet 3s vor dem Ventil (empfohlen)
attr Garten pumpStartDelay -2   # Ventil öffnet 2s vor der Pumpe
```

---

## startCircuit-Modus

Mit `startCircuit <1-8>` kannst du einen **einzelnen Bewässerungskreis** starten — unabhängig vom Hauptzyklus.

**Anwendungsfall:** Gewächshaus mit eigenem Feuchtigkeitssensor, der per DOIF oder Notify das Bewässerungs-Modul ansteuert:

```perl
# Beispiel DOIF: Gewächshaus-Kreis 8 starten wenn Boden trocken
define di_gewaechshaus DOIF ([Gewaechshaus_Sensor:moisture] < 30)
    (set Garten startCircuit 8)
```

**Besonderheiten von `startCircuit`:**
- Prüft ob das Fass voll genug ist (füllt ggf. kurz auf)
- Startet Pumpe mit konfigurierten Delays
- Unterstützt automatische Pausen (`wateringPauseInterval`)
- **Wird NICHT unterbrochen** durch Regen-Logik oder Zeitplan-Trigger
- Nach Abschluss geht das System zurück in `idle`

---

## Beispielkonfiguration

### Tasmota 8-Kanal Relay Board (vollständiges Setup)

```
# Gerät anlegen
define Garten Gartenbewaesserung

# --- Ventile (Tasmota 8-Kanal: Device:POWER1..8) ---
attr Garten valve1Device   Tasmota8CH:POWER1
attr Garten valve2Device   Tasmota8CH:POWER2
attr Garten valve3Device   Tasmota8CH:POWER3
attr Garten valve4Device   Tasmota8CH:POWER4
attr Garten valve5Device   Tasmota8CH:POWER5
attr Garten valve6Device   Tasmota8CH:POWER6
attr Garten valve7Device   Tasmota8CH:POWER7
attr Garten valve8Device   Tasmota8CH:POWER8

# --- Laufzeiten pro Zone (Minuten) ---
attr Garten valve1Duration 10
attr Garten valve2Duration 15
attr Garten valve3Duration 10
attr Garten valve4Duration 20
attr Garten valve5Duration 10
attr Garten valve6Duration 15
attr Garten valve7Duration 10
attr Garten valve8Duration 30    # Gewächshaus braucht länger

attr Garten activeValves 1,2,3,4,5,6,7

# --- Pumpe und Timing ---
attr Garten pumpDevice            Pumpe_Relais
attr Garten pumpStartDelay        3
attr Garten pumpMaxRuntime        60
attr Garten ibcToBarrelPumpDevice IBC_Pumpe_Relais

# --- Fass ---
attr Garten barrelFillValveDevice  Hauswasser_Ventil
attr Garten barrelFullSensorDevice Fass_Sensor:state
attr Garten barrelEmptySensorDevice Fass_Leer_Sensor:state
attr Garten barrelFillDuration     10
attr Garten barrelFillThreshold    25
attr Garten barrelFillTimeout      30

# --- IBC-Container ---
attr Garten ibcFillValveDevice      IBC_Einlass_Ventil
attr Garten ibcToBarrelValveDevice  IBC_Auslauf_Ventil
attr Garten ibcFullSensorDevice     IBC_Voll_Sensor:state
attr Garten ibcEmptySensorDevice    IBC_Leer_Sensor:state
attr Garten ibcToBarrelDuration     20

# --- Sensoren ---
attr Garten rainSensorDevice        Regensensor:state
attr Garten rainDurationForIBC      30
attr Garten moistureSensorDevice    Bodensensor:moisture
attr Garten moistureThreshold       35

# --- Pausen ---
attr Garten wateringPauseInterval   10
attr Garten wateringPauseDuration   25

# --- Zeitplan ---
attr Garten startTime1  06:00
attr Garten startTime2  18:30
attr Garten weekdaysOnly 0

# --- Schaltwerte (Tasmota Standard) ---
attr Garten switchOnValue   ON
attr Garten switchOffValue  OFF

# Konfiguration prüfen
get Garten validate
```

---

## Versionsverlauf

| Version | Datum | Änderungen |
|---|---|---|
| **1.0.29** | 2026-06-04 | Fix: Wird **tatsächlich bewässert** (`RunCircuit`/`OpenValve`) und ist das Fass leer, stößt das Modul jetzt automatisch das Nachfüllen aus dem IBC (bzw. Hauswasser) an, statt nur abzubrechen. Bisher wurde der Refill ausschließlich beim Flankenwechsel des Fass-leer-Sensors (`HandleBarrelEmpty`) gestartet — blieb `barrelEmpty` dauerhaft `yes`, hing das System trotz vorhandenem IBC-Wasser dauerhaft im Zustand `stopped - barrel empty` fest. Die unterbrochene Operation wird nach dem Refill über die bestehende Resume-Logik fortgesetzt. Nachgefüllt wird **nur bei Bedarf**: `StartWatering` füllt nicht vor dem Feuchte-Check nach (kein Nachfüllen, wenn der Boden ohnehin feucht genug ist), und die regengesteuerte IBC-Befüllung löst weiterhin kein Fass-Nachfüllen aus (Oszillationsschutz `barrel↔IBC` bleibt erhalten). |
| **1.0.28** | 2026-05-31 | Fix: Pumpen-Watchdog wird beim Ausschalten der Pumpe in `SwitchDevice` zuverlässig gestoppt (vorher abhängig vom noch nicht aktualisierten Geräte-Reading). Behebt falschen `pumpOverrunAlert` nach Abschluss einer Bewässerung (`FinishWatering`/`FinishCircuit`) sowie während der Fass-Befüllung mitten im Zyklus. Neu: `startIBCFill` verweigert die Befüllung bei leerem Fass (kein Pumpen-Trockenlauf). |
| **1.0.27** | 2026-05-31 | Fix: Pumpen-Watchdog wird beim Fass-leer-Not-Aus (`HandleBarrelEmpty`) explizit gestoppt. Andernfalls blieb nach gestoppter IBC-Befüllung ein verwaister Watchdog-Timer aktiv und löste Minuten später einen falschen `pumpOverrunAlert` aus, obwohl die Pumpe längst aus war. |
| **1.0.26** | 2026-05-31 | Fix: Kein automatisches Fass-Nachfüllen mehr, wenn das Fass durch die IBC-Befüllung leergelaufen ist. Bisher startete direkt nach der IBC-Befüllung das Auffüllen der Regentonne (Rückpumpen aus dem IBC bzw. Hauswasser) — ein Pendeln Fass↔IBC. Die Regentonne füllt sich jetzt von selbst über den Regen; die IBC-Befüllung setzt erst fort, wenn der Fass-voll-Sensor wieder anschlägt. |
| **1.0.25** | 2026-05-25 | Neu: Attribut `barrelFillTimeout` — Watchdog für Fass-Befüllung. Schlägt `barrelFullSensorDevice` nicht innerhalb der konfigurierten Minuten an, wird `barrelFillTimeoutAlert` auf `yes` gesetzt (IBC leer oder Wasserzufuhr gestört). Reset automatisch bei `barrelFull:yes` oder `raining:yes`. |
| **1.0.24** | 2026-05-25 | Fix: Pumpen-Watchdog wird auch im manuellen Ventilmodus (`set startValve N`) gestartet. `stopValve` stoppt den Watchdog, damit kein verwaister `PumpOverrun`-Timer feuert. |
| **1.0.23** | 2026-05-24 | Fix: Pumpen-Watchdog wird bei Bewässerungs-/Kreis-Pausen korrekt gestoppt und beim Resume mit voller Laufzeit neu gestartet. Konsistentes Watchdog-Handling in `barrelEmpty`-Refill-Pausen. |
| **1.0.22** | 2026-05-24 | Fix: `barrelEmpty:no` stoppt einen laufenden Fass-Refill nicht mehr vorzeitig. Während aktivem Refill wird das Event nur geloggt. |
| **1.0.21** | 2026-05-19 | Neu: Pumpen-Laufzeit-Watchdog `pumpMaxRuntime` (1–240, 0=aus), Not-Aus bei Überlauf, Reading `pumpOverrunAlert`, manueller Reset per `set resetPumpOverrunAlert`. |
| **1.0.18** | 2026-05-10 | Fix: Nach `barrelEmpty`-Stop wird unterbrochene Bewässerung/`startCircuit` nach erfolgreichem Refill automatisch fortgesetzt (inkl. Restlaufzeit und Position im Zyklus). |
| **1.0.14** | 2026-05-02 | Fix: `manualCircuit`-Flag — `startCircuit` wird nicht mehr durch Regen-Logik oder Scheduler unterbrochen. Fix: `CheckBarrelFull` stoppt IBC→Fass-Transfer korrekt statt zurückzupumpen. Fix: `startIBCFill` blockiert Befüllung während aktivem IBC→Fass-Transfer. |
| **1.0.13** | 2026-04-29 | Fix: Automatische Pausen auch bei `startCircuit` (Einzelkreislauf) |
| **1.0.12** | 2026-04-29 | Fix: Endlosschleife nach Pause; negatives `pumpStartDelay`; IBC→Fass in Pausen; `ibcEmptySensorDevice`; Fass-voll stoppt Pause |
| **1.0.11** | 2026-04-29 | Neu: Automatische Füll-Pausen während Bewässerung (`wateringPauseInterval`/`wateringPauseDuration`) |
| **1.0.10** | 2026-04-29 | Neu: Ausführliche Dokumentation |
| **1.0.9** | 2026-04-29 | Neu: Verbleibende Zeit als Reading (`remainingTime`) |
| **1.0.8** | 2026-04-29 | Neu: Initiale Sensor-Werte beim Start auslesen |
| **1.0.7** | 2026-04-29 | Neu: Optionale separate Pumpe für IBC→Fass (`ibcToBarrelPumpDevice`) |
| **1.0.6** | 2026-04-29 | Neu: IBC-zu-Fass-Rücklauf mit Schwerkraft oder Pumpe |
| **1.0.5** | 2026-04-29 | Neu: Optionale separate Pumpe für IBC→Fass mit `pumpStartDelay` |
| **1.0.4** | 2026-04-29 | Neu: Ausführliches Set mit Validierung und Einzelkreislauf-Modus |
| **1.0.3** | 2026-04-29 | Fix: Set/Get-Befehle korrekt implementiert |
| **1.0.2** | 2026-04-29 | Neu: Dynamische Werte-Erkennung für Sensoren und Schalter |
| **1.0.1** | 2026-04-29 | Neu: MQTT2-Support für Relay Boards (`Device:Reading`-Format) |
| **1.0.0** | 2026-04-29 | Initiale Version mit allen Basis-Features |

---

## Lizenz

Dieses Modul steht unter der **GNU General Public License Version 2 (GPLv2)**.

```
This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.
```

Vollständiger Lizenztext: https://www.gnu.org/licenses/old-licenses/gpl-2.0.html
