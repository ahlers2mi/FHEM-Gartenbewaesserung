##############################################################################
#
#     98_Gartenbewaesserung.pm
#
#     FHEM Modul für intelligente Gartenbewässerung mit IBC-Container
#     Version 1.0.30 - 2026-06-09
#
#     Unterstützt MQTT2 Relay Boards (z.B. Tasmota)
#     Dynamische Werte-Erkennung (on/off, true/false, 1/0, etc.)
#     Automatische Füll-Pausen während Bewässerung
#
##############################################################################
#
# Versionshistorie:
# 1.0.30 - 2026-06-09  Neu: Loop-Breaker gegen endloses Nachfuell<->Leerlauf-Pendeln. Laeuft das Fass trotz
#                      wiederholtem Nachfuellen binnen Sekunden wieder leer (z.B. IBC leer und keine Hauswasser-
#                      Reserve), bricht das Modul nach barrelEmptyMaxRefillAttempts Versuchen (Default 3) ab,
#                      State 'stopped - no water'. Automatischer Neustart sobald wieder Wasser da ist:
#                      barrelFull, ibcEmpty:no (IBC hat Wasser) oder Regen. Neues Attribut barrelEmptyMaxRefillAttempts
#                      (0 = aus = altes Verhalten).
# 1.0.29 - 2026-06-04  Fix: Wird tatsaechlich bewaessert (RunCircuit / OpenValve), stoesst ein leeres Fass jetzt
#                      automatisch das Nachfuellen aus dem IBC (bzw. Hauswasser) an, statt nur abzubrechen. Bisher
#                      wurde der Refill nur beim Flankenwechsel des Fass-leer-Sensors gestartet; blieb barrelEmpty
#                      dauerhaft 'yes', haengte das System trotz vorhandenem IBC-Wasser dauerhaft in
#                      'stopped - barrel empty'. Die unterbrochene Operation wird nach dem Refill ueber die bestehende
#                      Resume-Logik fortgesetzt. Nur-bei-Bedarf: StartWatering fuellt NICHT vor dem Feuchte-Check nach
#                      (kein Nachfuellen, wenn der Boden ohnehin feucht genug ist), und die regengesteuerte
#                      IBC-Befuellung loest weiterhin kein Fass-Nachfuellen aus (Oszillationsschutz bleibt erhalten).
# 1.0.28 - 2026-05-31  Fix: Pumpen-Watchdog wird beim Ausschalten der Pumpe in SwitchDevice zuverlaessig gestoppt
#                      (vorher abhaengig vom noch nicht aktualisierten Geraete-Reading) - behebt falschen
#                      pumpOverrunAlert nach FinishWatering/FinishCircuit und waehrend FillBarrel
#                      Neu: StartIBCFill verweigert Befuellung bei leerem Fass (kein Pumpen-Trockenlauf)
# 1.0.27 - 2026-05-31  Fix: Pumpen-Watchdog wird beim Fass-leer-Not-Aus (HandleBarrelEmpty) explizit gestoppt -
#                      verhindert falschen pumpOverrunAlert durch verwaisten Timer nach gestoppter IBC-Befuellung
# 1.0.26 - 2026-05-31  Fix: Kein automatisches Fass-Nachfuellen mehr, wenn das Fass durch die IBC-Befuellung
#                      geleert wurde - verhindert Pendeln Fass<->IBC (Wasser wurde sofort zurueckgepumpt)
# 1.0.25 - 2026-05-25  Neu: Attribut barrelFillTimeout (Minuten, 0=aus) - Watchdog erkennt blockierte Fass-Befuellung
#                      Neu: Reading barrelFillTimeoutAlert (yes/no) - wird gesetzt wenn barrelFull nicht rechtzeitig kommt
#                      Neu: Alert wird automatisch zurueckgesetzt bei barrelFull:yes oder raining:yes
# 1.0.24 - 2026-05-25  Fix: Pumpen-Watchdog wird auch im manuellen Ventilmodus (set valve N) gestartet
#                      Fix: StopCurrentValve stoppt den Watchdog, damit kein verwaister PumpOverrun-Timer feuert
# 1.0.23 - 2026-05-24  Fix: Pumpen-Watchdog wird bei Bewässerungs-/Kreis-Pausen korrekt gestoppt und beim Resume neu gestartet
#                      Fix: Konsistentes Watchdog-Handling auch in barrelEmpty-Refill-Pausen
# 1.0.22 - 2026-05-24  Fix: barrelEmpty:no stoppt laufenden barrelEmpty-Refill nicht mehr vorzeitig
#                      Neu: barrelEmpty:no wird während aktivem Refill nur geloggt
# 1.0.21 - 2026-05-19  Neu: Pumpen-Laufzeit-Watchdog (pumpMaxRuntime) mit Overrun-Alarm und Not-Aus
# 1.0.20 - 2026-05-11  Fix: Event-basierte Sensorwerte
# 1.0.19 - 2026-05-10  Fix: barrelEmpty:no löst Bewässerung nicht mehr sofort aus
#                      Neu: Nach barrelEmpty wird Befüllpause gestartet (IBC oder Stadtwasser)
#                      Fix: Resume erst nach barrelFull-Event oder Pause-Timer
#                      Fix: barrelLevel=100 nur bei barrelFull-Sensor Auslösung
# 1.0.18 - 2026-05-10  Fix: Bewässerung/Kreis setzt nach barrelEmpty-Refill automatisch fort
#                      Neu: Restlaufzeit und Ventil/Kreis-Kontext werden bei barrelEmpty-Stopp gespeichert
# 1.0.17 - 2026-05-10  Fix: Verzögerter Pumpen-/Ventilstart wird abgebrochen wenn Kreis bereits beendet ist
#                      Fix: Bei sehr kurzer Restlaufzeit (<= abs(pumpStartDelay)) wird Delay ignoriert
# 1.0.16 - 2026-05-04  Neu: barrelEmptySensorDevice – Fass-leer-Sensor schaltet Pumpe sofort ab
#                      Neu: Bewässerung/Kreis wird gestoppt wenn Fass leer gemeldet wird
#                      Neu: Pumpe kann wieder starten sobald Fass-leer-Sensor inaktiv wird
# 1.0.15 - 2026-05-03  Fix: Ghost-Timer nach vorzeitigem Pause-Ende (phase: resuming hängt nicht mehr)
#                      Fix: remainingTime bleibt während Pause sichtbar (zeigt verbleibende Ventilzeit)
# 1.0.14 - 2026-05-02  Fix: manualCircuit-Flag verhindert Regen-/Schedule-Unterbrechung bei startCircuit
#                      Fix: CheckBarrelFull stoppt bei aktivem IBC→Fass-Transfer statt zurückzupumpen
#                      Fix: StartIBCFill verweigert Befüllung während aktivem IBC→Fass-Transfer
#                      Neu: Event-basierter IBC-Befüllungstrigger (Fass-voll-Sensor bei Regen)
#                      Neu: NotifyFn überwacht auch Rain-Sensor für sofortige Reaktion
#                      Neu: Vollständige Attribut-Beschreibungen im Commandref
# 1.0.13 - 2026-04-29  Fix: Automatische Pausen auch bei startCircuit (Einzelkreislauf)
# 1.0.12 - 2026-04-29  Fix: Endlosschleife nach Pause behoben (Restzeit wird korrekt fortgesetzt)
#                      Fix: Fass-voll Sensor schließt Ventil während Pause und beendet Pause vorzeitig
#                      Neu: Negatives pumpStartDelay (-X = Ventil X Sek VOR Pumpe öffnen)
#                      Neu: IBC→Fass Befüllung während Pausen (statt Hauswasseranschluss, wenn IBC nicht leer)
#                      Neu: ibcEmptySensorDevice für intelligente Quellwahl in Pausen
#                      Neu: Versionsnummer und Änderungshistorie
# 1.0.11 - 2026-04-29  Neu: Automatische Füll-Pausen während Bewässerung (wateringPauseInterval/Duration)
# 1.0.10 - 2026-04-29  Neu: Ausführliche Dokumentation
# 1.0.9  - 2026-04-29  Neu: Verbleibende Zeit als Reading (remainingTime)
# 1.0.8  - 2026-04-29  Neu: Initiale Sensor-Werte beim Start auslesen
# 1.0.7  - 2026-04-29  Neu: Optionale separate Pumpe für IBC→Fass Rücklauf (ibcToBarrelPumpDevice)
# 1.0.6  - 2026-04-29  Neu: IBC-zu-Fass Rücklauf mit Schwerkraft oder Pumpe
# 1.0.5  - 2026-04-29  Neu: Optionale separate Pumpe für IBC→Fass mit pumpStartDelay
# 1.0.4  - 2026-04-29  Neu: Ausführliches Set mit Validierung und Einzelkreislauf-Modus
# 1.0.3  - 2026-04-29  Fix: Set/Get Befehle korrekt implementiert
# 1.0.2  - 2026-04-29  Neu: Dynamische Werte-Erkennung für Sensoren und Schalter
# 1.0.1  - 2026-04-29  Neu: MQTT2 Support für Relay Boards (Device:Reading Format)
# 1.0.0  - 2026-04-29  Initiale Version mit allen Basis-Features
#
##############################################################################

package main;

use strict;
use warnings;
use POSIX;

##############################################################################
sub Gartenbewaesserung_Initialize {
    my ($hash) = @_;

    $hash->{DefFn}      = "Gartenbewaesserung_Define";
    $hash->{UndefFn}    = "Gartenbewaesserung_Undef";
    $hash->{SetFn}      = "Gartenbewaesserung_Set";
    $hash->{GetFn}      = "Gartenbewaesserung_Get";
    $hash->{AttrFn}     = "Gartenbewaesserung_Attr";
    $hash->{NotifyFn}   = "Gartenbewaesserung_Notify";

    $hash->{AttrList} =
        "valve1Device:textField valve2Device:textField valve3Device:textField valve4Device:textField " .
        "valve5Device:textField valve6Device:textField valve7Device:textField valve8Device:textField " .
        "pumpDevice:textField " .
        "ibcToBarrelPumpDevice:textField " .
        "barrelFillValveDevice:textField " .
        "barrelFullSensorDevice:textField " .
        "ibcFillValveDevice:textField " .
        "ibcToBarrelValveDevice:textField " .
        "ibcFullSensorDevice:textField " .
        "ibcEmptySensorDevice:textField " .
        "barrelEmptySensorDevice:textField " .
        "rainSensorDevice:textField " .
        "moistureSensorDevice:textField " .
        "valve1Duration:slider,1,1,120 valve2Duration:slider,1,1,120 " .
        "valve3Duration:slider,1,1,120 valve4Duration:slider,1,1,120 " .
        "valve5Duration:slider,1,1,120 valve6Duration:slider,1,1,120 " .
        "valve7Duration:slider,1,1,120 valve8Duration:slider,1,1,120 " .
        "barrelFillDuration:slider,1,1,60 " .
        "barrelFillThreshold:slider,0,5,100 " .
        "ibcToBarrelDuration:slider,1,1,60 " .
        "moistureThreshold:slider,0,5,100 " .
        "wateringPauseInterval:slider,0,1,60 " .
        "wateringPauseDuration:slider,0,1,60 " .
        "startTime1:textField startTime2:textField startTime3:textField " .
        "rainDurationForIBC:slider,5,5,180 " .
        "rainCheckInterval:slider,1,1,30 " .
        "pumpStartDelay:slider,-30,1,30 " .
        "pumpMaxRuntime:slider,0,1,240 " .
        "barrelFillTimeout:slider,0,1,120 " .
        "barrelEmptyMaxRefillAttempts:slider,0,1,10 " .
        "activeValves:textField " .
        "weekdaysOnly:0,1 " .
        "manualMode:0,1 " .
        "switchOnValue:textField switchOffValue:textField " .
        "rainSensorActiveValue:textField rainSensorInactiveValue:textField " .
        "barrelFullSensorActiveValue:textField barrelFullSensorInactiveValue:textField " .
        "ibcFullSensorActiveValue:textField ibcFullSensorInactiveValue:textField " .
        "ibcEmptySensorActiveValue:textField ibcEmptySensorInactiveValue:textField " .
        "barrelEmptySensorActiveValue:textField barrelEmptySensorInactiveValue:textField " .
        "moistureSensorReading:textField moistureSensorInvert:0,1 " .
        "disable:0,1 " .
        $readingFnAttributes;
}

##############################################################################
sub Gartenbewaesserung_Define {
    my ($hash, $def) = @_;
    my @a = split("[ \t][ \t]*", $def);

    return "Usage: define <name> Gartenbewaesserung" if(@a != 2);

    $hash->{VERSION}    = '1.0.30';

    my $name = $a[0];

    # Initialize readings
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "state", "initialized");
    readingsBulkUpdate($hash, "phase", "idle");
    readingsBulkUpdate($hash, "currentValve", "none");
    readingsBulkUpdate($hash, "cycleProgress", "0/0");
    readingsBulkUpdate($hash, "ibcFilling", "no");
    readingsBulkUpdate($hash, "ibcToBarrelActive", "no");
    readingsBulkUpdate($hash, "rainDetectedSince", "never");
    readingsBulkUpdate($hash, "remainingTime", "-");
    readingsBulkUpdate($hash, "pauseActive", "no");
    readingsBulkUpdate($hash, "pauseTimeRemaining", "-");
    readingsBulkUpdate($hash, "barrelEmpty", "no");
    readingsBulkUpdate($hash, "barrelFillTimeoutAlert", "no");
    readingsEndUpdate($hash, 1);

    # Set default attributes
    $attr{$name}{activeValves} = "1,2,3,4,5,6,7,8" if(!defined($attr{$name}{activeValves}));
    $attr{$name}{valve1Duration} = 15 if(!defined($attr{$name}{valve1Duration}));
    $attr{$name}{valve2Duration} = 15 if(!defined($attr{$name}{valve2Duration}));
    $attr{$name}{valve3Duration} = 15 if(!defined($attr{$name}{valve3Duration}));
    $attr{$name}{valve4Duration} = 15 if(!defined($attr{$name}{valve4Duration}));
    $attr{$name}{valve5Duration} = 15 if(!defined($attr{$name}{valve5Duration}));
    $attr{$name}{valve6Duration} = 15 if(!defined($attr{$name}{valve6Duration}));
    $attr{$name}{valve7Duration} = 15 if(!defined($attr{$name}{valve7Duration}));
    $attr{$name}{valve8Duration} = 15 if(!defined($attr{$name}{valve8Duration}));
    $attr{$name}{barrelFillDuration} = 10 if(!defined($attr{$name}{barrelFillDuration}));
    $attr{$name}{barrelFillThreshold} = 30 if(!defined($attr{$name}{barrelFillThreshold}));
    $attr{$name}{ibcToBarrelDuration} = 15 if(!defined($attr{$name}{ibcToBarrelDuration}));
    $attr{$name}{moistureThreshold} = 40 if(!defined($attr{$name}{moistureThreshold}));
    $attr{$name}{rainDurationForIBC} = 30 if(!defined($attr{$name}{rainDurationForIBC}));
    $attr{$name}{rainCheckInterval} = 5 if(!defined($attr{$name}{rainCheckInterval}));
    $attr{$name}{pumpStartDelay} = 3 if(!defined($attr{$name}{pumpStartDelay}));
    $attr{$name}{pumpMaxRuntime} = 0 if(!defined($attr{$name}{pumpMaxRuntime}));
    $attr{$name}{wateringPauseInterval} = 8 if(!defined($attr{$name}{wateringPauseInterval}));
    $attr{$name}{wateringPauseDuration} = 20 if(!defined($attr{$name}{wateringPauseDuration}));

    # Default values for switches and sensors
    $attr{$name}{switchOnValue} = "ON" if(!defined($attr{$name}{switchOnValue}));
    $attr{$name}{switchOffValue} = "OFF" if(!defined($attr{$name}{switchOffValue}));

    my $pumpDevice = AttrVal($name, "pumpDevice", "");
    my $ibcToBarrelPump = AttrVal($name, "ibcToBarrelPumpDevice", "");
    if(!Gartenbewaesserung_IsDeviceOn($name, $pumpDevice) &&
       !Gartenbewaesserung_IsDeviceOn($name, $ibcToBarrelPump)) {
        readingsSingleUpdate($hash, "pumpOverrunAlert", "no", 1);
    }

    # Read initial sensor values - immediate attempt + retry after 5 seconds
    Gartenbewaesserung_UpdateSensorReadings($hash);
    InternalTimer(gettimeofday() + 5, sub {
        Gartenbewaesserung_UpdateSensorReadings($hash);
    }, $hash);

    # Start timer for scheduled watering
    InternalTimer(gettimeofday() + 60, "Gartenbewaesserung_CheckSchedule", $hash);

    # Start timer for rain monitoring
    InternalTimer(gettimeofday() + 30, "Gartenbewaesserung_CheckRain", $hash);

    Log3 $name, 3, "$name: Gartenbewaesserung v" . $hash->{VERSION} . " initialized";

    Gartenbewaesserung_UpdateNotifyDev($hash);

    return undef;
}

##############################################################################
sub Gartenbewaesserung_Undef {
    my ($hash, $arg) = @_;

    RemoveInternalTimer($hash);
    Gartenbewaesserung_StopAll($hash);

    return undef;
}

##############################################################################
sub Gartenbewaesserung_Set {
    my ($hash, $name, $cmd, @args) = @_;

    my $list = "start:noArg stop:noArg " .
               "startCircuit:1,2,3,4,5,6,7,8 " .
               "startIBCFill:noArg stopIBCFill:noArg " .
               "startIBCtoBarrel:noArg stopIBCtoBarrel:noArg " .
               "startValve:1,2,3,4,5,6,7,8 stopValve:noArg " .
               "resetPumpOverrunAlert:noArg " .
               "refreshSensors:noArg " .
               "validate:noArg";

    if($cmd eq "start") {
        return Gartenbewaesserung_StartWatering($hash);
    }
    elsif($cmd eq "stop") {
        return Gartenbewaesserung_StopAll($hash);
    }
    elsif($cmd eq "startCircuit") {
        my $circuit = $args[0];
        return "Please specify circuit number (1-8)" if(!defined($circuit));
        return Gartenbewaesserung_StartCircuit($hash, $circuit);
    }
    elsif($cmd eq "startIBCFill") {
        return Gartenbewaesserung_StartIBCFill($hash, 1);
    }
    elsif($cmd eq "stopIBCFill") {
        return Gartenbewaesserung_StopIBCFill($hash);
    }
    elsif($cmd eq "startIBCtoBarrel") {
        return Gartenbewaesserung_StartIBCtoBarrel($hash);
    }
    elsif($cmd eq "stopIBCtoBarrel") {
        return Gartenbewaesserung_StopIBCtoBarrel($hash);
    }
    elsif($cmd eq "startValve") {
        my $valve = $args[0];
        return "Please specify valve number" if(!defined($valve));
        return Gartenbewaesserung_StartSingleValve($hash, $valve);
    }
    elsif($cmd eq "stopValve") {
        return Gartenbewaesserung_StopCurrentValve($hash);
    }
    elsif($cmd eq "resetPumpOverrunAlert") {
        readingsSingleUpdate($hash, "pumpOverrunAlert", "no", 1);
        return undef;
    }
    elsif($cmd eq "refreshSensors") {
        Gartenbewaesserung_UpdateSensorReadings($hash);
        return "Sensor readings updated";
    }
    elsif($cmd eq "validate") {
        return Gartenbewaesserung_ValidateConfig($hash);
    } else {
        return "Unknown argument $cmd, choose one of $list";
    }
}

##############################################################################
sub Gartenbewaesserung_Get {
    my ($hash, $name, $cmd, @args) = @_;

    my $list = "status:noArg config:noArg version:noArg";

    if($cmd eq "status") {
        return Gartenbewaesserung_GetStatus($hash);
    }
    elsif($cmd eq "config") {
        return Gartenbewaesserung_GetConfig($hash);
    }
    elsif($cmd eq "version") {
        return "Gartenbewaesserung Version " . $hash->{VERSION};
    } else {
        return "Unknown argument $cmd, choose one of $list";
    }
}

##############################################################################
sub Gartenbewaesserung_Attr {
    my ($cmd, $name, $attrName, $attrVal) = @_;
    my $hash = $defs{$name};

    if($cmd eq "set" && $attrName eq "pumpMaxRuntime") {
        return "pumpMaxRuntime must be a number between 0 and 240"
            if($attrVal !~ /^\d+$/ || $attrVal < 0 || $attrVal > 240);

        if($attrVal == 0) {
            Gartenbewaesserung_StopPumpWatchdog($hash);
        }
        else {
            my $pumpDevice = AttrVal($name, "pumpDevice", "");
            my $ibcToBarrelPump = AttrVal($name, "ibcToBarrelPumpDevice", "");
            if(Gartenbewaesserung_IsDeviceOn($name, $pumpDevice) ||
               Gartenbewaesserung_IsDeviceOn($name, $ibcToBarrelPump)) {
                Gartenbewaesserung_StartPumpWatchdog($hash);
            }
        }
    }

    if($cmd eq "del" && $attrName eq "pumpMaxRuntime") {
        Gartenbewaesserung_StopPumpWatchdog($hash);
    }

    # Update sensor readings when sensor attributes change
    if($cmd eq "set" && $attrName =~ /(barrel|ibc|rain|moisture).*Device/) {
        InternalTimer(gettimeofday() + 1, sub {
            Gartenbewaesserung_UpdateSensorReadings($hash);
            Gartenbewaesserung_UpdateNotifyDev($hash);  # ← NEU!
        }, $hash);
    }

    return undef;
}

##############################################################################
sub Gartenbewaesserung_Notify {
    my ($hash, $dev) = @_;
    my $name = $hash->{NAME};

    return "" if(IsDisabled($name));

    my $devName = $dev->{NAME};
    my $events = deviceEvents($dev, 1);
    return if(!$events);

    Log3 $name, 5, "$name: Notify called for device: $devName";  # ← NEU

    # Monitor sensor changes
    foreach my $event (@{$events}) {

        Log3 $name, 5, "$name: Processing event: $event";  # ← NEU  
    
        # Barrel full sensor
        my $barrelSensorDef = AttrVal($name, "barrelFullSensorDevice", "");
        if($barrelSensorDef ne "") {
            my ($barrelDev, $barrelReading) = Gartenbewaesserung_ParseDevice($barrelSensorDef);
            $barrelReading = "state" if($barrelReading eq "");  # ← NEU!
            if($devName eq $barrelDev) {
                my $activeValue = AttrVal($name, "barrelFullSensorActiveValue", "");
                if(Gartenbewaesserung_CheckSensorActive($name, $event, $barrelReading, $activeValue)) {
                    readingsSingleUpdate($hash, "barrelFull", "yes", 1);
                    Gartenbewaesserung_CheckBarrelFull($hash);
                    # If raining and idle, start IBC fill immediately (event-triggered)
                    if(ReadingsVal($name, "raining", "no") eq "yes" &&
                       !$hash->{HELPER}{ibcFilling} &&
                       !$hash->{HELPER}{watering} &&
                        !$hash->{HELPER}{circuitMode}) {
                        Log3 $name, 3, "$name: Barrel full and raining, starting IBC fill (event-triggered)";
                        Gartenbewaesserung_StartIBCFill($hash, 0);
                    }
                    if($hash->{HELPER}{barrelEmptyResumePending} && $hash->{HELPER}{barrelEmptyRefillPause}) {
                        Log3 $name, 3, "$name: Barrel full during refill pause, resuming interrupted operation";
                        Gartenbewaesserung_StopBarrelEmptyRefillPause($hash);
                        Gartenbewaesserung_ResumeAfterBarrelEmpty($hash);
                    }
                    # Recover from a no-water abort: the barrel is physically full again
                    Gartenbewaesserung_RecoverFromNoWater($hash, 1);
                }
                elsif(Gartenbewaesserung_CheckSensorInactive($name, $event, $barrelReading,
                      AttrVal($name, "barrelFullSensorInactiveValue", ""))) {
                    readingsSingleUpdate($hash, "barrelFull", "no", 1);
                }
            }
        }

        # IBC full sensor
        my $ibcSensorDef = AttrVal($name, "ibcFullSensorDevice", "");
        if($ibcSensorDef ne "") {
            my ($ibcDev, $ibcReading) = Gartenbewaesserung_ParseDevice($ibcSensorDef);
            $ibcReading = "state" if($ibcReading eq "");  # ← NEU!
            if($devName eq $ibcDev) {
                my $activeValue = AttrVal($name, "ibcFullSensorActiveValue", "");
                if(Gartenbewaesserung_CheckSensorActive($name, $event, $ibcReading, $activeValue)) {
                    readingsSingleUpdate($hash, "ibcFull", "yes", 1);
                    Gartenbewaesserung_CheckIBCFull($hash);
                }
                elsif(Gartenbewaesserung_CheckSensorInactive($name, $event, $ibcReading,
                      AttrVal($name, "ibcFullSensorInactiveValue", ""))) {
                    readingsSingleUpdate($hash, "ibcFull", "no", 1);
                }
            }
        }

        # IBC empty sensor
        my $ibcEmptySensorDef = AttrVal($name, "ibcEmptySensorDevice", "");
        if($ibcEmptySensorDef ne "") {
            my ($ibcEmptyDev, $ibcEmptyReading) = Gartenbewaesserung_ParseDevice($ibcEmptySensorDef);
            $ibcEmptyReading = "state" if($ibcEmptyReading eq "");  # ← NEU!
            if($devName eq $ibcEmptyDev) {
                my $activeValue = AttrVal($name, "ibcEmptySensorActiveValue", "");
                if(Gartenbewaesserung_CheckSensorActive($name, $event, $ibcEmptyReading, $activeValue)) {
                    readingsSingleUpdate($hash, "ibcEmpty", "yes", 1);
                }
                elsif(Gartenbewaesserung_CheckSensorInactive($name, $event, $ibcEmptyReading,
                      AttrVal($name, "ibcEmptySensorInactiveValue", ""))) {
                    readingsSingleUpdate($hash, "ibcEmpty", "no", 1);
                    # IBC has water again -> recover from a no-water abort if active
                    Gartenbewaesserung_RecoverFromNoWater($hash, 0);
                }
            }
        }

        # Barrel empty sensor
        my $barrelEmptySensorDef = AttrVal($name, "barrelEmptySensorDevice", "");
        if($barrelEmptySensorDef ne "") {
            my ($barrelEmptyDev, $barrelEmptyReading) = Gartenbewaesserung_ParseDevice($barrelEmptySensorDef);
            $barrelEmptyReading = "state" if($barrelEmptyReading eq "");  # ← NEU!
            if($devName eq $barrelEmptyDev) {
                my $activeValue = AttrVal($name, "barrelEmptySensorActiveValue", "");
                if(Gartenbewaesserung_CheckSensorActive($name, $event, $barrelEmptyReading, $activeValue)) {
                    readingsSingleUpdate($hash, "barrelEmpty", "yes", 1);
                    Log3 $name, 3, "$name: Barrel empty detected, stopping pump and watering";
                    Gartenbewaesserung_HandleBarrelEmpty($hash);
                }
                elsif(Gartenbewaesserung_CheckSensorInactive($name, $event, $barrelEmptyReading,
                      AttrVal($name, "barrelEmptySensorInactiveValue", ""))) {
                    my $resumePending = $hash->{HELPER}{barrelEmptyResumePending};
                    if($hash->{HELPER}{barrelEmptyRefilling}) {
                        Log3 $name, 3, "$name: barrelEmpty inactive during refill - letting timer/sensor finish the refill";
                        readingsSingleUpdate($hash, "barrelEmpty", "no", 1);
                    }
                    elsif($resumePending && !$hash->{HELPER}{noWaterAbort}) {
                        Log3 $name, 3, "$name: Barrel no longer empty, starting refill pause before resuming";
                        readingsSingleUpdate($hash, "barrelEmpty", "no", 1);
                        Gartenbewaesserung_StartBarrelEmptyRefillPause($hash);
                    }
                    else {
                        readingsSingleUpdate($hash, "barrelEmpty", "no", 1);
                        Log3 $name, 3, "$name: Barrel no longer empty, pump can be used again";
                    }
                }
            }
        }

        # Rain sensor - event-triggered response
        my $rainSensorDef = AttrVal($name, "rainSensorDevice", "");
        if($rainSensorDef ne "") {
            my ($rainDev, $rainReading) = Gartenbewaesserung_ParseDevice($rainSensorDef);
            $rainReading = "state" if($rainReading eq "");  # ← NEU!
            if($devName eq $rainDev) {
                my $activeValue = AttrVal($name, "rainSensorActiveValue", "");
                if(Gartenbewaesserung_CheckSensorActive($name, $event, $rainReading, $activeValue)) {
                    readingsSingleUpdate($hash, "raining", "yes", 1);
                    if(ReadingsVal($name, "barrelFillTimeoutAlert", "no") ne "no") {
                        readingsSingleUpdate($hash, "barrelFillTimeoutAlert", "no", 1);
                        Log3 $name, 3, "$name: Rain detected, clearing barrelFillTimeoutAlert";
                    }
                    Log3 $name, 4, "$name: Rain sensor active (event), triggering CheckRain immediately";
                    # Rain will refill the barrel/IBC -> recover from a no-water abort if active
                    Gartenbewaesserung_RecoverFromNoWater($hash, 0);
                    # Remove pending timer and run CheckRain right now
                    RemoveInternalTimer($hash, "Gartenbewaesserung_CheckRain");
                    Gartenbewaesserung_CheckRain($hash);
                }
                elsif(Gartenbewaesserung_CheckSensorInactive($name, $event, $rainReading,
                      AttrVal($name, "rainSensorInactiveValue", ""))) {
                    readingsSingleUpdate($hash, "raining", "no", 1);
                    delete $hash->{HELPER}{rainingSince};
                    Log3 $name, 4, "$name: Rain sensor inactive (event), stopping IBC fill if running";
                    if($hash->{HELPER}{ibcFilling}) {
                        Gartenbewaesserung_StopIBCFill($hash);
                    }
                }
            }
        }

        # Moisture sensor - live update
        my $moistureSensorDef = AttrVal($name, "moistureSensorDevice", "");
        if($moistureSensorDef ne "") {
            my ($moistureDev, $moistureReading) = Gartenbewaesserung_ParseDevice($moistureSensorDef);
            $moistureReading = AttrVal($name, "moistureSensorReading", "moisture") if($moistureReading eq "");
            if($devName eq $moistureDev && $event =~ /^$moistureReading:\s*(.+)$/) {
                my $value = $1;
                readingsSingleUpdate($hash, "soilMoisture", $value, 1);
                Log3 $name, 4, "$name: Soil moisture updated (event): $value";
            }
        }
    }

    return undef;
}

##############################################################################
# Update remaining time display
##############################################################################
sub Gartenbewaesserung_UpdateRemainingTime {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    RemoveInternalTimer($hash, "Gartenbewaesserung_UpdateRemainingTime");

    if(!defined($hash->{HELPER}{endTime}) || $hash->{HELPER}{endTime} <= 0) {
        readingsSingleUpdate($hash, "remainingTime", "-", 1);
        return;
    }

    my $remaining = $hash->{HELPER}{endTime} - time();

    if($remaining <= 0) {
        readingsSingleUpdate($hash, "remainingTime", "finishing...", 1);
        return;
    }

    # Format time
    my $timeStr;
    if($remaining >= 60) {
        my $minutes = int($remaining / 60);
        my $seconds = $remaining % 60;
        $timeStr = sprintf("%d min %d sec", $minutes, $seconds);
    }
    else {
        $timeStr = sprintf("%d sec", $remaining);
    }

    readingsSingleUpdate($hash, "remainingTime", $timeStr, 1);

    # Schedule next update in 10 seconds
    InternalTimer(gettimeofday() + 10, "Gartenbewaesserung_UpdateRemainingTime", $hash);
}

##############################################################################
# Update pause time remaining
##############################################################################
sub Gartenbewaesserung_UpdatePauseTime {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    RemoveInternalTimer($hash, "Gartenbewaesserung_UpdatePauseTime");

    if(!defined($hash->{HELPER}{pauseEndTime}) || $hash->{HELPER}{pauseEndTime} <= 0) {
        readingsSingleUpdate($hash, "pauseTimeRemaining", "-", 1);
        return;
    }

    my $remaining = $hash->{HELPER}{pauseEndTime} - time();

    if($remaining <= 0) {
        readingsSingleUpdate($hash, "pauseTimeRemaining", "finishing...", 1);
        return;
    }

    # Format time
    my $timeStr;
    if($remaining >= 60) {
        my $minutes = int($remaining / 60);
        my $seconds = $remaining % 60;
        $timeStr = sprintf("%d min %d sec", $minutes, $seconds);
    }
    else {
        $timeStr = sprintf("%d sec", $remaining);
    }

    readingsSingleUpdate($hash, "pauseTimeRemaining", $timeStr, 1);

    # Schedule next update in 10 seconds
    InternalTimer(gettimeofday() + 10, "Gartenbewaesserung_UpdatePauseTime", $hash);
}

##############################################################################
# Set end time and start countdown timer
##############################################################################
sub Gartenbewaesserung_SetEndTime {
    my ($hash, $durationMinutes) = @_;

    $hash->{HELPER}{endTime} = time() + ($durationMinutes * 60);
    Gartenbewaesserung_UpdateRemainingTime($hash);
}

##############################################################################
# Clear end time and stop countdown
##############################################################################
sub Gartenbewaesserung_ClearEndTime {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    delete $hash->{HELPER}{endTime};
    RemoveInternalTimer($hash, "Gartenbewaesserung_UpdateRemainingTime");
    readingsSingleUpdate($hash, "remainingTime", "-", 1);
}

##############################################################################
# Set pause end time and start countdown
##############################################################################
sub Gartenbewaesserung_SetPauseEndTime {
    my ($hash, $durationMinutes) = @_;

    $hash->{HELPER}{pauseEndTime} = time() + ($durationMinutes * 60);
    Gartenbewaesserung_UpdatePauseTime($hash);
}

##############################################################################
# Clear pause time
##############################################################################
sub Gartenbewaesserung_ClearPauseTime {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    delete $hash->{HELPER}{pauseEndTime};
    RemoveInternalTimer($hash, "Gartenbewaesserung_UpdatePauseTime");
    readingsSingleUpdate($hash, "pauseTimeRemaining", "-", 1);
}

##############################################################################
# Update sensor readings (initial read and refresh)
##############################################################################
sub Gartenbewaesserung_UpdateSensorReadings {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    Log3 $name, 4, "$name: Updating sensor readings";

    readingsBeginUpdate($hash);

    # Barrel full sensor
    my $barrelSensorDef = AttrVal($name, "barrelFullSensorDevice", "");
    if($barrelSensorDef ne "") {
        my $activeValue = AttrVal($name, "barrelFullSensorActiveValue", "");
        my $inactiveValue = AttrVal($name, "barrelFullSensorInactiveValue", "");
        my $value = Gartenbewaesserung_GetSensorValue($name, $barrelSensorDef, $activeValue, $inactiveValue);
        readingsBulkUpdate($hash, "barrelFull", $value ? "yes" : "no");
        Log3 $name, 4, "$name: Barrel full sensor: " . ($value ? "yes" : "no");
    }
    else {
        readingsBulkUpdate($hash, "barrelFull", "not configured");
    }

    # IBC full sensor
    my $ibcSensorDef = AttrVal($name, "ibcFullSensorDevice", "");
    if($ibcSensorDef ne "") {
        my $activeValue = AttrVal($name, "ibcFullSensorActiveValue", "");
        my $inactiveValue = AttrVal($name, "ibcFullSensorInactiveValue", "");
        my $value = Gartenbewaesserung_GetSensorValue($name, $ibcSensorDef, $activeValue, $inactiveValue);
        readingsBulkUpdate($hash, "ibcFull", $value ? "yes" : "no");
        Log3 $name, 4, "$name: IBC full sensor: " . ($value ? "yes" : "no");
    }
    else {
        readingsBulkUpdate($hash, "ibcFull", "not configured");
    }

    # IBC empty sensor
    my $ibcEmptySensorDef = AttrVal($name, "ibcEmptySensorDevice", "");
    if($ibcEmptySensorDef ne "") {
        my $activeValue = AttrVal($name, "ibcEmptySensorActiveValue", "");
        my $inactiveValue = AttrVal($name, "ibcEmptySensorInactiveValue", "");
        my $value = Gartenbewaesserung_GetSensorValue($name, $ibcEmptySensorDef, $activeValue, $inactiveValue);
        readingsBulkUpdate($hash, "ibcEmpty", $value ? "yes" : "no");
        Log3 $name, 4, "$name: IBC empty sensor: " . ($value ? "yes" : "no");
    }
    else {
        readingsBulkUpdate($hash, "ibcEmpty", "not configured");
    }

    # Barrel empty sensor
    my $barrelEmptySensorDef = AttrVal($name, "barrelEmptySensorDevice", "");
    if($barrelEmptySensorDef ne "") {
        my $activeValue = AttrVal($name, "barrelEmptySensorActiveValue", "");
        my $inactiveValue = AttrVal($name, "barrelEmptySensorInactiveValue", "");
        my $value = Gartenbewaesserung_GetSensorValue($name, $barrelEmptySensorDef, $activeValue, $inactiveValue);
        readingsBulkUpdate($hash, "barrelEmpty", $value ? "yes" : "no");
        Log3 $name, 4, "$name: Barrel empty sensor: " . ($value ? "yes" : "no");
    }
    else {
        readingsBulkUpdate($hash, "barrelEmpty", "not configured");
    }

    # Rain sensor
    my $rainSensorDef = AttrVal($name, "rainSensorDevice", "");
    if($rainSensorDef ne "") {
        my $activeValue = AttrVal($name, "rainSensorActiveValue", "");
        my $inactiveValue = AttrVal($name, "rainSensorInactiveValue", "");
        my $value = Gartenbewaesserung_GetSensorValue($name, $rainSensorDef, $activeValue, $inactiveValue);
        readingsBulkUpdate($hash, "raining", $value ? "yes" : "no");
        Log3 $name, 4, "$name: Rain sensor: " . ($value ? "yes" : "no");
    }
    else {
        readingsBulkUpdate($hash, "raining", "not configured");
    }

    # Moisture sensor
    my $moistureSensorDef = AttrVal($name, "moistureSensorDevice", "");
    if($moistureSensorDef ne "") {
        my ($moistureDev, $moistureReading) = Gartenbewaesserung_ParseDevice($moistureSensorDef);
        $moistureReading = AttrVal($name, "moistureSensorReading", "moisture") if($moistureReading eq "");

        if($moistureDev ne "" && defined($defs{$moistureDev})) {
            my $value = ReadingsVal($moistureDev, $moistureReading, "unknown");
            readingsBulkUpdate($hash, "soilMoisture", $value);
            Log3 $name, 4, "$name: Soil moisture: $value";
        }
    }
    else {
        readingsBulkUpdate($hash, "soilMoisture", "not configured");
    }

    readingsEndUpdate($hash, 1);
}

##############################################################################
# Default sensor values for auto-detection
##############################################################################
sub Gartenbewaesserung_DefaultSensorActiveValues {
    return ('on', 'ON', '1', 'true', 'yes', 'closed', 'active', 'wet', 'rain', 'raining');
}

sub Gartenbewaesserung_DefaultSensorInactiveValues {
    return ('off', 'OFF', '0', 'false', 'no', 'open', 'inactive', 'dry');
}

sub Gartenbewaesserung_SensorValueMatches {
    my ($value, @candidates) = @_;

    return 0 if(!defined($value) || $value eq "");

    foreach my $candidate (@candidates) {
        return 1 if($value =~ /^$candidate$/i);
    }

    return 0;
}

sub Gartenbewaesserung_ValidateSensorConfigEntry {
    my ($hash, $sensorLabel, $sensorDef, $activeAttrName, $inactiveAttrName, $missingLevel,
        $missingMessage, $errorsRef, $warningsRef, $infoRef) = @_;
    my $name = $hash->{NAME};

    if($sensorDef eq "") {
        if($missingLevel eq "warning") {
            push @$warningsRef, $missingMessage;
        }
        else {
            push @$infoRef, $missingMessage;
        }
        return;
    }

    my ($device, $reading) = Gartenbewaesserung_ParseDevice($sensorDef);
    if(!defined($defs{$device})) {
        push @$errorsRef, "$sensorLabel device '$device' does not exist";
        return;
    }

    $reading = "state" if($reading eq "");

    my $value = ReadingsVal($device, $reading, "unknown");
    my $activeValue = AttrVal($name, $activeAttrName, "");
    my $inactiveValue = AttrVal($name, $inactiveAttrName, "");
    my $activeDisplay = $activeValue ne "" ? $activeValue : "auto";
    my $inactiveDisplay = $inactiveValue ne "" ? $inactiveValue : "auto";

    my $matchesActive = $activeValue ne ""
        ? Gartenbewaesserung_SensorValueMatches($value, $activeValue)
        : Gartenbewaesserung_SensorValueMatches($value, Gartenbewaesserung_DefaultSensorActiveValues());
    my $matchesInactive = $inactiveValue ne ""
        ? Gartenbewaesserung_SensorValueMatches($value, $inactiveValue)
        : Gartenbewaesserung_SensorValueMatches($value, Gartenbewaesserung_DefaultSensorInactiveValues());

    if($value eq "" || $value eq "unknown") {
        push @$warningsRef, "$sensorLabel: current value for '$sensorDef' is '$value' - detection cannot be verified yet";
        push @$infoRef, "$sensorLabel: $sensorDef (current: $value, active=$activeDisplay, inactive=$inactiveDisplay) OK";
        return;
    }

    if($matchesActive || $matchesInactive) {
        if($activeValue eq "" && $inactiveValue eq "") {
            push @$infoRef, "$sensorLabel: $sensorDef (current: $value, auto-detected) OK";
        }
        else {
            push @$infoRef, "$sensorLabel: $sensorDef (current: $value, active=$activeDisplay, inactive=$inactiveDisplay) OK";
        }
        return;
    }

    if($activeValue eq "" && $inactiveValue eq "") {
        push @$warningsRef, "$sensorLabel: current value '$value' is not auto-detected - please set $activeAttrName and $inactiveAttrName";
    }
    else {
        push @$warningsRef, "$sensorLabel: current value '$value' matches neither active=$activeDisplay nor inactive=$inactiveDisplay";
    }

    push @$infoRef, "$sensorLabel: $sensorDef (current: $value, active=$activeDisplay, inactive=$inactiveDisplay) OK";
}

##############################################################################
# Validate configuration
##############################################################################
sub Gartenbewaesserung_ValidateConfig {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    my @errors;
    my @warnings;
    my @info;

    Log3 $name, 3, "$name: Starting configuration validation";

    # Version info
    push @info, "Version: " . $hash->{VERSION};

    # Check active valves
    my $activeValvesStr = AttrVal($name, "activeValves", "");
    if($activeValvesStr eq "") {
        push @errors, "No active valves configured (activeValves attribute is empty)";
    }
    else {
        my @activeValves = split(/,/, $activeValvesStr);
        @activeValves = grep { $_ =~ /^\d+$/ && $_ >= 1 && $_ <= 8 } @activeValves;

        if(scalar(@activeValves) == 0) {
            push @errors, "No valid valves in activeValves attribute";
        }
        else {
            push @info, "Active valves: " . join(", ", @activeValves);

            # Check each active valve
            foreach my $valveNum (@activeValves) {
                my $valveDevice = AttrVal($name, "valve${valveNum}Device", "");
                if($valveDevice eq "") {
                    push @errors, "Valve $valveNum is active but valve${valveNum}Device is not configured";
                }
                else {
                    my ($device, $reading) = Gartenbewaesserung_ParseDevice($valveDevice);
                    if(!defined($defs{$device})) {
                        push @errors, "Valve $valveNum: Device '$device' does not exist";
                    }
                    else {
                        push @info, "Valve $valveNum: $valveDevice (" .
                            AttrVal($name, "valve${valveNum}Duration", 15) . " min) OK";
                    }
                }
            }
        }
    }

    # Check pause settings
    my $pauseInterval = AttrVal($name, "wateringPauseInterval", 8);
    my $pauseDuration = AttrVal($name, "wateringPauseDuration", 20);
    if($pauseInterval > 0) {
        push @info, "Automatic pause: Every $pauseInterval min for $pauseDuration min refill";
    }
    else {
        push @info, "Automatic pause: DISABLED (continuous watering)";
    }

    # Check pump
    my $pumpDevice = AttrVal($name, "pumpDevice", "");
    if($pumpDevice eq "") {
        push @warnings, "No pump device configured (pumpDevice)";
    }
    else {
        my ($device, $reading) = Gartenbewaesserung_ParseDevice($pumpDevice);
        if(!defined($defs{$device})) {
            push @errors, "Pump device '$device' does not exist";
        }
        else {
            my $delay = AttrVal($name, "pumpStartDelay", 3);
            my $maxRuntime = AttrVal($name, "pumpMaxRuntime", 0);
            my $delayInfo = $delay < 0 ? "valve opens ${delay}s BEFORE pump" :
                           $delay > 0 ? "pump starts ${delay}s BEFORE valve" : "simultaneous";
            my $watchdogInfo = $maxRuntime > 0 ? ", watchdog ${maxRuntime}min" : ", watchdog disabled";
            push @info, "Pump: $pumpDevice ($delayInfo$watchdogInfo) OK";
        }
    }

    # Check barrel fill valve
    my $barrelFillValve = AttrVal($name, "barrelFillValveDevice", "");
    if($barrelFillValve eq "") {
        push @warnings, "No barrel fill valve configured (barrelFillValveDevice)";
    }
    else {
        my ($device, $reading) = Gartenbewaesserung_ParseDevice($barrelFillValve);
        if(!defined($defs{$device})) {
            push @errors, "Barrel fill valve device '$device' does not exist";
        }
        else {
            push @info, "Barrel fill valve (water supply): $barrelFillValve OK";
        }
    }

    # Check barrel full sensor
    my $barrelFullSensor = AttrVal($name, "barrelFullSensorDevice", "");
    Gartenbewaesserung_ValidateSensorConfigEntry($hash, "Barrel full sensor", $barrelFullSensor,
        "barrelFullSensorActiveValue", "barrelFullSensorInactiveValue", "warning",
        "No barrel full sensor configured (barrelFullSensorDevice)", \@errors, \@warnings, \@info);

    # Check IBC fill valve
    my $ibcFillValve = AttrVal($name, "ibcFillValveDevice", "");
    if($ibcFillValve eq "") {
        push @warnings, "No IBC fill valve configured (ibcFillValveDevice)";
    }
    else {
        my ($device, $reading) = Gartenbewaesserung_ParseDevice($ibcFillValve);
        if(!defined($defs{$device})) {
            push @errors, "IBC fill valve device '$device' does not exist";
        }
        else {
            push @info, "IBC fill valve (barrel→IBC): $ibcFillValve OK";

            # WARNING: Check if same as barrel fill valve
            if($barrelFillValve eq $ibcFillValve) {
                push @warnings, "⚠️  barrelFillValveDevice and ibcFillValveDevice are IDENTICAL! They should be different valves.";
            }
        }
    }

    # Check IBC to barrel valve
    my $ibcToBarrelValve = AttrVal($name, "ibcToBarrelValveDevice", "");
    if($ibcToBarrelValve eq "") {
        push @info, "No IBC to barrel valve configured (optional)";
    }
    else {
        my ($device, $reading) = Gartenbewaesserung_ParseDevice($ibcToBarrelValve);
        if(!defined($defs{$device})) {
            push @errors, "IBC to barrel valve device '$device' does not exist";
        }
        else {
            push @info, "IBC to barrel valve (IBC→barrel): $ibcToBarrelValve OK";
        }
    }

    # Check IBC to barrel pump (optional)
    my $ibcToBarrelPump = AttrVal($name, "ibcToBarrelPumpDevice", "");
    if($ibcToBarrelPump eq "") {
        push @info, "No IBC to barrel pump configured (using gravity)";
    }
    else {
        my ($device, $reading) = Gartenbewaesserung_ParseDevice($ibcToBarrelPump);
        if(!defined($defs{$device})) {
            push @errors, "IBC to barrel pump device '$device' does not exist";
        }
        else {
            push @info, "IBC to barrel pump: $ibcToBarrelPump OK";
        }
    }

    # Check IBC full sensor
    my $ibcFullSensor = AttrVal($name, "ibcFullSensorDevice", "");
    Gartenbewaesserung_ValidateSensorConfigEntry($hash, "IBC full sensor", $ibcFullSensor,
        "ibcFullSensorActiveValue", "ibcFullSensorInactiveValue", "warning",
        "No IBC full sensor configured (ibcFullSensorDevice)", \@errors, \@warnings, \@info);

    # Check IBC empty sensor
    my $ibcEmptySensor = AttrVal($name, "ibcEmptySensorDevice", "");
    Gartenbewaesserung_ValidateSensorConfigEntry($hash, "IBC empty sensor", $ibcEmptySensor,
        "ibcEmptySensorActiveValue", "ibcEmptySensorInactiveValue", "info",
        "No IBC empty sensor (optional, defaults to: use IBC if not full)", \@errors, \@warnings, \@info);

    # Check barrel empty sensor
    my $barrelEmptySensor = AttrVal($name, "barrelEmptySensorDevice", "");
    Gartenbewaesserung_ValidateSensorConfigEntry($hash, "Barrel empty sensor", $barrelEmptySensor,
        "barrelEmptySensorActiveValue", "barrelEmptySensorInactiveValue", "info",
        "No barrel empty sensor configured (optional, barrelEmptySensorDevice)", \@errors, \@warnings, \@info);

    # Check rain sensor
    my $rainSensor = AttrVal($name, "rainSensorDevice", "");
    Gartenbewaesserung_ValidateSensorConfigEntry($hash, "Rain sensor", $rainSensor,
        "rainSensorActiveValue", "rainSensorInactiveValue", "warning",
        "No rain sensor configured (rainSensorDevice) - IBC auto-fill disabled", \@errors, \@warnings, \@info);

    # Check moisture sensor
    my $moistureSensor = AttrVal($name, "moistureSensorDevice", "");
    if($moistureSensor eq "") {
        push @info, "No moisture sensor configured - watering will always run when scheduled";
    }
    else {
        my ($device, $reading) = Gartenbewaesserung_ParseDevice($moistureSensor);
        if(!defined($defs{$device})) {
            push @errors, "Moisture sensor device '$device' does not exist";
        }
        else {
            $reading = AttrVal($name, "moistureSensorReading", "moisture") if($reading eq "");
            my $value = ReadingsVal($device, $reading, "unknown");
            my $threshold = AttrVal($name, "moistureThreshold", 40);
            my $invert = AttrVal($name, "moistureSensorInvert", 0);
            push @info, "Moisture sensor: $moistureSensor:$reading (current: $value, threshold: $threshold, invert: $invert) OK";
        }
    }

    # Check switch values
    my $onValue = AttrVal($name, "switchOnValue", "ON");
    my $offValue = AttrVal($name, "switchOffValue", "OFF");
    push @info, "Switch values: ON='$onValue', OFF='$offValue'";

    # Check schedule
    my $hasSchedule = 0;
    for(my $i = 1; $i <= 3; $i++) {
        my $startTime = AttrVal($name, "startTime$i", "");
        if($startTime ne "") {
            if($startTime !~ /^\d{2}:\d{2}$/) {
                push @errors, "startTime$i has invalid format (should be HH:MM): $startTime";
            }
            else {
                push @info, "Schedule $i: $startTime";
                $hasSchedule = 1;
            }
        }
    }

    if(!$hasSchedule && !AttrVal($name, "manualMode", 0)) {
        push @warnings, "No schedule configured and manualMode is off - watering will only run manually";
    }

    # Build result
    my $result = "\n=== Configuration Validation ===\n\n";

    if(scalar(@errors) > 0) {
        $result .= "ERRORS (" . scalar(@errors) . "):\n";
        foreach my $err (@errors) {
            $result .= "  ❌ $err\n";
            Log3 $name, 2, "$name: Validation ERROR: $err";
        }
        $result .= "\n";
    }

    if(scalar(@warnings) > 0) {
        $result .= "WARNINGS (" . scalar(@warnings) . "):\n";
        foreach my $warn (@warnings) {
            $result .= "  ⚠️  $warn\n";
            Log3 $name, 3, "$name: Validation WARNING: $warn";
        }
        $result .= "\n";
    }

    if(scalar(@info) > 0) {
        $result .= "INFO:\n";
        foreach my $inf (@info) {
            $result .= "  ✓ $inf\n";
        }
        $result .= "\n";
    }

    if(scalar(@errors) == 0) {
        $result .= "✅ Configuration is " . (scalar(@warnings) > 0 ? "valid (with warnings)" : "valid") . "\n";
        Log3 $name, 3, "$name: Validation completed - configuration is valid";
    }
    else {
        $result .= "❌ Configuration has errors - please fix before operation\n";
    }

    return $result;
}

##############################################################################
# Get detailed configuration
##############################################################################
sub Gartenbewaesserung_GetConfig {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    my $config = "\n=== Gartenbewässerung Configuration ===\n";
    $config .= "Version: " . $hash->{VERSION} . "\n\n";

    # Valves
    $config .= "VENTILE:\n";
    my $activeValvesStr = AttrVal($name, "activeValves", "1,2,3,4,5,6,7,8");
    my @activeValves = split(/,/, $activeValvesStr);
    foreach my $v (@activeValves) {
        my $dev = AttrVal($name, "valve${v}Device", "not configured");
        my $dur = AttrVal($name, "valve${v}Duration", 15);
        $config .= sprintf("  Valve %d: %s (%d min)\n", $v, $dev, $dur);
    }

    # Pump
    $config .= "\nPUMPE:\n";
    my $pump = AttrVal($name, "pumpDevice", "not configured");
    my $pumpDelay = AttrVal($name, "pumpStartDelay", 3);
    my $pumpMaxRuntime = AttrVal($name, "pumpMaxRuntime", 0);
    my $delayText = $pumpDelay < 0 ? "valve opens " . abs($pumpDelay) . " sec BEFORE pump" :
                    $pumpDelay > 0 ? "pump starts $pumpDelay sec BEFORE valve" : "simultaneous";
    $config .= "  Main pump: $pump\n";
    $config .= "  Pump timing: $delayText\n";
    $config .= "  Pump max runtime watchdog: " . ($pumpMaxRuntime > 0 ? "$pumpMaxRuntime min" : "disabled") . "\n";

    my $ibcToBarrelPump = AttrVal($name, "ibcToBarrelPumpDevice", "not configured");
    $config .= "  IBC to barrel pump: $ibcToBarrelPump\n";

    # Pause settings
    $config .= "\nAUTOMATISCHE PAUSEN:\n";
    my $pauseInterval = AttrVal($name, "wateringPauseInterval", 8);
    my $pauseDuration = AttrVal($name, "wateringPauseDuration", 20);
    if($pauseInterval > 0) {
        $config .= "  Pause interval: Every $pauseInterval min\n";
        $config .= "  Pause duration: $pauseDuration min (refill from IBC or water supply)\n";
    }
    else {
        $config .= "  Automatic pause: DISABLED (continuous watering)\n";
    }

    # Barrel
    $config .= "\nFASS:\n";
    my $barrelValve = AttrVal($name, "barrelFillValveDevice", "not configured");
    my $barrelSensor = AttrVal($name, "barrelFullSensorDevice", "not configured");
    my $barrelEmptySensor = AttrVal($name, "barrelEmptySensorDevice", "not configured");
    my $barrelDur = AttrVal($name, "barrelFillDuration", 10);
    my $barrelThreshold = AttrVal($name, "barrelFillThreshold", 30);
    $config .= "  Fill valve (water supply): $barrelValve\n";
    $config .= "  Full sensor: $barrelSensor\n";
    $config .= "  Empty sensor: $barrelEmptySensor\n";
    $config .= "  Fill duration: $barrelDur min\n";
    $config .= "  Fill threshold: $barrelThreshold%\n";

    # IBC
    $config .= "\nIBC CONTAINER:\n";
    my $ibcValve = AttrVal($name, "ibcFillValveDevice", "not configured");
    my $ibcToBarrelValve = AttrVal($name, "ibcToBarrelValveDevice", "not configured");
    my $ibcSensor = AttrVal($name, "ibcFullSensorDevice", "not configured");
    my $ibcEmptySensor = AttrVal($name, "ibcEmptySensorDevice", "not configured");
    my $rainDur = AttrVal($name, "rainDurationForIBC", 30);
    my $ibcToBarrelDur = AttrVal($name, "ibcToBarrelDuration", 15);
    $config .= "  Fill valve (barrel→IBC): $ibcValve\n";
    $config .= "  To barrel valve (IBC→barrel): $ibcToBarrelValve\n";
    $config .= "  Full sensor: $ibcSensor\n";
    $config .= "  Empty sensor: $ibcEmptySensor\n";
    $config .= "  Rain duration needed: $rainDur min\n";
    $config .= "  IBC to barrel duration: $ibcToBarrelDur min\n";

    # Sensors
    $config .= "\nSENSOREN:\n";
    my $rain = AttrVal($name, "rainSensorDevice", "not configured");
    my $moisture = AttrVal($name, "moistureSensorDevice", "not configured");
    $config .= "  Rain sensor: $rain\n";
    $config .= "  Moisture sensor: $moisture\n";

    # Schedule
    $config .= "\nZEITPLAN:\n";
    for(my $i = 1; $i <= 3; $i++) {
        my $time = AttrVal($name, "startTime$i", "-");
        $config .= "  Start time $i: $time\n";
    }
    my $weekdays = AttrVal($name, "weekdaysOnly", 0) ? "yes" : "no";
    my $manual = AttrVal($name, "manualMode", 0) ? "yes" : "no";
    $config .= "  Weekdays only: $weekdays\n";
    $config .= "  Manual mode: $manual\n";

    # Values
    $config .= "\nWERTE:\n";
    $config .= "  Switch ON: " . AttrVal($name, "switchOnValue", "ON") . "\n";
    $config .= "  Switch OFF: " . AttrVal($name, "switchOffValue", "OFF") . "\n";
    $config .= "  Rain active: " . AttrVal($name, "rainSensorActiveValue", "auto") . "\n";
    $config .= "  Rain inactive: " . AttrVal($name, "rainSensorInactiveValue", "auto") . "\n";

    return $config;
}

##############################################################################
# Parse device definition (supports "Device" or "Device:Reading")
##############################################################################
sub Gartenbewaesserung_ParseDevice {
    my ($deviceDef) = @_;

    return ("", "") if(!defined($deviceDef) || $deviceDef eq "");

    if($deviceDef =~ /^([^:]+):(.+)$/) {
        # Format: Device:Reading (z.B. MQTT2_DVES_F96D88:POWER1)
        return ($1, $2);
    }
    else {
        # Format: Device (klassisches FHEM Device)
        return ($deviceDef, "");
    }
}

##############################################################################
# Check if a switch device is currently ON (based on switchOnValue)
##############################################################################
sub Gartenbewaesserung_IsDeviceOn {
    my ($name, $deviceDef) = @_;

    return 0 if(!defined($deviceDef) || $deviceDef eq "");

    my ($device, $reading) = Gartenbewaesserung_ParseDevice($deviceDef);
    return 0 if($device eq "");
    return 0 if(!defined($defs{$device}));

    $reading = "state" if($reading eq "");
    my $value = ReadingsVal($device, $reading, "");
    my $onValue = AttrVal($name, "switchOnValue", "ON");

    return ($value =~ /^$onValue$/i) ? 1 : 0;
}

##############################################################################
# Check if sensor is active based on event
##############################################################################
sub Gartenbewaesserung_CheckSensorActive {
    my ($name, $event, $reading, $customActiveValue) = @_;

    # If custom active value is defined, use it
    if(defined($customActiveValue) && $customActiveValue ne "") {
        if($reading ne "") {
            # Event format: "reading: value"
            return 1 if($event =~ /^$reading:?\s*$customActiveValue$/i);
        }
        else {
            # Event format: "value"
            return 1 if($event =~ /^$customActiveValue$/i);
        }        
        return 0;
    }

    # Default: Check for common "active" values
    my @activeValues = Gartenbewaesserung_DefaultSensorActiveValues();

    if($reading ne "") {
        foreach my $val (@activeValues) {
            return 1 if($event =~ /^$reading:?\s*$val$/i);
        }
    }
    else {
        foreach my $val (@activeValues) {
            return 1 if($event =~ /^$val$/i);
        }
    }

    return 0;
}

##############################################################################
# Check if sensor is inactive based on event
##############################################################################
sub Gartenbewaesserung_CheckSensorInactive {
    my ($name, $event, $reading, $customInactiveValue) = @_;

    # If custom inactive value is defined, use it
    if(defined($customInactiveValue) && $customInactiveValue ne "") {
        if($reading ne "") {
            return 1 if($event =~ /^$reading:?\s*$customInactiveValue$/i);
        }
        else {
            return 1 if($event =~ /^$customInactiveValue$/i);
        }
        return 0;
    }

    # Default: Check for common "inactive" values
    my @inactiveValues = Gartenbewaesserung_DefaultSensorInactiveValues();

    if($reading ne "") {
        foreach my $val (@inactiveValues) {
            return 1 if($event =~ /^$reading:?\s*$val$/i);
        }
    }
    else {
        foreach my $val (@inactiveValues) {
            return 1 if($event =~ /^$val$/i);
        }
    }

    return 0;
}

##############################################################################
# Get sensor value (returns 1 for active, 0 for inactive)
##############################################################################
sub Gartenbewaesserung_GetSensorValue {
    my ($name, $deviceDef, $customActiveValue, $customInactiveValue) = @_;

    return 0 if(!defined($deviceDef) || $deviceDef eq "");

    my ($device, $reading) = Gartenbewaesserung_ParseDevice($deviceDef);
    return 0 if($device eq "");
    return 0 if(!defined($defs{$device}));

    $reading = "state" if($reading eq "");
    my $value = ReadingsVal($device, $reading, "");

    return 0 if($value eq "");

    # Check custom values first
    if(defined($customActiveValue) && $customActiveValue ne "") {
        return 1 if($value =~ /^$customActiveValue$/i);
    }
    if(defined($customInactiveValue) && $customInactiveValue ne "") {
        return 0 if($value =~ /^$customInactiveValue$/i);
    }

    # Default active values
    my @activeValues = Gartenbewaesserung_DefaultSensorActiveValues();
    foreach my $val (@activeValues) {
        return 1 if($value =~ /^$val$/i);
    }

    return 0;
}

##############################################################################
# Determine barrel level after a refill/pause
##############################################################################
sub Gartenbewaesserung_GetBarrelLevelAfterRefill {
    my ($hash, $fallbackLevel) = @_;
    my $name = $hash->{NAME};

    $fallbackLevel = 50 if(!defined($fallbackLevel));

    my $barrelFullSensor = AttrVal($name, "barrelFullSensorDevice", "");
    return 100 if($barrelFullSensor eq "");
    return 100 if(ReadingsVal($name, "barrelFull", "no") eq "yes");

    return $fallbackLevel;
}

##############################################################################
# Switch device on/off (supports MQTT2 and classic devices)
##############################################################################
sub Gartenbewaesserung_SwitchDevice {
    my ($name, $deviceDef, $state) = @_;

    return if(!defined($deviceDef) || $deviceDef eq "");

    my ($device, $reading) = Gartenbewaesserung_ParseDevice($deviceDef);
    return if($device eq "");

    # Get custom on/off values
    my $onValue = AttrVal($name, "switchOnValue", "ON");
    my $offValue = AttrVal($name, "switchOffValue", "OFF");

    # Convert state to custom value
    my $cmdValue = ($state eq "on") ? $onValue : $offValue;

    if($reading ne "") {
        # MQTT2 Style: set Device Reading State
        fhem("set $device $reading $cmdValue");
        Log3 $name, 4, "$name: Switched $device $reading to $cmdValue";
    }
    else {
        # Classic Style: set Device State
        fhem("set $device $cmdValue");
        Log3 $name, 4, "$name: Switched $device to $cmdValue";
    }

    my $pumpDevice = AttrVal($name, "pumpDevice", "");
    my $ibcToBarrelPump = AttrVal($name, "ibcToBarrelPumpDevice", "");
    if($deviceDef eq $pumpDevice || $deviceDef eq $ibcToBarrelPump) {
        if($state eq "on") {
            Gartenbewaesserung_StartPumpWatchdog($defs{$name});
        }
        else {
            # Stop the watchdog whenever a pump is switched off. The main pump
            # (barrel->garden / barrel->IBC) and the IBC->barrel pump never run at
            # the same time, so switching either off means no pump is running.
            # NOTE: we must NOT gate this on IsDeviceOn() - right after the MQTT
            # "off" command the device reading is still stale ("on"), which would
            # leave a stray PumpOverrun timer running and fire a false
            # pumpOverrunAlert minutes later (e.g. after FinishWatering).
            Gartenbewaesserung_StopPumpWatchdog($defs{$name});
        }
    }
}

##############################################################################
# Start pump runtime watchdog timer
##############################################################################
sub Gartenbewaesserung_StartPumpWatchdog {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    RemoveInternalTimer($hash, "Gartenbewaesserung_PumpOverrun");

    my $maxRuntime = AttrVal($name, "pumpMaxRuntime", 0);
    return if($maxRuntime <= 0);

    InternalTimer(gettimeofday() + ($maxRuntime * 60), "Gartenbewaesserung_PumpOverrun", $hash);
    Log3 $name, 4, "$name: Pump watchdog started ($maxRuntime min)";
}

##############################################################################
# Stop pump runtime watchdog timer
##############################################################################
sub Gartenbewaesserung_StopPumpWatchdog {
    my ($hash) = @_;

    RemoveInternalTimer($hash, "Gartenbewaesserung_PumpOverrun");
}

##############################################################################
# Pump watchdog timeout handler (emergency stop)
##############################################################################
sub Gartenbewaesserung_PumpOverrun {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    my $maxRuntime = AttrVal($name, "pumpMaxRuntime", 0);

    Gartenbewaesserung_StopAll($hash);

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "pumpOverrunAlert", "yes");
    readingsBulkUpdate($hash, "state", "stopped - pump overrun");
    readingsEndUpdate($hash, 1);

    Log3 $name, 1, "$name: WARNUNG - Pumpe wurde nach $maxRuntime Minuten Maximallaufzeit abgeschaltet (pumpOverrunAlert)";
}

##############################################################################
# Start barrel-fill timeout watchdog (detects IBC empty / broken water supply
# when barrelFull sensor does not activate within configured time)
##############################################################################
sub Gartenbewaesserung_StartBarrelFillTimeout {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    RemoveInternalTimer($hash, "Gartenbewaesserung_BarrelFillTimeout");

    my $timeout = AttrVal($name, "barrelFillTimeout", 0);
    return if($timeout <= 0);

    # Watchdog only useful if a barrelFull sensor exists to reset it
    return if(AttrVal($name, "barrelFullSensorDevice", "") eq "");

    InternalTimer(gettimeofday() + ($timeout * 60), "Gartenbewaesserung_BarrelFillTimeout", $hash);
    Log3 $name, 4, "$name: Barrel-fill timeout watchdog started ($timeout min)";
}

##############################################################################
# Stop barrel-fill timeout watchdog
##############################################################################
sub Gartenbewaesserung_StopBarrelFillTimeout {
    my ($hash) = @_;
    RemoveInternalTimer($hash, "Gartenbewaesserung_BarrelFillTimeout");
}

##############################################################################
# Barrel-fill timeout handler: barrelFull did not trigger within timeout
##############################################################################
sub Gartenbewaesserung_BarrelFillTimeout {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    my $timeout = AttrVal($name, "barrelFillTimeout", 0);

    # If barrel is already full in the meantime, skip
    if(ReadingsVal($name, "barrelFull", "no") eq "yes") {
        return;
    }

    readingsSingleUpdate($hash, "barrelFillTimeoutAlert", "yes", 1);
    Log3 $name, 1, "$name: WARNUNG - Fass-Befuellung dauert seit $timeout Minuten an, barrelFull-Sensor reagiert nicht (IBC moeglicherweise leer oder Wasserzufuhr gestoert)";
}

##############################################################################
# Start single circuit with full logic (for external control like greenhouse)
##############################################################################
sub Gartenbewaesserung_StartCircuit {
    my ($hash, $circuitNum) = @_;
    my $name = $hash->{NAME};

    return "Circuit number must be between 1 and 8" if($circuitNum < 1 || $circuitNum > 8);

    my $valveDevice = AttrVal($name, "valve${circuitNum}Device", "");
    if($valveDevice eq "") {
        return "Circuit $circuitNum (valve${circuitNum}Device) is not configured";
    }

    # Stop any ongoing operations
    if($hash->{HELPER}{watering} || $hash->{HELPER}{circuitMode}) {
        Log3 $name, 3, "$name: Stopping current operations before starting circuit $circuitNum";
        Gartenbewaesserung_StopAll($hash);
        # Small delay
        InternalTimer(gettimeofday() + 2, sub {
            Gartenbewaesserung_StartCircuit($hash, $circuitNum);
        }, $hash);
        return "Stopping current operation, will start circuit $circuitNum in 2 seconds...";
    }

    # Set circuit mode
    $hash->{HELPER}{circuitMode} = 1;
    $hash->{HELPER}{manualCircuit} = 1;  # Prevents rain/schedule from interrupting manual circuit
    $hash->{HELPER}{circuitNumber} = $circuitNum;
    $hash->{HELPER}{circuitStartTime} = time();  # Track start time for pauses
    delete $hash->{HELPER}{valveRemainingTime};  # Clear any leftover remaining time

    # Fresh run -> reset the no-water loop-breaker state
    $hash->{HELPER}{barrelEmptyRefillAttempts} = 0;
    delete $hash->{HELPER}{lastWateringStart};
    delete $hash->{HELPER}{noWaterAbort};

    # Make absolutely sure IBC fill is stopped
    Gartenbewaesserung_StopIBCFill($hash);

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "state", "circuit mode");
    readingsBulkUpdate($hash, "phase", "starting circuit $circuitNum");
    readingsBulkUpdate($hash, "cycleProgress", "1/1");
    readingsBulkUpdate($hash, "pauseActive", "no");
    readingsEndUpdate($hash, 1);

    Log3 $name, 3, "$name: Starting circuit $circuitNum (independent mode - no IBC collection)";

    # Check if barrel needs filling
    my $barrelLevel = ReadingsVal($name, "barrelLevel", 100);
    my $threshold = AttrVal($name, "barrelFillThreshold", 30);

    if($barrelLevel < $threshold) {
        Log3 $name, 3, "$name: Barrel level low, filling before circuit $circuitNum";
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash, "phase", "filling barrel for circuit $circuitNum");
        readingsBulkUpdate($hash, "nextValve", $circuitNum);
        readingsEndUpdate($hash, 1);

        Gartenbewaesserung_FillBarrelForCircuit($hash, $circuitNum);
        return undef;
    }

    # Start circuit directly
    Gartenbewaesserung_RunCircuit($hash, $circuitNum);

    return undef;
}

##############################################################################
# Fill barrel for circuit mode
##############################################################################
sub Gartenbewaesserung_FillBarrelForCircuit {
    my ($hash, $circuitNum) = @_;
    my $name = $hash->{NAME};

    my $fillValve = AttrVal($name, "barrelFillValveDevice", "");
    if($fillValve eq "") {
        Log3 $name, 2, "$name: No barrel fill valve configured, continuing with circuit";
        Gartenbewaesserung_RunCircuit($hash, $circuitNum);
        return;
    }

    Gartenbewaesserung_SwitchDevice($name, $fillValve, "on");
    $hash->{HELPER}{barrelFilling} = 1;
    Gartenbewaesserung_StartBarrelFillTimeout($hash);

    my $duration = AttrVal($name, "barrelFillDuration", 10);

    # Set end time
    Gartenbewaesserung_SetEndTime($hash, $duration);

    Log3 $name, 3, "$name: Filling barrel for $duration minutes before circuit $circuitNum";

    # Schedule fill stop
    InternalTimer(gettimeofday() + ($duration * 60), sub {
        Gartenbewaesserung_StopBarrelFillForCircuit($hash, $circuitNum);
    }, $hash);
}

##############################################################################
# Stop barrel filling and continue with circuit
##############################################################################
sub Gartenbewaesserung_StopBarrelFillForCircuit {
    my ($hash, $circuitNum) = @_;
    my $name = $hash->{NAME};

    my $fillValve = AttrVal($name, "barrelFillValveDevice", "");
    if($fillValve ne "") {
        Gartenbewaesserung_SwitchDevice($name, $fillValve, "off");
    }

    $hash->{HELPER}{barrelFilling} = 0;
    Gartenbewaesserung_StopBarrelFillTimeout($hash);
    readingsSingleUpdate($hash, "barrelLevel", Gartenbewaesserung_GetBarrelLevelAfterRefill($hash, 50), 1);

    Gartenbewaesserung_ClearEndTime($hash);

    Log3 $name, 4, "$name: Barrel filling stopped, continuing with circuit $circuitNum";

    # Continue with circuit
    InternalTimer(gettimeofday() + 2, sub {
        Gartenbewaesserung_RunCircuit($hash, $circuitNum);
    }, $hash);
}

##############################################################################
# Run the circuit valve (with pause support!)
##############################################################################
sub Gartenbewaesserung_RunCircuit {
    my ($hash, $circuitNum) = @_;
    my $name = $hash->{NAME};

    my $valveDevice = AttrVal($name, "valve${circuitNum}Device", "");
    my $duration = AttrVal($name, "valve${circuitNum}Duration", 15);

    # Check if we have remaining time from a pause
    if(defined($hash->{HELPER}{valveRemainingTime}) && $hash->{HELPER}{valveRemainingTime} > 0) {
        $duration = $hash->{HELPER}{valveRemainingTime};
        delete $hash->{HELPER}{valveRemainingTime};
        Log3 $name, 4, "$name: Circuit $circuitNum using remaining time: $duration minutes";
    }

    # Make sure IBC valve is closed
    Gartenbewaesserung_StopIBCFill($hash);

    # Check if barrel is empty - do not run pump, but try to refill it first
    if(ReadingsVal($name, "barrelEmpty", "no") eq "yes") {
        Log3 $name, 3, "$name: Cannot start circuit $circuitNum - barrel is empty";
        my $refilling = Gartenbewaesserung_TriggerBarrelRefillIfPossible($hash);
        readingsSingleUpdate($hash, "state", "stopped - barrel empty", 1)
            if(!$refilling && !$hash->{HELPER}{noWaterAbort});
        return;
    }

    # Mark the start of actual watering (used by the no-water loop-breaker)
    $hash->{HELPER}{lastWateringStart} = time();

    # Check if pause is needed DURING this circuit run
    my $pauseInterval = AttrVal($name, "wateringPauseInterval", 8);
    if($pauseInterval > 0) {
        my $lastPauseEnd = $hash->{HELPER}{lastPauseEnd} || $hash->{HELPER}{circuitStartTime} || time();
        my $elapsedMinutes = (time() - $lastPauseEnd) / 60;
        my $timeUntilPause = $pauseInterval - $elapsedMinutes;

        if($timeUntilPause >= 0 && $timeUntilPause < $duration) {
            # Pause is needed DURING this circuit
            Log3 $name, 4, "$name: Circuit $circuitNum: Will pause after $timeUntilPause minutes (valve duration: $duration min)";

            # Store remaining time for after pause
            $hash->{HELPER}{valveRemainingTime} = $duration - $timeUntilPause;

            # Run valve for partial time only
            $duration = $timeUntilPause;
            Log3 $name, 4, "$name: Circuit $circuitNum will run for $duration minutes until pause";
        }
    }

    # Get pump and delay
    my $pumpDevice = AttrVal($name, "pumpDevice", "");
    my $delay = AttrVal($name, "pumpStartDelay", 3);
    my $effectiveDelay = $delay;

    if($delay != 0 && ($duration * 60) <= abs($delay)) {
        $effectiveDelay = 0;
        Log3 $name, 4, "$name: Circuit $circuitNum duration too short for pumpStartDelay ($delay s), using simultaneous start";
    }

    if($pumpDevice ne "") {
        if($effectiveDelay < 0) {
            # Negative delay: Open valve FIRST, then pump
            Gartenbewaesserung_SwitchDevice($name, $valveDevice, "on");
            Log3 $name, 4, "$name: Circuit $circuitNum valve opened (negative delay)";

            InternalTimer(gettimeofday() + abs($effectiveDelay), sub {
                return if(!$hash->{HELPER}{circuitMode});
                my $currentValve = ReadingsVal($name, "currentValve", "none");
                return if($currentValve eq "none" || $currentValve ne $circuitNum);
                Gartenbewaesserung_SwitchDevice($name, $pumpDevice, "on");
                Log3 $name, 4, "$name: Pump started after valve (negative delay)";
            }, $hash);
        }
        elsif($effectiveDelay > 0) {
            # Positive delay: Start pump FIRST, wait, then valve
            Gartenbewaesserung_SwitchDevice($name, $pumpDevice, "on");
            Log3 $name, 4, "$name: Pump started for circuit $circuitNum";

            InternalTimer(gettimeofday() + $effectiveDelay, sub {
                return if(!$hash->{HELPER}{circuitMode});
                my $currentValve = ReadingsVal($name, "currentValve", "none");
                return if($currentValve eq "none" || $currentValve ne $circuitNum);
                Gartenbewaesserung_SwitchDevice($name, $valveDevice, "on");
                Log3 $name, 4, "$name: Circuit $circuitNum valve opened after pump delay";
            }, $hash);
        }
        else {
            # Zero delay: Simultaneous
            Gartenbewaesserung_SwitchDevice($name, $pumpDevice, "on");
            Gartenbewaesserung_SwitchDevice($name, $valveDevice, "on");
            Log3 $name, 4, "$name: Pump and valve started simultaneously";
        }
    }
    else {
        # No pump, just open valve
        Gartenbewaesserung_SwitchDevice($name, $valveDevice, "on");
    }

    # Set end time
    Gartenbewaesserung_SetEndTime($hash, $duration);

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "phase", "watering circuit $circuitNum");
    readingsBulkUpdate($hash, "currentValve", $circuitNum);
    readingsEndUpdate($hash, 1);

    Log3 $name, 3, "$name: Circuit $circuitNum watering for $duration minutes";

    # Schedule valve close
    $hash->{HELPER}{valveCloseTimer} = gettimeofday() + ($duration * 60);
    InternalTimer($hash->{HELPER}{valveCloseTimer}, sub {
        Gartenbewaesserung_FinishOrPauseCircuit($hash, $circuitNum);
    }, $hash);
}

##############################################################################
# Finish or pause circuit (checks if pause needed)
##############################################################################
sub Gartenbewaesserung_FinishOrPauseCircuit {
    my ($hash, $circuitNum) = @_;
    my $name = $hash->{NAME};

    # Close valve and pump
    my $valveDevice = AttrVal($name, "valve${circuitNum}Device", "");
    Gartenbewaesserung_SwitchDevice($name, $valveDevice, "off");

    my $pumpDevice = AttrVal($name, "pumpDevice", "");
    if($pumpDevice ne "") {
        Gartenbewaesserung_SwitchDevice($name, $pumpDevice, "off");
    }

    delete $hash->{HELPER}{valveCloseTimer};
    Gartenbewaesserung_ClearEndTime($hash);
    readingsSingleUpdate($hash, "currentValve", "none", 1);

    # Decrease barrel level (simulated)
    my $currentLevel = ReadingsVal($name, "barrelLevel", 100);
    my $newLevel = $currentLevel - 12;
    $newLevel = 0 if($newLevel < 0);
    readingsSingleUpdate($hash, "barrelLevel", $newLevel, 1);

    # Check if we have remaining time (pause is needed)
    if(defined($hash->{HELPER}{valveRemainingTime}) && $hash->{HELPER}{valveRemainingTime} > 0) {
        Log3 $name, 4, "$name: Circuit $circuitNum has remaining time, starting pause";
        Gartenbewaesserung_StartCircuitPause($hash, $circuitNum);
        return;
    }

    # No remaining time, circuit is complete
    Gartenbewaesserung_FinishCircuit($hash, $circuitNum);
}

##############################################################################
# Start pause for circuit mode
##############################################################################
sub Gartenbewaesserung_StartCircuitPause {
    my ($hash, $circuitNum) = @_;
    my $name = $hash->{NAME};

    my $pauseDuration = AttrVal($name, "wateringPauseDuration", 20);

    Log3 $name, 3, "$name: Starting circuit $circuitNum pause for $pauseDuration minutes (barrel refill)";

    $hash->{HELPER}{pauseActive} = 1;
    $hash->{HELPER}{pauseStartTime} = time();
    $hash->{HELPER}{pausedCircuit} = $circuitNum;

    Gartenbewaesserung_ClearEndTime($hash);
    Gartenbewaesserung_SetPauseEndTime($hash, $pauseDuration);
    Gartenbewaesserung_StartBarrelFillTimeout($hash);

    if(defined($hash->{HELPER}{valveRemainingTime}) && $hash->{HELPER}{valveRemainingTime} > 0) {
        my $rem = $hash->{HELPER}{valveRemainingTime};
        my $timeStr = $rem >= 1 ? sprintf("%d min", $rem) : "< 1 min";
        readingsSingleUpdate($hash, "remainingTime", "$timeStr (paused)", 1);
    }

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "state", "paused");
    readingsBulkUpdate($hash, "phase", "pause - refilling");
    readingsBulkUpdate($hash, "pauseActive", "yes");
    readingsEndUpdate($hash, 1);

    Gartenbewaesserung_StopPumpWatchdog($hash);

    # Fill from IBC or water supply
    my $ibcEmpty = ReadingsVal($name, "ibcEmpty", "no");

    if($ibcEmpty eq "yes") {
        # Use water supply
        Log3 $name, 3, "$name: IBC empty, using water supply to fill barrel";
        my $fillValve = AttrVal($name, "barrelFillValveDevice", "");
        if($fillValve ne "") {
            Gartenbewaesserung_SwitchDevice($name, $fillValve, "on");
            $hash->{HELPER}{pauseSource} = "water_supply";
        }
    }
    else {
        # Fill from IBC
        Log3 $name, 3, "$name: IBC has water, filling barrel from IBC";

        my $ibcToBarrelPump = AttrVal($name, "ibcToBarrelPumpDevice", "");
        my $ibcToBarrelValve = AttrVal($name, "ibcToBarrelValveDevice", "");

        if($ibcToBarrelPump ne "") {
            Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelPump, "on");

            my $delay = AttrVal($name, "pumpStartDelay", 3);
            $delay = abs($delay);

            InternalTimer(gettimeofday() + $delay, sub {
                if($ibcToBarrelValve ne "") {
                    Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelValve, "on");
                }
            }, $hash);
        }
        else {
            if($ibcToBarrelValve ne "") {
                Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelValve, "on");
            }
        }

        $hash->{HELPER}{pauseSource} = "ibc";
    }

    # Schedule pause end
    $hash->{HELPER}{pauseEndTimer} = gettimeofday() + ($pauseDuration * 60);
    InternalTimer($hash->{HELPER}{pauseEndTimer}, "Gartenbewaesserung_EndCircuitPauseTimer", $hash);
}

##############################################################################
# Named timer callback for circuit pause end (needed for RemoveInternalTimer)
##############################################################################
sub Gartenbewaesserung_EndCircuitPauseTimer {
    my ($hash) = @_;
    my $circuitNum = $hash->{HELPER}{pausedCircuit};
    Gartenbewaesserung_EndCircuitPause($hash, $circuitNum);
}

##############################################################################
# End circuit pause and resume
##############################################################################
sub Gartenbewaesserung_EndCircuitPause {
    my ($hash, $circuitNum) = @_;
    my $name = $hash->{NAME};

    return if(!$hash->{HELPER}{pauseActive});

    Log3 $name, 3, "$name: Ending circuit $circuitNum pause, resuming";

    # Close fill valves
    my $pauseSource = $hash->{HELPER}{pauseSource} || "";

    if($pauseSource eq "water_supply") {
        my $fillValve = AttrVal($name, "barrelFillValveDevice", "");
        if($fillValve ne "") {
            Gartenbewaesserung_SwitchDevice($name, $fillValve, "off");
        }
    }
    elsif($pauseSource eq "ibc") {
        my $ibcToBarrelValve = AttrVal($name, "ibcToBarrelValveDevice", "");
        if($ibcToBarrelValve ne "") {
            Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelValve, "off");
        }

        my $ibcToBarrelPump = AttrVal($name, "ibcToBarrelPumpDevice", "");
        if($ibcToBarrelPump ne "") {
            Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelPump, "off");
        }
    }

    $hash->{HELPER}{pauseActive} = 0;
    $hash->{HELPER}{lastPauseEnd} = time();
    delete $hash->{HELPER}{pausedCircuit};
    delete $hash->{HELPER}{pauseSource};
    delete $hash->{HELPER}{pauseStartTime};
    delete $hash->{HELPER}{pauseEndTimer};

    Gartenbewaesserung_StopBarrelFillTimeout($hash);

    readingsSingleUpdate($hash, "barrelLevel", Gartenbewaesserung_GetBarrelLevelAfterRefill($hash, 50), 1);
    Gartenbewaesserung_ClearPauseTime($hash);

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "state", "circuit mode");
    readingsBulkUpdate($hash, "phase", "resuming circuit $circuitNum");
    readingsBulkUpdate($hash, "pauseActive", "no");
    readingsEndUpdate($hash, 1);

    # Resume circuit with remaining time
    InternalTimer(gettimeofday() + 2, sub {
        Gartenbewaesserung_RunCircuit($hash, $circuitNum);
        my $pumpDevice = AttrVal($name, "pumpDevice", "");
        my $ibcToBarrelPump = AttrVal($name, "ibcToBarrelPumpDevice", "");
        if(Gartenbewaesserung_IsDeviceOn($name, $pumpDevice) ||
           Gartenbewaesserung_IsDeviceOn($name, $ibcToBarrelPump)) {
            Gartenbewaesserung_StartPumpWatchdog($hash);
        }
    }, $hash);
}

##############################################################################
# Finish circuit watering
##############################################################################
sub Gartenbewaesserung_FinishCircuit {
    my ($hash, $circuitNum) = @_;
    my $name = $hash->{NAME};

    $hash->{HELPER}{circuitMode} = 0;
    delete $hash->{HELPER}{manualCircuit};
    delete $hash->{HELPER}{circuitNumber};
    delete $hash->{HELPER}{circuitStartTime};
    delete $hash->{HELPER}{lastPauseEnd};
    delete $hash->{HELPER}{valveRemainingTime};

    # Circuit completed normally -> reset the no-water loop-breaker state
    $hash->{HELPER}{barrelEmptyRefillAttempts} = 0;
    delete $hash->{HELPER}{lastWateringStart};
    delete $hash->{HELPER}{noWaterAbort};

    Gartenbewaesserung_ClearEndTime($hash);

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "state", "idle");
    readingsBulkUpdate($hash, "phase", "idle");
    readingsBulkUpdate($hash, "currentValve", "none");
    readingsBulkUpdate($hash, "lastCircuitWatering", TimeNow());
    readingsEndUpdate($hash, 1);

    Log3 $name, 3, "$name: Circuit $circuitNum watering finished";
}

##############################################################################
# Start complete watering cycle
##############################################################################
sub Gartenbewaesserung_StartWatering {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    return "Watering disabled" if(IsDisabled($name));

    # Check moisture if sensor configured
    my $moistureSensorDef = AttrVal($name, "moistureSensorDevice", "");
    if($moistureSensorDef ne "") {
        my ($moistureDev, $moistureReading) = Gartenbewaesserung_ParseDevice($moistureSensorDef);
        $moistureReading = AttrVal($name, "moistureSensorReading", "moisture") if($moistureReading eq "");

        my $moisture = ReadingsVal($moistureDev, $moistureReading, 100);
        my $threshold = AttrVal($name, "moistureThreshold", 40);
        my $invert = AttrVal($name, "moistureSensorInvert", 0);

        # If inverted, high value means dry (needs water)
        my $needsWater = $invert ? ($moisture > $threshold) : ($moisture < $threshold);

        if(!$needsWater) {
            Log3 $name, 3, "$name: Moisture level $moisture% " .
                ($invert ? "below" : "above") . " threshold $threshold%, skipping watering";
            readingsSingleUpdate($hash, "state", "skipped - soil moist enough", 1);
            return "Soil moisture sufficient, watering not needed";
        }
    }

    # Get active valves
    my $activeValvesStr = AttrVal($name, "activeValves", "1,2,3,4,5,6,7,8");
    my @activeValves = split(/,/, $activeValvesStr);
    @activeValves = grep { $_ =~ /^\d+$/ && $_ >= 1 && $_ <= 8 } @activeValves;

    if(scalar(@activeValves) == 0) {
        return "No active valves configured";
    }

    # Store watering plan
    $hash->{HELPER}{wateringQueue} = \@activeValves;
    $hash->{HELPER}{wateringIndex} = 0;
    $hash->{HELPER}{totalValves} = scalar(@activeValves);
    $hash->{HELPER}{watering} = 1;
    $hash->{HELPER}{wateringStartTime} = time();  # Track start time for pauses
    delete $hash->{HELPER}{valveRemainingTime};   # Clear any leftover remaining time

    # Fresh run -> reset the no-water loop-breaker state
    $hash->{HELPER}{barrelEmptyRefillAttempts} = 0;
    delete $hash->{HELPER}{lastWateringStart};
    delete $hash->{HELPER}{noWaterAbort};

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "pumpOverrunAlert", "no");
    readingsBulkUpdate($hash, "state", "watering");
    readingsBulkUpdate($hash, "phase", "starting");
    readingsBulkUpdate($hash, "cycleProgress", "0/" . scalar(@activeValves));
    readingsBulkUpdate($hash, "pauseActive", "no");
    readingsEndUpdate($hash, 1);

    Log3 $name, 3, "$name: Starting watering cycle with " . scalar(@activeValves) . " valves: " . join(", ", @activeValves);

    # Start first valve
    Gartenbewaesserung_NextValve($hash);

    return undef;
}

##############################################################################
# Calculate remaining time until next pause
##############################################################################
sub Gartenbewaesserung_TimeUntilNextPause {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    my $pauseInterval = AttrVal($name, "wateringPauseInterval", 8);

    # If pause interval is 0, no pauses
    return -1 if($pauseInterval == 0);

    # Calculate time since watering started (or last pause ended)
    my $lastPauseEnd = $hash->{HELPER}{lastPauseEnd} || $hash->{HELPER}{wateringStartTime} || time();
    my $elapsedMinutes = (time() - $lastPauseEnd) / 60;

    my $remainingMinutes = $pauseInterval - $elapsedMinutes;

    return $remainingMinutes > 0 ? $remainingMinutes : 0;
}

##############################################################################
# Start watering pause for barrel refill
##############################################################################
sub Gartenbewaesserung_StartWateringPause {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    my $pauseDuration = AttrVal($name, "wateringPauseDuration", 20);

    Log3 $name, 3, "$name: Starting watering pause for $pauseDuration minutes (barrel refill)";

    # Store current valve info for resume
    my $currentValve = ReadingsVal($name, "currentValve", "none");
    $hash->{HELPER}{pausedValve} = $currentValve;

    # Stop current valve and pump
    if($currentValve ne "none" && $currentValve =~ /^\d+$/) {
        my $valveDevice = AttrVal($name, "valve${currentValve}Device", "");
        if($valveDevice ne "") {
            Gartenbewaesserung_SwitchDevice($name, $valveDevice, "off");
            Log3 $name, 4, "$name: Closed valve $currentValve for pause";
        }
    }

    # Stop pump
    my $pumpDevice = AttrVal($name, "pumpDevice", "");
    if($pumpDevice ne "") {
        Gartenbewaesserung_SwitchDevice($name, $pumpDevice, "off");
        Log3 $name, 4, "$name: Stopped pump for pause";
    }

    Gartenbewaesserung_StopPumpWatchdog($hash);

    # Mark as paused
    $hash->{HELPER}{pauseActive} = 1;
    $hash->{HELPER}{pauseStartTime} = time();

    # Clear valve end time, set pause end time
    Gartenbewaesserung_ClearEndTime($hash);
    Gartenbewaesserung_SetPauseEndTime($hash, $pauseDuration);
    Gartenbewaesserung_StartBarrelFillTimeout($hash);

    if(defined($hash->{HELPER}{valveRemainingTime}) && $hash->{HELPER}{valveRemainingTime} > 0) {
        my $rem = $hash->{HELPER}{valveRemainingTime};
        my $timeStr = $rem >= 1 ? sprintf("%d min", $rem) : "< 1 min";
        readingsSingleUpdate($hash, "remainingTime", "$timeStr (paused)", 1);
    }

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "state", "paused");
    readingsBulkUpdate($hash, "phase", "pause - refilling");
    readingsBulkUpdate($hash, "pauseActive", "yes");
    readingsEndUpdate($hash, 1);

    # Decide: Fill from IBC or water supply?
    my $ibcEmpty = ReadingsVal($name, "ibcEmpty", "no");

    if($ibcEmpty eq "yes") {
        # IBC is empty, use water supply (barrelFillValveDevice)
        Log3 $name, 3, "$name: IBC empty, using water supply to fill barrel";
        my $fillValve = AttrVal($name, "barrelFillValveDevice", "");
        if($fillValve ne "") {
            Gartenbewaesserung_SwitchDevice($name, $fillValve, "on");
            $hash->{HELPER}{pauseSource} = "water_supply";
            Log3 $name, 4, "$name: Opened water supply valve (barrelFillValveDevice)";
        }
    }
    else {
        # IBC has water, fill from IBC
        Log3 $name, 3, "$name: IBC has water, filling barrel from IBC";

        my $ibcToBarrelPump = AttrVal($name, "ibcToBarrelPumpDevice", "");
        my $ibcToBarrelValve = AttrVal($name, "ibcToBarrelValveDevice", "");

        if($ibcToBarrelPump ne "") {
            # Use pump
            Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelPump, "on");
            Log3 $name, 4, "$name: Started IBC to barrel pump";

            my $delay = AttrVal($name, "pumpStartDelay", 3);
            $delay = abs($delay);  # Use absolute value for pause pumping

            InternalTimer(gettimeofday() + $delay, sub {
                if($ibcToBarrelValve ne "") {
                    Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelValve, "on");
                    Log3 $name, 4, "$name: Opened IBC to barrel valve";
                }
            }, $hash);
        }
        else {
            # Gravity feed
            if($ibcToBarrelValve ne "") {
                Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelValve, "on");
                Log3 $name, 4, "$name: Opened IBC to barrel valve (gravity)";
            }
        }

        $hash->{HELPER}{pauseSource} = "ibc";
    }

    # Schedule pause end
    $hash->{HELPER}{pauseEndTimer} = gettimeofday() + ($pauseDuration * 60);
    InternalTimer($hash->{HELPER}{pauseEndTimer}, "Gartenbewaesserung_EndWateringPause", $hash);
}

##############################################################################
# End watering pause and resume
##############################################################################
sub Gartenbewaesserung_EndWateringPause {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    return if(!$hash->{HELPER}{pauseActive});

    Log3 $name, 3, "$name: Ending watering pause, resuming cycle";

    # Close fill valves
    my $pauseSource = $hash->{HELPER}{pauseSource} || "";

    if($pauseSource eq "water_supply") {
        my $fillValve = AttrVal($name, "barrelFillValveDevice", "");
        if($fillValve ne "") {
            Gartenbewaesserung_SwitchDevice($name, $fillValve, "off");
            Log3 $name, 4, "$name: Closed water supply valve";
        }
    }
    elsif($pauseSource eq "ibc") {
        my $ibcToBarrelValve = AttrVal($name, "ibcToBarrelValveDevice", "");
        if($ibcToBarrelValve ne "") {
            Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelValve, "off");
            Log3 $name, 4, "$name: Closed IBC to barrel valve";
        }

        my $ibcToBarrelPump = AttrVal($name, "ibcToBarrelPumpDevice", "");
        if($ibcToBarrelPump ne "") {
            Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelPump, "off");
            Log3 $name, 4, "$name: Stopped IBC to barrel pump";
        }
    }

    # Mark pause as ended
    $hash->{HELPER}{pauseActive} = 0;
    $hash->{HELPER}{lastPauseEnd} = time();
    delete $hash->{HELPER}{pausedValve};
    delete $hash->{HELPER}{pauseSource};
    delete $hash->{HELPER}{pauseStartTime};
    delete $hash->{HELPER}{pauseEndTimer};

    Gartenbewaesserung_StopBarrelFillTimeout($hash);

    # Reset barrel level
    readingsSingleUpdate($hash, "barrelLevel", Gartenbewaesserung_GetBarrelLevelAfterRefill($hash, 50), 1);

    Gartenbewaesserung_ClearPauseTime($hash);

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "state", "watering");
    readingsBulkUpdate($hash, "phase", "resuming");
    readingsBulkUpdate($hash, "pauseActive", "no");
    readingsEndUpdate($hash, 1);

    # Small delay, then continue with current or next valve
    InternalTimer(gettimeofday() + 2, sub {
        # Check if we have remaining time for current valve
        if(defined($hash->{HELPER}{valveRemainingTime}) && $hash->{HELPER}{valveRemainingTime} > 0) {
            # Resume current valve with remaining time
            my $queue = $hash->{HELPER}{wateringQueue};
            my $index = $hash->{HELPER}{wateringIndex};
            my $valveNum = $queue->[$index];

            Log3 $name, 3, "$name: Resuming valve $valveNum with remaining time";
            Gartenbewaesserung_OpenValve($hash, $valveNum);
        }
        else {
            # Move to next valve
            Log3 $name, 3, "$name: Moving to next valve after pause";
            Gartenbewaesserung_NextValve($hash);
        }

        my $pumpDevice = AttrVal($name, "pumpDevice", "");
        my $ibcToBarrelPump = AttrVal($name, "ibcToBarrelPumpDevice", "");
        if(Gartenbewaesserung_IsDeviceOn($name, $pumpDevice) ||
           Gartenbewaesserung_IsDeviceOn($name, $ibcToBarrelPump)) {
            Gartenbewaesserung_StartPumpWatchdog($hash);
        }
    }, $hash);
}

##############################################################################
# Process next valve in queue
##############################################################################
sub Gartenbewaesserung_NextValve {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    return if(!$hash->{HELPER}{watering});

    my $queue = $hash->{HELPER}{wateringQueue};
    my $index = $hash->{HELPER}{wateringIndex};

    # Check if we're done
    if($index >= scalar(@$queue)) {
        Gartenbewaesserung_FinishWatering($hash);
        return;
    }

    my $valveNum = $queue->[$index];
    my $valveDevice = AttrVal($name, "valve${valveNum}Device", "");

    if($valveDevice eq "") {
        Log3 $name, 2, "$name: Valve $valveNum has no device configured, skipping";
        $hash->{HELPER}{wateringIndex}++;
        Gartenbewaesserung_NextValve($hash);
        return;
    }

    # Check if barrel needs filling (initial check, not pause-based)
    my $barrelLevel = ReadingsVal($name, "barrelLevel", 100);
    my $threshold = AttrVal($name, "barrelFillThreshold", 30);

    if($barrelLevel < $threshold) {
        Log3 $name, 3, "$name: Barrel level low, filling before valve $valveNum";
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash, "phase", "filling barrel");
        readingsBulkUpdate($hash, "nextValve", $valveNum);
        readingsEndUpdate($hash, 1);

        Gartenbewaesserung_FillBarrel($hash);
        return;
    }

    # Start valve
    Gartenbewaesserung_OpenValve($hash, $valveNum);
}

##############################################################################
# Open specific valve
##############################################################################
sub Gartenbewaesserung_OpenValve {
    my ($hash, $valveNum) = @_;
    my $name = $hash->{NAME};

    my $valveDevice = AttrVal($name, "valve${valveNum}Device", "");
    my $duration = AttrVal($name, "valve${valveNum}Duration", 15);

    # Check if we have remaining time from a pause
    if(defined($hash->{HELPER}{valveRemainingTime}) && $hash->{HELPER}{valveRemainingTime} > 0) {
        $duration = $hash->{HELPER}{valveRemainingTime};
        delete $hash->{HELPER}{valveRemainingTime};
        Log3 $name, 4, "$name: Using remaining time: $duration minutes";
    }

    # Make sure IBC valve is closed during watering
    Gartenbewaesserung_StopIBCFill($hash);

    # Check if barrel is empty - do not run pump, but try to refill it first
    if(ReadingsVal($name, "barrelEmpty", "no") eq "yes") {
        Log3 $name, 3, "$name: Cannot open valve $valveNum - barrel is empty";
        my $refilling = Gartenbewaesserung_TriggerBarrelRefillIfPossible($hash);
        readingsSingleUpdate($hash, "state", "stopped - barrel empty", 1)
            if(!$refilling && !$hash->{HELPER}{noWaterAbort});
        return;
    }

    # Mark the start of actual watering (used by the no-water loop-breaker)
    $hash->{HELPER}{lastWateringStart} = time();

    # Check if pause is needed DURING this valve
    my $pauseInterval = AttrVal($name, "wateringPauseInterval", 8);
    if($pauseInterval > 0) {
        my $timeUntilPause = Gartenbewaesserung_TimeUntilNextPause($hash);

        if($timeUntilPause >= 0 && $timeUntilPause < $duration) {
            # Pause is needed DURING this valve
            Log3 $name, 4, "$name: Valve $valveNum: Will pause after $timeUntilPause minutes (valve duration: $duration min)";

            # Store remaining time for after pause
            $hash->{HELPER}{valveRemainingTime} = $duration - $timeUntilPause;

            # Open valve for partial time only
            $duration = $timeUntilPause;
            Log3 $name, 4, "$name: Valve $valveNum will run for $duration minutes until pause";
        }
    }

    # Get pump and delay
    my $pumpDevice = AttrVal($name, "pumpDevice", "");
    my $delay = AttrVal($name, "pumpStartDelay", 3);
    my $effectiveDelay = $delay;

    if($delay != 0 && ($duration * 60) <= abs($delay)) {
        $effectiveDelay = 0;
        Log3 $name, 4, "$name: Valve $valveNum duration too short for pumpStartDelay ($delay s), using simultaneous start";
    }

    if($pumpDevice ne "") {
        if($effectiveDelay < 0) {
            # Negative delay: Open valve FIRST, then pump
            Gartenbewaesserung_SwitchDevice($name, $valveDevice, "on");
            Log3 $name, 4, "$name: Valve $valveNum opened (negative delay)";

            InternalTimer(gettimeofday() + abs($effectiveDelay), sub {
                return if(!$hash->{HELPER}{watering} && !$hash->{HELPER}{circuitMode});
                my $currentValve = ReadingsVal($name, "currentValve", "none");
                return if($currentValve eq "none" || $currentValve ne $valveNum);
                Gartenbewaesserung_SwitchDevice($name, $pumpDevice, "on");
                Log3 $name, 4, "$name: Pump started after valve (negative delay)";
            }, $hash);
        }
        elsif($effectiveDelay > 0) {
            # Positive delay: Start pump FIRST, wait, then valve
            Gartenbewaesserung_SwitchDevice($name, $pumpDevice, "on");
            Log3 $name, 4, "$name: Pump started";

            InternalTimer(gettimeofday() + $effectiveDelay, sub {
                return if(!$hash->{HELPER}{watering} && !$hash->{HELPER}{circuitMode});
                my $currentValve = ReadingsVal($name, "currentValve", "none");
                return if($currentValve eq "none" || $currentValve ne $valveNum);
                Gartenbewaesserung_SwitchDevice($name, $valveDevice, "on");
                Log3 $name, 4, "$name: Valve $valveNum opened after pump delay";
            }, $hash);
        }
        else {
            # Zero delay: Simultaneous
            Gartenbewaesserung_SwitchDevice($name, $pumpDevice, "on");
            Gartenbewaesserung_SwitchDevice($name, $valveDevice, "on");
            Log3 $name, 4, "$name: Pump and valve $valveNum started simultaneously";
        }
    }
    else {
        Gartenbewaesserung_SwitchDevice($name, $valveDevice, "on");
    }

    # Set end time
    Gartenbewaesserung_SetEndTime($hash, $duration);

    my $index = $hash->{HELPER}{wateringIndex} + 1;
    my $total = $hash->{HELPER}{totalValves};

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "phase", "watering");
    readingsBulkUpdate($hash, "currentValve", $valveNum);
    readingsBulkUpdate($hash, "cycleProgress", "$index/$total");
    readingsEndUpdate($hash, 1);

    Log3 $name, 3, "$name: Valve $valveNum opened for $duration minutes ($index/$total)";

    # Schedule valve close
    $hash->{HELPER}{valveCloseTimer} = gettimeofday() + ($duration * 60);
    InternalTimer($hash->{HELPER}{valveCloseTimer}, sub {
        Gartenbewaesserung_CloseValve($hash, $valveNum);
    }, $hash);
}

##############################################################################
# Close specific valve
##############################################################################
sub Gartenbewaesserung_CloseValve {
    my ($hash, $valveNum) = @_;
    my $name = $hash->{NAME};

    my $valveDevice = AttrVal($name, "valve${valveNum}Device", "");
    Gartenbewaesserung_SwitchDevice($name, $valveDevice, "off");

    Log3 $name, 4, "$name: Valve $valveNum closed";

    delete $hash->{HELPER}{valveCloseTimer};
    Gartenbewaesserung_ClearEndTime($hash);

    readingsSingleUpdate($hash, "currentValve", "none", 1);

    # Turn off pump
    my $pumpDevice = AttrVal($name, "pumpDevice", "");
    if($pumpDevice ne "") {
        Gartenbewaesserung_SwitchDevice($name, $pumpDevice, "off");
    }

    # Decrease barrel level (simulated)
    my $currentLevel = ReadingsVal($name, "barrelLevel", 100);
    my $newLevel = $currentLevel - 12;  # Each valve uses about 12%
    $newLevel = 0 if($newLevel < 0);
    readingsSingleUpdate($hash, "barrelLevel", $newLevel, 1);

    # Check if we have remaining time (pause is needed)
    if(defined($hash->{HELPER}{valveRemainingTime}) && $hash->{HELPER}{valveRemainingTime} > 0) {
        Log3 $name, 4, "$name: Valve $valveNum has remaining time, starting pause";
        Gartenbewaesserung_StartWateringPause($hash);
        return;
    }

    # No remaining time, move to next valve
    $hash->{HELPER}{wateringIndex}++;
    InternalTimer(gettimeofday() + 2, sub {
        Gartenbewaesserung_NextValve($hash);
    }, $hash);
}

##############################################################################
# Fill barrel
##############################################################################
sub Gartenbewaesserung_FillBarrel {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    my $fillValve = AttrVal($name, "barrelFillValveDevice", "");
    if($fillValve eq "") {
        Log3 $name, 2, "$name: No barrel fill valve configured";
        Gartenbewaesserung_NextValve($hash);
        return;
    }

    Gartenbewaesserung_SwitchDevice($name, $fillValve, "on");
    $hash->{HELPER}{barrelFilling} = 1;
    Gartenbewaesserung_StartBarrelFillTimeout($hash);

    my $duration = AttrVal($name, "barrelFillDuration", 10);

    # Set end time
    Gartenbewaesserung_SetEndTime($hash, $duration);

    Log3 $name, 3, "$name: Filling barrel for $duration minutes";

    # Schedule fill stop
    InternalTimer(gettimeofday() + ($duration * 60), sub {
        Gartenbewaesserung_StopBarrelFill($hash);
    }, $hash);
}

##############################################################################
# Stop barrel filling
##############################################################################
sub Gartenbewaesserung_StopBarrelFill {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    my $fillValve = AttrVal($name, "barrelFillValveDevice", "");
    if($fillValve ne "") {
        Gartenbewaesserung_SwitchDevice($name, $fillValve, "off");
    }

    $hash->{HELPER}{barrelFilling} = 0;
    Gartenbewaesserung_StopBarrelFillTimeout($hash);
    readingsSingleUpdate($hash, "barrelLevel", Gartenbewaesserung_GetBarrelLevelAfterRefill($hash, 50), 1);

    Gartenbewaesserung_ClearEndTime($hash);

    Log3 $name, 4, "$name: Barrel filling stopped";

    # Continue with watering
    if($hash->{HELPER}{watering}) {
        InternalTimer(gettimeofday() + 2, sub {
            Gartenbewaesserung_NextValve($hash);
        }, $hash);
    }
}

##############################################################################
# Check if barrel is full (called by Notify when sensor triggers)
##############################################################################
sub Gartenbewaesserung_CheckBarrelFull {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    Log3 $name, 3, "$name: Barrel full detected";

    # Stop fill-timeout watchdog and clear any pending alert
    Gartenbewaesserung_StopBarrelFillTimeout($hash);
    if(ReadingsVal($name, "barrelFillTimeoutAlert", "no") ne "no") {
        readingsSingleUpdate($hash, "barrelFillTimeoutAlert", "no", 1);
    }

    # If IBC→Barrel transfer is active, stop the transfer and do NOT pump back
    if($hash->{HELPER}{ibcToBarrelActive}) {
        Log3 $name, 3, "$name: Barrel full during IBC-to-barrel transfer, stopping transfer";
        if($hash->{HELPER}{barrelEmptyRefilling}) {
            Gartenbewaesserung_StopBarrelEmptyRefill($hash);
        }
        else {
            Gartenbewaesserung_StopIBCtoBarrel($hash);
        }
        return;
    }

    # If filling barrel directly
    if($hash->{HELPER}{barrelFilling}) {
        Log3 $name, 3, "$name: Stopping barrel fill (sensor triggered)";
        if($hash->{HELPER}{barrelEmptyRefilling}) {
            Gartenbewaesserung_StopBarrelEmptyRefill($hash);
        }
        else {
            Gartenbewaesserung_StopBarrelFill($hash);
        }
    }

    # If pause is active (during watering cycle OR circuit mode)
    if($hash->{HELPER}{pauseActive}) {
        Log3 $name, 3, "$name: Barrel full during pause, closing valves and ending pause early";

        # Close fill valves immediately
        my $pauseSource = $hash->{HELPER}{pauseSource} || "";

        if($pauseSource eq "water_supply") {
            my $fillValve = AttrVal($name, "barrelFillValveDevice", "");
            if($fillValve ne "") {
                Gartenbewaesserung_SwitchDevice($name, $fillValve, "off");
                Log3 $name, 4, "$name: Closed water supply valve (barrel full)";
            }
        }
        elsif($pauseSource eq "ibc") {
            my $ibcToBarrelValve = AttrVal($name, "ibcToBarrelValveDevice", "");
            if($ibcToBarrelValve ne "") {
                Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelValve, "off");
                Log3 $name, 4, "$name: Closed IBC to barrel valve (barrel full)";
            }

            my $ibcToBarrelPump = AttrVal($name, "ibcToBarrelPumpDevice", "");
            if($ibcToBarrelPump ne "") {
                Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelPump, "off");
                Log3 $name, 4, "$name: Stopped IBC to barrel pump (barrel full)";
            }
        }

        # Cancel pause timer
        if(defined($hash->{HELPER}{pauseEndTimer})) {
            RemoveInternalTimer($hash, "Gartenbewaesserung_EndWateringPause");
            RemoveInternalTimer($hash, "Gartenbewaesserung_EndCircuitPauseTimer");
            delete $hash->{HELPER}{pauseEndTimer};
        }

        # End pause early - check if watering or circuit mode
        if($hash->{HELPER}{circuitMode}) {
            my $circuitNum = $hash->{HELPER}{pausedCircuit} || $hash->{HELPER}{circuitNumber};
            Gartenbewaesserung_EndCircuitPause($hash, $circuitNum);
        }
        else {
            Gartenbewaesserung_EndWateringPause($hash);
        }
    }
}

##############################################################################
# Handle barrel empty: stop pump and all active watering immediately
##############################################################################
sub Gartenbewaesserung_SaveBarrelEmptyResumeContext {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    my $mode = "";
    if($hash->{HELPER}{watering}) {
        $mode = "watering";
    }
    elsif($hash->{HELPER}{circuitMode}) {
        $mode = "circuit";
    }

    return 0 if($mode eq "");

    my $remainingMinutes;
    if(defined($hash->{HELPER}{valveRemainingTime}) && $hash->{HELPER}{valveRemainingTime} > 0) {
        $remainingMinutes = $hash->{HELPER}{valveRemainingTime};
    }
    elsif(defined($hash->{HELPER}{endTime})) {
        my $remainingSeconds = $hash->{HELPER}{endTime} - time();
        if($remainingSeconds > 0) {
            $remainingMinutes = $remainingSeconds / 60;
        }
    }

    my %context = (
        mode      => $mode,
        createdAt => time()
    );

    if(defined($remainingMinutes) && $remainingMinutes > 0) {
        $context{remainingMinutes} = $remainingMinutes;
    }

    if($mode eq "watering") {
        my $queueRef = $hash->{HELPER}{wateringQueue};
        my @queue = (defined($queueRef) && ref($queueRef) eq "ARRAY") ? @$queueRef : ();
        my $index = defined($hash->{HELPER}{wateringIndex}) ? $hash->{HELPER}{wateringIndex} : 0;

        if($index < 0) {
            $index = 0;
        }

        my $resumeValve = ReadingsVal($name, "currentValve", "none");
        if($resumeValve !~ /^\d+$/) {
            my $pausedValve = $hash->{HELPER}{pausedValve} || "";
            $resumeValve = $pausedValve if($pausedValve =~ /^\d+$/);
        }
        if($resumeValve !~ /^\d+$/ && $index < scalar(@queue)) {
            my $queuedValve = $queue[$index];
            $resumeValve = $queuedValve if(defined($queuedValve) && $queuedValve =~ /^\d+$/);
        }

        $context{queue} = \@queue;
        $context{index} = $index;
        $context{totalValves} = defined($hash->{HELPER}{totalValves}) ? $hash->{HELPER}{totalValves} : scalar(@queue);
        $context{wateringStartTime} = $hash->{HELPER}{wateringStartTime} if(defined($hash->{HELPER}{wateringStartTime}));
        $context{lastPauseEnd} = $hash->{HELPER}{lastPauseEnd} if(defined($hash->{HELPER}{lastPauseEnd}));
        $context{resumeValve} = $resumeValve if($resumeValve =~ /^\d+$/);
    }
    else {
        my $circuitNum = $hash->{HELPER}{circuitNumber};
        $circuitNum = $hash->{HELPER}{pausedCircuit} if(!defined($circuitNum));

        if(!defined($circuitNum) || $circuitNum !~ /^\d+$/) {
            Log3 $name, 2, "$name: Cannot store barrel-empty resume context for circuit mode (missing circuit number)";
            return 0;
        }

        $context{circuitNumber} = $circuitNum;
        $context{manualCircuit} = $hash->{HELPER}{manualCircuit} ? 1 : 0;
        $context{circuitStartTime} = $hash->{HELPER}{circuitStartTime} if(defined($hash->{HELPER}{circuitStartTime}));
        $context{lastPauseEnd} = $hash->{HELPER}{lastPauseEnd} if(defined($hash->{HELPER}{lastPauseEnd}));
    }

    $hash->{HELPER}{barrelEmptyResumePending} = 1;
    $hash->{HELPER}{barrelEmptyResumeContext} = \%context;

    Log3 $name, 3, "$name: Stored barrel-empty resume context ($mode)";
    return 1;
}

##############################################################################
sub Gartenbewaesserung_ClearBarrelEmptyResumeContext {
    my ($hash) = @_;

    delete $hash->{HELPER}{barrelEmptyResumePending};
    delete $hash->{HELPER}{barrelEmptyResumeContext};
}

##############################################################################
sub Gartenbewaesserung_ResumeAfterBarrelEmpty {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    return "none" if(!$hash->{HELPER}{barrelEmptyResumePending});

    my $context = $hash->{HELPER}{barrelEmptyResumeContext};
    if(!defined($context) || ref($context) ne "HASH") {
        Gartenbewaesserung_ClearBarrelEmptyResumeContext($hash);
        return "none";
    }

    if(ReadingsVal($name, "barrelEmpty", "no") eq "yes") {
        Log3 $name, 3, "$name: Resume blocked: barrelEmpty is still active";
        return "blocked";
    }

    my $mode = $context->{mode} || "";
    my $remainingMinutes = $context->{remainingMinutes};

    if($mode eq "watering") {
        my $queueRef = $context->{queue};
        if(!defined($queueRef) || ref($queueRef) ne "ARRAY" || scalar(@$queueRef) == 0) {
            Log3 $name, 2, "$name: Resume context for watering is incomplete, not resuming automatically";
            Gartenbewaesserung_ClearBarrelEmptyResumeContext($hash);
            return "none";
        }

        my @queue = @$queueRef;
        my $index = defined($context->{index}) ? $context->{index} : 0;
        $index = 0 if($index < 0);
        $index = scalar(@queue) if($index > scalar(@queue));

        $hash->{HELPER}{watering} = 1;
        $hash->{HELPER}{circuitMode} = 0;
        $hash->{HELPER}{wateringQueue} = \@queue;
        $hash->{HELPER}{wateringIndex} = $index;
        $hash->{HELPER}{totalValves} = defined($context->{totalValves}) ? $context->{totalValves} : scalar(@queue);
        $hash->{HELPER}{wateringStartTime} = defined($context->{wateringStartTime}) ? $context->{wateringStartTime} : time();

        if(defined($context->{lastPauseEnd})) {
            $hash->{HELPER}{lastPauseEnd} = $context->{lastPauseEnd};
        }
        else {
            delete $hash->{HELPER}{lastPauseEnd};
        }

        delete $hash->{HELPER}{manualCircuit};
        delete $hash->{HELPER}{circuitNumber};
        delete $hash->{HELPER}{circuitStartTime};
        delete $hash->{HELPER}{pausedValve};
        delete $hash->{HELPER}{pausedCircuit};
        delete $hash->{HELPER}{pauseSource};
        delete $hash->{HELPER}{pauseStartTime};
        delete $hash->{HELPER}{pauseEndTimer};
        delete $hash->{HELPER}{valveCloseTimer};
        $hash->{HELPER}{pauseActive} = 0;

        if(defined($remainingMinutes) && $remainingMinutes > 0) {
            $hash->{HELPER}{valveRemainingTime} = $remainingMinutes;
        }
        else {
            delete $hash->{HELPER}{valveRemainingTime};
        }

        Gartenbewaesserung_ClearPauseTime($hash);

        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash, "state", "watering");
        readingsBulkUpdate($hash, "phase", "resuming after barrel refill");
        readingsBulkUpdate($hash, "pauseActive", "no");
        readingsBulkUpdate($hash, "currentValve", "none");
        readingsEndUpdate($hash, 1);

        my $resumeValve = $context->{resumeValve};
        Gartenbewaesserung_ClearBarrelEmptyResumeContext($hash);

        if(defined($remainingMinutes) && $remainingMinutes > 0 && defined($resumeValve) && $resumeValve =~ /^\d+$/) {
            Log3 $name, 3, "$name: Resuming valve $resumeValve after barrel refill";
            InternalTimer(gettimeofday() + 2, sub {
                return if(!$hash->{HELPER}{watering});
                Gartenbewaesserung_OpenValve($hash, $resumeValve);
                my $pumpDevice = AttrVal($name, "pumpDevice", "");
                my $ibcToBarrelPump = AttrVal($name, "ibcToBarrelPumpDevice", "");
                if(Gartenbewaesserung_IsDeviceOn($name, $pumpDevice) ||
                   Gartenbewaesserung_IsDeviceOn($name, $ibcToBarrelPump)) {
                    Gartenbewaesserung_StartPumpWatchdog($hash);
                }
            }, $hash);
        }
        else {
            Log3 $name, 3, "$name: Continuing watering queue after barrel refill";
            InternalTimer(gettimeofday() + 2, sub {
                return if(!$hash->{HELPER}{watering});
                Gartenbewaesserung_NextValve($hash);
                my $pumpDevice = AttrVal($name, "pumpDevice", "");
                my $ibcToBarrelPump = AttrVal($name, "ibcToBarrelPumpDevice", "");
                if(Gartenbewaesserung_IsDeviceOn($name, $pumpDevice) ||
                   Gartenbewaesserung_IsDeviceOn($name, $ibcToBarrelPump)) {
                    Gartenbewaesserung_StartPumpWatchdog($hash);
                }
            }, $hash);
        }

        return "resumed";
    }
    elsif($mode eq "circuit") {
        my $circuitNum = $context->{circuitNumber};
        if(!defined($circuitNum) || $circuitNum !~ /^\d+$/) {
            Log3 $name, 2, "$name: Resume context for circuit mode is incomplete, not resuming automatically";
            Gartenbewaesserung_ClearBarrelEmptyResumeContext($hash);
            return "none";
        }

        $hash->{HELPER}{watering} = 0;
        $hash->{HELPER}{circuitMode} = 1;
        $hash->{HELPER}{circuitNumber} = $circuitNum;
        $hash->{HELPER}{manualCircuit} = $context->{manualCircuit} ? 1 : 0;
        $hash->{HELPER}{circuitStartTime} = defined($context->{circuitStartTime}) ? $context->{circuitStartTime} : time();

        if(defined($context->{lastPauseEnd})) {
            $hash->{HELPER}{lastPauseEnd} = $context->{lastPauseEnd};
        }
        else {
            delete $hash->{HELPER}{lastPauseEnd};
        }

        delete $hash->{HELPER}{wateringQueue};
        delete $hash->{HELPER}{wateringIndex};
        delete $hash->{HELPER}{totalValves};
        delete $hash->{HELPER}{pausedValve};
        delete $hash->{HELPER}{pausedCircuit};
        delete $hash->{HELPER}{pauseSource};
        delete $hash->{HELPER}{pauseStartTime};
        delete $hash->{HELPER}{pauseEndTimer};
        delete $hash->{HELPER}{valveCloseTimer};
        $hash->{HELPER}{pauseActive} = 0;

        if(defined($remainingMinutes) && $remainingMinutes > 0) {
            $hash->{HELPER}{valveRemainingTime} = $remainingMinutes;
        }
        else {
            delete $hash->{HELPER}{valveRemainingTime};
        }

        Gartenbewaesserung_ClearPauseTime($hash);

        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash, "state", "circuit mode");
        readingsBulkUpdate($hash, "phase", "resuming circuit $circuitNum after barrel refill");
        readingsBulkUpdate($hash, "pauseActive", "no");
        readingsBulkUpdate($hash, "cycleProgress", "1/1");
        readingsBulkUpdate($hash, "currentValve", "none");
        readingsEndUpdate($hash, 1);

        Gartenbewaesserung_ClearBarrelEmptyResumeContext($hash);

        Log3 $name, 3, "$name: Resuming circuit $circuitNum after barrel refill";
        InternalTimer(gettimeofday() + 2, sub {
            return if(!$hash->{HELPER}{circuitMode});
            Gartenbewaesserung_RunCircuit($hash, $circuitNum);
            my $pumpDevice = AttrVal($name, "pumpDevice", "");
            my $ibcToBarrelPump = AttrVal($name, "ibcToBarrelPumpDevice", "");
            if(Gartenbewaesserung_IsDeviceOn($name, $pumpDevice) ||
               Gartenbewaesserung_IsDeviceOn($name, $ibcToBarrelPump)) {
                Gartenbewaesserung_StartPumpWatchdog($hash);
            }
        }, $hash);

        return "resumed";
    }

    Gartenbewaesserung_ClearBarrelEmptyResumeContext($hash);
    return "none";
}

##############################################################################
# Start refill pause after barrel-empty condition cleared
##############################################################################
sub Gartenbewaesserung_StartBarrelEmptyRefillPause {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    return if($hash->{HELPER}{barrelEmptyRefillPause});

    my $pauseDuration = AttrVal($name, "wateringPauseDuration", 20);

    Log3 $name, 3, "$name: Starting barrel refill pause ($pauseDuration min) after barrel-empty event";

    $hash->{HELPER}{barrelEmptyRefillPause} = 1;

    Gartenbewaesserung_StopPumpWatchdog($hash);
    Gartenbewaesserung_StartBarrelFillTimeout($hash);

    my $ibcEmpty = ReadingsVal($name, "ibcEmpty", "no");

    if($ibcEmpty ne "yes") {
        my $ibcToBarrelPump = AttrVal($name, "ibcToBarrelPumpDevice", "");
        my $ibcToBarrelValve = AttrVal($name, "ibcToBarrelValveDevice", "");

        if($ibcToBarrelPump ne "") {
            Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelPump, "on");
            my $delay = abs(AttrVal($name, "pumpStartDelay", 3));
            InternalTimer(gettimeofday() + $delay, sub {
                if($hash->{HELPER}{barrelEmptyRefillPause} && $ibcToBarrelValve ne "") {
                    Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelValve, "on");
                }
            }, $hash);
        }
        elsif($ibcToBarrelValve ne "") {
            Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelValve, "on");
        }

        $hash->{HELPER}{barrelEmptyRefillPauseSource} = "ibc";
        Log3 $name, 3, "$name: Refill pause: using IBC as source";
    }
    else {
        my $fillValve = AttrVal($name, "barrelFillValveDevice", "");
        if($fillValve ne "") {
            Gartenbewaesserung_SwitchDevice($name, $fillValve, "on");
        }

        $hash->{HELPER}{barrelEmptyRefillPauseSource} = "water_supply";
        Log3 $name, 3, "$name: Refill pause: using water supply as source";
    }

    InternalTimer(gettimeofday() + ($pauseDuration * 60),
        "Gartenbewaesserung_EndBarrelEmptyRefillPause", $hash);
}

##############################################################################
# Stop refill pause after barrel-empty condition cleared
##############################################################################
sub Gartenbewaesserung_StopBarrelEmptyRefillPause {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    return if(!$hash->{HELPER}{barrelEmptyRefillPause});

    RemoveInternalTimer($hash, "Gartenbewaesserung_EndBarrelEmptyRefillPause");

    my $source = $hash->{HELPER}{barrelEmptyRefillPauseSource} || "";

    if($source eq "ibc") {
        my $ibcToBarrelValve = AttrVal($name, "ibcToBarrelValveDevice", "");
        Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelValve, "off") if($ibcToBarrelValve ne "");

        my $ibcToBarrelPump = AttrVal($name, "ibcToBarrelPumpDevice", "");
        Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelPump, "off") if($ibcToBarrelPump ne "");
    }
    elsif($source eq "water_supply") {
        my $fillValve = AttrVal($name, "barrelFillValveDevice", "");
        Gartenbewaesserung_SwitchDevice($name, $fillValve, "off") if($fillValve ne "");
    }

    Gartenbewaesserung_StopPumpWatchdog($hash);
    Gartenbewaesserung_StopBarrelFillTimeout($hash);

    readingsSingleUpdate($hash, "barrelLevel", Gartenbewaesserung_GetBarrelLevelAfterRefill($hash, 50), 1);

    delete $hash->{HELPER}{barrelEmptyRefillPause};
    delete $hash->{HELPER}{barrelEmptyRefillPauseSource};

    Log3 $name, 3, "$name: Barrel empty refill pause stopped";
}

##############################################################################
# End refill pause after barrel-empty condition cleared
##############################################################################
sub Gartenbewaesserung_EndBarrelEmptyRefillPause {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    return if(!$hash->{HELPER}{barrelEmptyRefillPause});

    Log3 $name, 3, "$name: Barrel empty refill pause ended (timer), resuming operation";
    Gartenbewaesserung_StopBarrelEmptyRefillPause($hash);

    if($hash->{HELPER}{barrelEmptyResumePending}) {
        Gartenbewaesserung_ResumeAfterBarrelEmpty($hash);
    }
}

##############################################################################
# Trigger an automatic barrel refill when a watering/circuit request hits an
# empty barrel. Without this, such a request would only abort (return) and the
# barrel would never be refilled until the barrel-empty sensor toggles again -
# i.e. the system could stay stuck in "stopped - barrel empty" indefinitely
# even though the IBC still has water. Reuses HandleBarrelEmpty, which saves the
# resume context and continues the interrupted operation once the barrel is full.
# Returns 1 if a refill was (or already is) running, 0 otherwise.
##############################################################################
sub Gartenbewaesserung_TriggerBarrelRefillIfPossible {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    # A refill is already running - let it finish, do not restart it.
    return 1 if($hash->{HELPER}{barrelEmptyRefilling});

    Log3 $name, 3, "$name: Barrel empty on watering request - triggering automatic refill";
    Gartenbewaesserung_HandleBarrelEmpty($hash);

    return $hash->{HELPER}{barrelEmptyRefilling} ? 1 : 0;
}

##############################################################################
# Abort watering/circuit when the barrel cannot be refilled (no water source).
# Stops everything, keeps the resume context, and waits for water to return
# (handled by RecoverFromNoWater). Prevents endless refill<->drain cycling.
##############################################################################
sub Gartenbewaesserung_AbortNoWater {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    Log3 $name, 1, "$name: WARNUNG - Fass bleibt trotz wiederholtem Nachfuellen leer " .
        "(IBC leer oder Wasserzufuhr gestoert). Bewaesserung abgebrochen, warte auf Wasser.";

    # Remember what we were doing so we can auto-resume once water returns
    Gartenbewaesserung_SaveBarrelEmptyResumeContext($hash);

    Gartenbewaesserung_StopAll($hash, { preserveBarrelEmptyResume => 1 });

    $hash->{HELPER}{noWaterAbort} = 1;

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "state", "stopped - no water");
    readingsBulkUpdate($hash, "phase", "waiting for water");
    readingsBulkUpdate($hash, "barrelFillTimeoutAlert", "yes");
    readingsEndUpdate($hash, 1);
}

##############################################################################
# Recover from a no-water abort once a water source reports water again
# (barrel full, IBC no longer empty, or rain). Resumes the saved operation.
# No-op unless a no-water abort is currently active.
##############################################################################
sub Gartenbewaesserung_RecoverFromNoWater {
    my ($hash, $barrelFull) = @_;
    my $name = $hash->{NAME};

    return if(!$hash->{HELPER}{noWaterAbort});

    Log3 $name, 3, "$name: Water source available again - clearing no-water abort";
    delete $hash->{HELPER}{noWaterAbort};
    $hash->{HELPER}{barrelEmptyRefillAttempts} = 0;
    delete $hash->{HELPER}{lastWateringStart};

    if(ReadingsVal($name, "barrelFillTimeoutAlert", "no") ne "no") {
        readingsSingleUpdate($hash, "barrelFillTimeoutAlert", "no", 1);
    }

    return if(!$hash->{HELPER}{barrelEmptyResumePending});

    if($barrelFull || ReadingsVal($name, "barrelEmpty", "no") ne "yes") {
        # Barrel already holds water -> resume the interrupted operation directly
        readingsSingleUpdate($hash, "barrelEmpty", "no", 1) if($barrelFull);
        Gartenbewaesserung_ResumeAfterBarrelEmpty($hash);
    }
    else {
        # Source has water but barrel is still empty -> start one refill,
        # which resumes the operation once the barrel is full again
        Gartenbewaesserung_HandleBarrelEmpty($hash);
    }
}

##############################################################################
# Handle barrel empty: stop pump and all active watering immediately
##############################################################################
sub Gartenbewaesserung_HandleBarrelEmpty {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    if($hash->{HELPER}{barrelEmptyRefilling}) {
        Log3 $name, 4, "$name: Barrel empty refill is already active";
        return;
    }

    # Stop pump immediately
    my $pumpDevice = AttrVal($name, "pumpDevice", "");
    if($pumpDevice ne "") {
        Gartenbewaesserung_SwitchDevice($name, $pumpDevice, "off");
        Log3 $name, 3, "$name: Pump switched off (barrel empty)";
    }

    # Stop the pump-runtime watchdog explicitly. SwitchDevice only stops it when
    # IsDeviceOn() already reports the pump as off, but the device reading is often
    # still stale right after the MQTT "off" command - which would leave a stray
    # PumpOverrun timer running and trigger a false pumpOverrunAlert minutes later.
    Gartenbewaesserung_StopPumpWatchdog($hash);

    # Stop IBC filling if active (pump was running barrel→IBC and emptied the barrel).
    # In this case we must NOT auto-refill the barrel: the barrel ran empty because
    # we deliberately pumped its (rain)water into the IBC. Refilling from the IBC
    # would immediately pump the water back (barrel<->IBC oscillation), and topping
    # up from city water right after rain wastes water. The barrel refills from rain
    # on its own; CheckRain resumes IBC filling once barrelFull reports full again.
    if($hash->{HELPER}{ibcFilling}) {
        Log3 $name, 3, "$name: Stopping IBC fill (barrel was emptied during IBC fill)";
        Gartenbewaesserung_StopIBCFill($hash);
        Log3 $name, 3, "$name: Barrel emptied by IBC fill - skipping automatic refill (avoids barrel<->IBC oscillation)";
        readingsSingleUpdate($hash, "state", "idle", 1);
        return;
    }

    # Loop-breaker: if the barrel keeps running empty within seconds of resuming,
    # the configured water source cannot actually refill it (e.g. IBC empty and no
    # mains fallback). Abort after a few unproductive attempts instead of cycling
    # the pump forever; auto-recovers once a water source reports water again.
    my $maxAttempts = AttrVal($name, "barrelEmptyMaxRefillAttempts", 3);
    if($maxAttempts > 0 && ($hash->{HELPER}{watering} || $hash->{HELPER}{circuitMode})) {
        my $unproductive = (defined($hash->{HELPER}{lastWateringStart})
            && (time() - $hash->{HELPER}{lastWateringStart}) < 60) ? 1 : 0;

        if($unproductive) {
            $hash->{HELPER}{barrelEmptyRefillAttempts} =
                ($hash->{HELPER}{barrelEmptyRefillAttempts} || 0) + 1;
            Log3 $name, 3, "$name: Barrel ran empty again within seconds of resuming " .
                "(attempt $hash->{HELPER}{barrelEmptyRefillAttempts}/$maxAttempts)";
        }
        else {
            # Barrel held water long enough for real watering -> refills are working
            $hash->{HELPER}{barrelEmptyRefillAttempts} = 0;
        }

        if($hash->{HELPER}{barrelEmptyRefillAttempts} >= $maxAttempts) {
            Gartenbewaesserung_AbortNoWater($hash);
            return;
        }
    }

    # If watering or circuit mode is active, stop all operations
    if($hash->{HELPER}{watering} || $hash->{HELPER}{circuitMode}) {
        Gartenbewaesserung_SaveBarrelEmptyResumeContext($hash);
        Log3 $name, 3, "$name: Stopping watering/circuit because barrel is empty";
        Gartenbewaesserung_StopAll($hash, { preserveBarrelEmptyResume => 1 });
        readingsSingleUpdate($hash, "state", "stopped - barrel empty", 1);
    }

    # Start automatic refilling of the barrel
    Log3 $name, 3, "$name: Barrel empty - starting automatic refill";
    my $ibcEmpty = ReadingsVal($name, "ibcEmpty", "no");

    if($ibcEmpty eq "yes") {
        # IBC is empty, use water supply (barrelFillValveDevice)
        my $fillValve = AttrVal($name, "barrelFillValveDevice", "");
        if($fillValve ne "") {
            Log3 $name, 3, "$name: IBC empty, using water supply to refill barrel";
            Gartenbewaesserung_SwitchDevice($name, $fillValve, "on");
            $hash->{HELPER}{barrelEmptyRefilling} = 1;
            $hash->{HELPER}{barrelEmptyRefillSource} = "water_supply";
            $hash->{HELPER}{barrelFilling} = 1;

            my $duration = AttrVal($name, "barrelFillDuration", 10);
            InternalTimer(gettimeofday() + ($duration * 60), sub {
                Gartenbewaesserung_StopBarrelEmptyRefill($hash);
            }, $hash);

            readingsSingleUpdate($hash, "state", "stopped - barrel empty - refilling", 1);
            Log3 $name, 4, "$name: Opened water supply valve for barrel empty refill ($duration min)";
        }
        else {
            Log3 $name, 3, "$name: No fill valve configured (barrelFillValveDevice), cannot refill barrel";
        }
    }
    else {
        # IBC has water, fill from IBC (ibcToBarrelValveDevice)
        my $ibcToBarrelValve = AttrVal($name, "ibcToBarrelValveDevice", "");
        if($ibcToBarrelValve ne "") {
            Log3 $name, 3, "$name: IBC has water, refilling barrel from IBC";
            my $ibcToBarrelPump = AttrVal($name, "ibcToBarrelPumpDevice", "");

            $hash->{HELPER}{barrelEmptyRefilling} = 1;
            $hash->{HELPER}{barrelEmptyRefillSource} = "ibc";
            $hash->{HELPER}{ibcToBarrelActive} = 1;

            if($ibcToBarrelPump ne "") {
                Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelPump, "on");
                Log3 $name, 4, "$name: Started IBC to barrel pump (barrel empty refill)";

                my $delay = AttrVal($name, "pumpStartDelay", 3);
                $delay = abs($delay);

                InternalTimer(gettimeofday() + $delay, sub {
                    Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelValve, "on");
                    Log3 $name, 4, "$name: Opened IBC to barrel valve (barrel empty refill)";
                }, $hash);
            }
            else {
                Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelValve, "on");
                Log3 $name, 4, "$name: Opened IBC to barrel valve (barrel empty refill, gravity)";
            }

            my $duration = AttrVal($name, "ibcToBarrelDuration", 15);
            InternalTimer(gettimeofday() + ($duration * 60), sub {
                Gartenbewaesserung_StopBarrelEmptyRefill($hash);
            }, $hash);

            readingsSingleUpdate($hash, "state", "stopped - barrel empty - refilling", 1);
            Log3 $name, 4, "$name: IBC to barrel transfer started for barrel empty refill ($duration min)";
        }
        else {
            Log3 $name, 3, "$name: No IBC to barrel valve configured (ibcToBarrelValveDevice), cannot refill barrel";
        }
    }
}

##############################################################################
# Stop barrel empty refill (called by timer, barrel-full sensor, or barrel-empty-inactive sensor)
##############################################################################
sub Gartenbewaesserung_StopBarrelEmptyRefill {
    my ($hash, $options) = @_;
    my $name = $hash->{NAME};

    $options = {} if(!defined($options) || ref($options) ne "HASH");

    return if(!$hash->{HELPER}{barrelEmptyRefilling});

    Log3 $name, 3, "$name: Stopping barrel empty refill";

    my $source = $hash->{HELPER}{barrelEmptyRefillSource} || "";

    if($source eq "ibc") {
        my $ibcToBarrelValve = AttrVal($name, "ibcToBarrelValveDevice", "");
        if($ibcToBarrelValve ne "") {
            Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelValve, "off");
        }
        my $ibcToBarrelPump = AttrVal($name, "ibcToBarrelPumpDevice", "");
        if($ibcToBarrelPump ne "") {
            Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelPump, "off");
        }
        $hash->{HELPER}{ibcToBarrelActive} = 0;
    }
    elsif($source eq "water_supply") {
        my $fillValve = AttrVal($name, "barrelFillValveDevice", "");
        if($fillValve ne "") {
            Gartenbewaesserung_SwitchDevice($name, $fillValve, "off");
        }
        $hash->{HELPER}{barrelFilling} = 0;
    }

    delete $hash->{HELPER}{barrelEmptyRefilling};
    delete $hash->{HELPER}{barrelEmptyRefillSource};

    Gartenbewaesserung_ClearEndTime($hash);

    my $barrelLevel = Gartenbewaesserung_GetBarrelLevelAfterRefill($hash, 50);

    if($options->{skipResume}) {
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash, "barrelLevel", $barrelLevel);
        if($source eq "ibc") {
            readingsBulkUpdate($hash, "ibcToBarrelActive", "no");
        }
        readingsBulkUpdate($hash, "state", "stopped - barrel empty");
        readingsBulkUpdate($hash, "phase", "waiting for barrel refill");
        readingsEndUpdate($hash, 1);
        Log3 $name, 3, "$name: Barrel empty refill stopped, waiting for refill pause before resume";
        return;
    }

    my $resumeStatus = Gartenbewaesserung_ResumeAfterBarrelEmpty($hash);

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "barrelLevel", $barrelLevel);
    if($source eq "ibc") {
        readingsBulkUpdate($hash, "ibcToBarrelActive", "no");
    }

    if($resumeStatus eq "resumed") {
        readingsEndUpdate($hash, 1);
        Log3 $name, 3, "$name: Barrel empty refill stopped, interrupted operation resumed";
        return;
    }

    if($resumeStatus eq "blocked") {
        readingsBulkUpdate($hash, "state", "stopped - barrel empty");
        readingsBulkUpdate($hash, "phase", "waiting for barrel refill");
        readingsBulkUpdate($hash, "pauseActive", "no");
        readingsEndUpdate($hash, 1);
        Log3 $name, 3, "$name: Barrel empty refill stopped, resume is blocked while barrelEmpty stays active";
        return;
    }

    readingsBulkUpdate($hash, "state", "idle");
    readingsBulkUpdate($hash, "phase", "idle");
    readingsEndUpdate($hash, 1);

    Log3 $name, 3, "$name: Barrel empty refill stopped, state set to idle";
}

##############################################################################
# Finish watering cycle
##############################################################################
sub Gartenbewaesserung_FinishWatering {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    # Turn off pump
    my $pumpDevice = AttrVal($name, "pumpDevice", "");
    if($pumpDevice ne "") {
        Gartenbewaesserung_SwitchDevice($name, $pumpDevice, "off");
    }

    $hash->{HELPER}{watering} = 0;
    delete $hash->{HELPER}{wateringQueue};
    delete $hash->{HELPER}{wateringIndex};
    delete $hash->{HELPER}{wateringStartTime};
    delete $hash->{HELPER}{lastPauseEnd};
    delete $hash->{HELPER}{valveRemainingTime};
    delete $hash->{HELPER}{pausedValve};
    delete $hash->{HELPER}{valveCloseTimer};

    # Cycle completed normally -> reset the no-water loop-breaker state
    $hash->{HELPER}{barrelEmptyRefillAttempts} = 0;
    delete $hash->{HELPER}{lastWateringStart};
    delete $hash->{HELPER}{noWaterAbort};

    Gartenbewaesserung_ClearEndTime($hash);
    Gartenbewaesserung_ClearPauseTime($hash);

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "state", "idle");
    readingsBulkUpdate($hash, "phase", "idle");
    readingsBulkUpdate($hash, "currentValve", "none");
    readingsBulkUpdate($hash, "pauseActive", "no");
    readingsBulkUpdate($hash, "lastWatering", TimeNow());
    readingsEndUpdate($hash, 1);

    Log3 $name, 3, "$name: Watering cycle finished";
}

##############################################################################
# Stop everything
##############################################################################
sub Gartenbewaesserung_StopAll {
    my ($hash, $opts) = @_;
    my $name = $hash->{NAME};
    my $preserveBarrelEmptyResume = (defined($opts) && ref($opts) eq "HASH" && $opts->{preserveBarrelEmptyResume}) ? 1 : 0;

    Gartenbewaesserung_StopPumpWatchdog($hash);
    Gartenbewaesserung_StopBarrelFillTimeout($hash);
    RemoveInternalTimer($hash);

    # Close all valves
    for(my $i = 1; $i <= 8; $i++) {
        my $valveDevice = AttrVal($name, "valve${i}Device", "");
        if($valveDevice ne "") {
            Gartenbewaesserung_SwitchDevice($name, $valveDevice, "off");
        }
    }

    # Turn off pumps
    my $pumpDevice = AttrVal($name, "pumpDevice", "");
    if($pumpDevice ne "") {
        Gartenbewaesserung_SwitchDevice($name, $pumpDevice, "off");
    }

    my $ibcToBarrelPump = AttrVal($name, "ibcToBarrelPumpDevice", "");
    if($ibcToBarrelPump ne "") {
        Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelPump, "off");
    }

    # Close barrel fill
    my $barrelFillValve = AttrVal($name, "barrelFillValveDevice", "");
    if($barrelFillValve ne "") {
        Gartenbewaesserung_SwitchDevice($name, $barrelFillValve, "off");
    }

    # Close IBC valves
    my $ibcFillValve = AttrVal($name, "ibcFillValveDevice", "");
    if($ibcFillValve ne "") {
        Gartenbewaesserung_SwitchDevice($name, $ibcFillValve, "off");
    }

    my $ibcToBarrelValve = AttrVal($name, "ibcToBarrelValveDevice", "");
    if($ibcToBarrelValve ne "") {
        Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelValve, "off");
    }

    $hash->{HELPER}{watering} = 0;
    $hash->{HELPER}{barrelFilling} = 0;
    $hash->{HELPER}{circuitMode} = 0;
    $hash->{HELPER}{pauseActive} = 0;
    $hash->{HELPER}{ibcFilling} = 0;
    $hash->{HELPER}{ibcToBarrelActive} = 0;
    delete $hash->{HELPER}{barrelEmptyRefilling};
    delete $hash->{HELPER}{barrelEmptyRefillSource};
    delete $hash->{HELPER}{manualCircuit};
    delete $hash->{HELPER}{wateringQueue};
    delete $hash->{HELPER}{wateringIndex};
    delete $hash->{HELPER}{circuitNumber};
    delete $hash->{HELPER}{wateringStartTime};
    delete $hash->{HELPER}{circuitStartTime};
    delete $hash->{HELPER}{lastPauseEnd};
    delete $hash->{HELPER}{valveRemainingTime};
    delete $hash->{HELPER}{pausedValve};
    delete $hash->{HELPER}{pausedCircuit};
    delete $hash->{HELPER}{pauseSource};
    delete $hash->{HELPER}{pauseStartTime};
    delete $hash->{HELPER}{pauseEndTimer};
    delete $hash->{HELPER}{valveCloseTimer};

    Gartenbewaesserung_ClearEndTime($hash);
    Gartenbewaesserung_ClearPauseTime($hash);

    if(!$preserveBarrelEmptyResume) {
        Gartenbewaesserung_ClearBarrelEmptyResumeContext($hash);
    }

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "state", "stopped");
    readingsBulkUpdate($hash, "phase", "idle");
    readingsBulkUpdate($hash, "currentValve", "none");
    readingsBulkUpdate($hash, "pauseActive", "no");
    readingsEndUpdate($hash, 1);

    Log3 $name, 3, "$name: All operations stopped";

    # Restart timers
    InternalTimer(gettimeofday() + 60, "Gartenbewaesserung_CheckSchedule", $hash);
    InternalTimer(gettimeofday() + 30, "Gartenbewaesserung_CheckRain", $hash);

    return undef;
}

##############################################################################
# Start single valve (manual mode - simple on/off)
##############################################################################
sub Gartenbewaesserung_StartSingleValve {
    my ($hash, $valveNum) = @_;
    my $name = $hash->{NAME};

    my $valveDevice = AttrVal($name, "valve${valveNum}Device", "");
    if($valveDevice eq "") {
        return "Valve $valveNum has no device configured";
    }

    # Make sure IBC fill is stopped
    Gartenbewaesserung_StopIBCFill($hash);
    Gartenbewaesserung_StopIBCtoBarrel($hash);

    # Check if barrel is empty - do not run pump
    if(ReadingsVal($name, "barrelEmpty", "no") eq "yes") {
        return "Barrel is empty - pump cannot be started";
    }

    # Start pump
    my $pumpDevice = AttrVal($name, "pumpDevice", "");
    if($pumpDevice ne "") {
        Gartenbewaesserung_SwitchDevice($name, $pumpDevice, "on");
        Gartenbewaesserung_StartPumpWatchdog($hash);
    }

    Gartenbewaesserung_SwitchDevice($name, $valveDevice, "on");

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "state", "manual");
    readingsBulkUpdate($hash, "phase", "manual watering");
    readingsBulkUpdate($hash, "currentValve", $valveNum);
    readingsEndUpdate($hash, 1);

    Log3 $name, 3, "$name: Manual valve $valveNum started";

    return undef;
}

##############################################################################
# Stop current valve
##############################################################################
sub Gartenbewaesserung_StopCurrentValve {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    my $currentValve = ReadingsVal($name, "currentValve", "none");
    if($currentValve ne "none") {
        my $valveDevice = AttrVal($name, "valve${currentValve}Device", "");
        if($valveDevice ne "") {
            Gartenbewaesserung_SwitchDevice($name, $valveDevice, "off");
        }
    }

    # Turn off pump
    my $pumpDevice = AttrVal($name, "pumpDevice", "");
    if($pumpDevice ne "") {
        Gartenbewaesserung_SwitchDevice($name, $pumpDevice, "off");
    }

    Gartenbewaesserung_StopPumpWatchdog($hash);
    Gartenbewaesserung_ClearEndTime($hash);

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "state", "idle");
    readingsBulkUpdate($hash, "phase", "idle");
    readingsBulkUpdate($hash, "currentValve", "none");
    readingsEndUpdate($hash, 1);

    return undef;
}

##############################################################################
# Start IBC filling (from barrel with pump)
##############################################################################
sub Gartenbewaesserung_StartIBCFill {
    my ($hash, $manual) = @_;
    my $name = $hash->{NAME};

    # Don't start if watering is active
    if($hash->{HELPER}{watering} || $hash->{HELPER}{circuitMode}) {
        Log3 $name, 3, "$name: Cannot start IBC fill during watering";
        return "Cannot start IBC fill during watering" if($manual);
        return;
    }

    # Don't start if IBC→Barrel transfer is running (would pump water in wrong direction)
    if($hash->{HELPER}{ibcToBarrelActive}) {
        Log3 $name, 3, "$name: Cannot fill IBC while IBC-to-barrel transfer is active";
        return "Cannot fill IBC while IBC-to-barrel transfer is active" if($manual);
        return;
    }

    # Check if IBC is already full
    if(ReadingsVal($name, "ibcFull", "no") eq "yes") {
        Log3 $name, 3, "$name: IBC already full";
        return "IBC already full" if($manual);
        return;
    }

    # Don't pump from an empty barrel (would dry-run the pump). The sensor-based
    # triggers already require barrelFull, but the time-based fallback and the
    # manual command could otherwise start filling with an empty barrel.
    if(ReadingsVal($name, "barrelEmpty", "no") eq "yes") {
        Log3 $name, 3, "$name: Cannot fill IBC - barrel is empty";
        return "Cannot fill IBC - barrel is empty" if($manual);
        return;
    }

    my $ibcValve = AttrVal($name, "ibcFillValveDevice", "");
    if($ibcValve eq "") {
        return "No IBC fill valve configured" if($manual);
        return;
    }

    # Start pump to move water from barrel to IBC
    my $pumpDevice = AttrVal($name, "pumpDevice", "");
    if($pumpDevice ne "") {
        Gartenbewaesserung_SwitchDevice($name, $pumpDevice, "on");
        Log3 $name, 4, "$name: Pump started for IBC filling";

        # Wait for pump, then open valve
        my $delay = AttrVal($name, "pumpStartDelay", 3);
        $delay = abs($delay);  # Use absolute value

        InternalTimer(gettimeofday() + $delay, sub {
            Gartenbewaesserung_SwitchDevice($name, $ibcValve, "on");
            $hash->{HELPER}{ibcFilling} = 1;

            readingsBeginUpdate($hash);
            readingsBulkUpdate($hash, "ibcFilling", "yes");
            readingsBulkUpdate($hash, "ibcFillStarted", TimeNow());
            readingsEndUpdate($hash, 1);

            Log3 $name, 3, "$name: IBC filling started (from barrel with pump)";
        }, $hash);
    }
    else {
        # No pump - just open valve (gravity feed from rain)
        Gartenbewaesserung_SwitchDevice($name, $ibcValve, "on");
        $hash->{HELPER}{ibcFilling} = 1;

        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash, "ibcFilling", "yes");
        readingsBulkUpdate($hash, "ibcFillStarted", TimeNow());
        readingsEndUpdate($hash, 1);

        Log3 $name, 3, "$name: IBC filling started (gravity feed)";
    }

    return undef;
}

##############################################################################
# Stop IBC filling
##############################################################################
sub Gartenbewaesserung_StopIBCFill {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    return if(!$hash->{HELPER}{ibcFilling});

    my $ibcValve = AttrVal($name, "ibcFillValveDevice", "");
    if($ibcValve ne "") {
        Gartenbewaesserung_SwitchDevice($name, $ibcValve, "off");
    }

    # Turn off pump
    my $pumpDevice = AttrVal($name, "pumpDevice", "");
    if($pumpDevice ne "") {
        Gartenbewaesserung_SwitchDevice($name, $pumpDevice, "off");
        Log3 $name, 4, "$name: Pump stopped (IBC filling)";
    }

    $hash->{HELPER}{ibcFilling} = 0;

    readingsSingleUpdate($hash, "ibcFilling", "no", 1);

    Log3 $name, 3, "$name: IBC filling stopped";

    return undef;
}

##############################################################################
# Check if IBC is full
##############################################################################
sub Gartenbewaesserung_CheckIBCFull {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    if($hash->{HELPER}{ibcFilling}) {
        Log3 $name, 3, "$name: IBC full detected, stopping fill";
        Gartenbewaesserung_StopIBCFill($hash);
    }
}

##############################################################################
# Start IBC to Barrel (return water from IBC to barrel)
##############################################################################
sub Gartenbewaesserung_StartIBCtoBarrel {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    # Don't start if watering is active
    if($hash->{HELPER}{watering} || $hash->{HELPER}{circuitMode}) {
        Log3 $name, 3, "$name: Cannot start IBC to barrel during watering";
        return "Cannot start IBC to barrel transfer during watering";
    }

    # Make sure IBC fill is not running
    Gartenbewaesserung_StopIBCFill($hash);

    my $ibcToBarrelValve = AttrVal($name, "ibcToBarrelValveDevice", "");
    if($ibcToBarrelValve eq "") {
        return "No IBC to barrel valve configured (ibcToBarrelValveDevice)";
    }

    # Check if we need a pump for IBC to barrel
    my $ibcToBarrelPump = AttrVal($name, "ibcToBarrelPumpDevice", "");
    my $duration = AttrVal($name, "ibcToBarrelDuration", 15);

    if($ibcToBarrelPump ne "") {
        # Use pump for IBC to barrel transfer
        Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelPump, "on");
        Log3 $name, 4, "$name: IBC to barrel pump started";

        # Wait for pump, then open valve
        my $delay = AttrVal($name, "pumpStartDelay", 3);
        $delay = abs($delay);  # Use absolute value

        InternalTimer(gettimeofday() + $delay, sub {
            Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelValve, "on");
            $hash->{HELPER}{ibcToBarrelActive} = 1;

            # Set end time
            Gartenbewaesserung_SetEndTime($hash, $duration);

            readingsBeginUpdate($hash);
            readingsBulkUpdate($hash, "ibcToBarrelActive", "yes");
            readingsBulkUpdate($hash, "state", "ibc to barrel");
            readingsBulkUpdate($hash, "phase", "transferring water from IBC (pump)");
            readingsEndUpdate($hash, 1);

            Log3 $name, 3, "$name: IBC to barrel transfer started with pump for $duration minutes";

            # Schedule auto-stop
            InternalTimer(gettimeofday() + ($duration * 60), sub {
                Gartenbewaesserung_StopIBCtoBarrel($hash);
            }, $hash);
        }, $hash);
    }
    else {
        # Gravity feed - no pump needed
        Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelValve, "on");
        $hash->{HELPER}{ibcToBarrelActive} = 1;

        # Set end time
        Gartenbewaesserung_SetEndTime($hash, $duration);

        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash, "ibcToBarrelActive", "yes");
        readingsBulkUpdate($hash, "state", "ibc to barrel");
        readingsBulkUpdate($hash, "phase", "transferring water from IBC (gravity)");
        readingsEndUpdate($hash, 1);

        Log3 $name, 3, "$name: IBC to barrel transfer started (gravity) for $duration minutes";

        # Schedule auto-stop
        InternalTimer(gettimeofday() + ($duration * 60), sub {
            Gartenbewaesserung_StopIBCtoBarrel($hash);
        }, $hash);
    }

    return undef;
}

##############################################################################
# Stop IBC to Barrel
##############################################################################
sub Gartenbewaesserung_StopIBCtoBarrel {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    return if(!$hash->{HELPER}{ibcToBarrelActive});

    my $ibcToBarrelValve = AttrVal($name, "ibcToBarrelValveDevice", "");
    if($ibcToBarrelValve ne "") {
        Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelValve, "off");
    }

    # Turn off pump if used
    my $ibcToBarrelPump = AttrVal($name, "ibcToBarrelPumpDevice", "");
    if($ibcToBarrelPump ne "") {
        Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelPump, "off");
        Log3 $name, 4, "$name: IBC to barrel pump stopped";
    }

    $hash->{HELPER}{ibcToBarrelActive} = 0;

    Gartenbewaesserung_ClearEndTime($hash);

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "ibcToBarrelActive", "no");
    readingsBulkUpdate($hash, "state", "idle");
    readingsBulkUpdate($hash, "phase", "idle");
    readingsBulkUpdate($hash, "barrelLevel", Gartenbewaesserung_GetBarrelLevelAfterRefill($hash, 50));
    readingsEndUpdate($hash, 1);

    Log3 $name, 3, "$name: IBC to barrel transfer stopped";

    return undef;
}

##############################################################################
# Check for rain and IBC filling opportunity
##############################################################################
sub Gartenbewaesserung_CheckRain {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    RemoveInternalTimer($hash, "Gartenbewaesserung_CheckRain");

    return if(IsDisabled($name));

    # Do not interrupt a manually started circuit
    if($hash->{HELPER}{manualCircuit}) {
        my $interval = AttrVal($name, "rainCheckInterval", 5) * 60;
        InternalTimer(gettimeofday() + $interval, "Gartenbewaesserung_CheckRain", $hash);
        return;
    }

    my $rainSensorDef = AttrVal($name, "rainSensorDevice", "");
    if($rainSensorDef ne "") {
        my $activeValue = AttrVal($name, "rainSensorActiveValue", "");
        my $inactiveValue = AttrVal($name, "rainSensorInactiveValue", "");

        my $isRaining = Gartenbewaesserung_GetSensorValue($name, $rainSensorDef, $activeValue, $inactiveValue);

        if($isRaining) {
            if(!defined($hash->{HELPER}{rainingSince})) {
                $hash->{HELPER}{rainingSince} = time();
                readingsSingleUpdate($hash, "rainDetectedSince", TimeNow(), 1);
                Log3 $name, 4, "$name: Rain detected";
            }

            # Check how to trigger IBC fill: sensor-based or time-based
            my $barrelSensorDef = AttrVal($name, "barrelFullSensorDevice", "");
            if($barrelSensorDef ne "") {
                # Sensor-based: start IBC fill only when barrel is full
                if(ReadingsVal($name, "barrelFull", "no") eq "yes" && !$hash->{HELPER}{ibcFilling}) {
                    Log3 $name, 3, "$name: Rain active and barrel full, starting IBC fill";
                    Gartenbewaesserung_StartIBCFill($hash, 0);
                }
            }
            else {
                # Time-based fallback: start IBC fill after rainDurationForIBC minutes
                my $rainDuration = time() - $hash->{HELPER}{rainingSince};
                my $requiredDuration = AttrVal($name, "rainDurationForIBC", 30) * 60;

                if($rainDuration >= $requiredDuration && !$hash->{HELPER}{ibcFilling}) {
                    Log3 $name, 3, "$name: Rain duration threshold reached, starting IBC fill";
                    Gartenbewaesserung_StartIBCFill($hash, 0);
                }
            }
        }
        else {
            if(defined($hash->{HELPER}{rainingSince})) {
                delete $hash->{HELPER}{rainingSince};
                Log3 $name, 4, "$name: Rain stopped";

                # Stop IBC fill when rain stops
                if($hash->{HELPER}{ibcFilling}) {
                    Gartenbewaesserung_StopIBCFill($hash);
                }
            }
        }
    }

    my $interval = AttrVal($name, "rainCheckInterval", 5) * 60;
    InternalTimer(gettimeofday() + $interval, "Gartenbewaesserung_CheckRain", $hash);
}

##############################################################################
# Check schedule for automatic watering
##############################################################################
sub Gartenbewaesserung_CheckSchedule {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    RemoveInternalTimer($hash, "Gartenbewaesserung_CheckSchedule");

    return if(IsDisabled($name));
    return if(AttrVal($name, "manualMode", 0));

    my ($sec, $min, $hour, $mday, $mon, $year, $wday) = localtime(time);
    my $currentTime = sprintf("%02d:%02d", $hour, $min);

    # Check weekday restriction
    if(AttrVal($name, "weekdaysOnly", 0) && ($wday == 0 || $wday == 6)) {
        InternalTimer(gettimeofday() + 60, "Gartenbewaesserung_CheckSchedule", $hash);
        return;
    }

    # Check start times
    for(my $i = 1; $i <= 3; $i++) {
        my $startTime = AttrVal($name, "startTime$i", "");
        if($startTime ne "" && $startTime eq $currentTime) {
            if(!$hash->{HELPER}{watering} && !$hash->{HELPER}{manualCircuit}) {
                Log3 $name, 3, "$name: Schedule triggered at $currentTime";
                Gartenbewaesserung_StartWatering($hash);
            }
        }
    }

    InternalTimer(gettimeofday() + 60, "Gartenbewaesserung_CheckSchedule", $hash);
}

##############################################################################
# Get status information
##############################################################################
sub Gartenbewaesserung_GetStatus {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    my $status = "\n=== Gartenbewässerung Status ===\n";
    $status .= "Version: " . $hash->{VERSION} . "\n\n";
    $status .= "State: " . ReadingsVal($name, "state", "unknown") . "\n";
    $status .= "Phase: " . ReadingsVal($name, "phase", "unknown") . "\n";
    $status .= "Current Valve: " . ReadingsVal($name, "currentValve", "none") . "\n";
    $status .= "Remaining Time: " . ReadingsVal($name, "remainingTime", "-") . "\n";
    $status .= "Cycle Progress: " . ReadingsVal($name, "cycleProgress", "0/0") . "\n";
    $status .= "Pause Active: " . ReadingsVal($name, "pauseActive", "no") . "\n";
    $status .= "Pause Time Remaining: " . ReadingsVal($name, "pauseTimeRemaining", "-") . "\n";
    $status .= "IBC Filling: " . ReadingsVal($name, "ibcFilling", "no") . "\n";
    $status .= "IBC to Barrel: " . ReadingsVal($name, "ibcToBarrelActive", "no") . "\n";
    $status .= "Pump Overrun Alert: " . ReadingsVal($name, "pumpOverrunAlert", "no") . "\n";
    $status .= "Barrel Full: " . ReadingsVal($name, "barrelFull", "not configured") . "\n";
    $status .= "Barrel Empty: " . ReadingsVal($name, "barrelEmpty", "not configured") . "\n";
    $status .= "IBC Full: " . ReadingsVal($name, "ibcFull", "not configured") . "\n";
    $status .= "IBC Empty: " . ReadingsVal($name, "ibcEmpty", "not configured") . "\n";
    $status .= "Raining: " . ReadingsVal($name, "raining", "not configured") . "\n";
    $status .= "Rain Since: " . ReadingsVal($name, "rainDetectedSince", "never") . "\n";
    $status .= "Soil Moisture: " . ReadingsVal($name, "soilMoisture", "not configured") . "\n";
    $status .= "Last Watering: " . ReadingsVal($name, "lastWatering", "never") . "\n";
    $status .= "Last Circuit: " . ReadingsVal($name, "lastCircuitWatering", "never") . "\n";

    return $status;
}

##############################################################################
# Update NOTIFYDEV to monitor all configured sensor devices
##############################################################################
sub Gartenbewaesserung_UpdateNotifyDev {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    
    my @devices;
    
    # Collect all sensor device names
    my @sensorAttrs = qw(
        barrelFullSensorDevice barrelEmptySensorDevice
        ibcFullSensorDevice ibcEmptySensorDevice
        rainSensorDevice moistureSensorDevice
    );
    
    foreach my $attr (@sensorAttrs) {
        my $deviceDef = AttrVal($name, $attr, "");
        if($deviceDef ne "") {
            my ($device, $reading) = Gartenbewaesserung_ParseDevice($deviceDef);
            push @devices, $device if($device ne "" && defined($defs{$device}));
        }
    }
    
    if(@devices) {
        # Set NOTIFYDEV to monitor these devices
        $hash->{NOTIFYDEV} = join(",", @devices);
        Log3 $name, 4, "$name: NOTIFYDEV set to: " . $hash->{NOTIFYDEV};
    } else {
        # No sensors configured, monitor nothing (or global: .*)
        delete $hash->{NOTIFYDEV};
        Log3 $name, 4, "$name: No sensors configured, NOTIFYDEV cleared";
    }
}

1;

=pod
=item device
=item summary Intelligente Gartenbewässerung mit IBC-Container und Regenwasser-Management
=item summary_DE Intelligente Gartenbewässerung mit IBC-Container und Regenwasser-Management

=begin html

<a id="Gartenbewaesserung"></a>
<h3>Gartenbewaesserung</h3>
<ul>
    <p>FHEM Modul für intelligente Gartenbewässerung mit bis zu 8 Ventilen, Regenwasserfass und IBC-Container.</p>
    <p><b>Version: 1.0.28</b></p>

    <h4>Features</h4>
    <ul>
        <li>Bis zu 8 Magnetventile für verschiedene Bewässerungsbereiche</li>
        <li>Unterstützt MQTT2 Relay Boards (z.B. Tasmota mit 8-Kanal Relay Board)</li>
        <li>Automatische Füll-Pausen während der Bewässerung (IBC → Fass oder Hauswasseranschluss)</li>
        <li><b>NEU in 1.0.17:</b> Verzögerter Pumpen-/Ventilstart wird nach Pause-Ende sicher abgebrochen, wenn kein aktiver Kreis mehr läuft</li>
        <li><b>NEU in 1.0.16:</b> Fass-leer-Sensor (<code>barrelEmptySensorDevice</code>): Pumpe wird sofort abgeschaltet wenn das Fass leer ist; Bewässerung startet wieder sobald der Sensor inaktiv wird</li>
        <li><b>NEU in 1.0.14:</b> Ereignisgesteuerter IBC-Befüllungs-Trigger: Fass-voll-Sensor löst IBC-Fill bei Regen sofort aus</li>
        <li><b>NEU in 1.0.14:</b> NotifyFn überwacht den Regensensor für sofortige Reaktion (kein Polling-Delay)</li>
        <li><b>NEU in 1.0.14:</b> Manueller startCircuit wird nicht mehr durch Regen oder Scheduler unterbrochen</li>
        <li><b>NEU in 1.0.14:</b> IBC→Fass-Transfer stoppt korrekt bei vollem Fass (kein Rückpumpen mehr)</li>
        <li><b>NEU in 1.0.13:</b> Pausen auch bei Einzelkreislauf-Modus (startCircuit)</li>
        <li>Regenwasser-Management mit IBC-Container</li>
        <li>Feuchtigkeitssensor-Integration (überspringt Bewässerung bei ausreichender Feuchtigkeit)</li>
        <li>Regensensor-Integration (automatische IBC-Befüllung bei Regen)</li>
        <li>Zeitgesteuerte Bewässerung (bis zu 3 Startzeiten pro Tag)</li>
        <li>Einzelkreislauf-Modus (z.B. für Gewächshaus mit eigenem Feuchtigkeitssensor)</li>
        <li>Flexible Werte-Erkennung (on/off, true/false, 1/0, open/closed, etc.)</li>
        <li>Negatives Pumpen-Delay (Ventil öffnet VOR Pumpe)</li>
        <li>Live-Countdown der verbleibenden Zeit</li>
        <li>Fass-voll Sensor stoppt Pause vorzeitig</li>
        <li>Umfassende Konfigurationsvalidierung</li>
    </ul>

    <h4>Versionshistorie</h4>
    <ul>
        <li><b>1.0.28</b> (2026-05-31): Fix: Pumpen-Watchdog wird beim Ausschalten der Pumpe in <code>SwitchDevice</code> zuverlässig gestoppt (vorher abhängig vom noch nicht aktualisierten Geräte-Reading). Behebt falschen <code>pumpOverrunAlert</code> nach Abschluss einer Bewässerung (<code>FinishWatering</code>/<code>FinishCircuit</code>) und während der Fass-Befüllung mitten im Zyklus. Neu: <code>StartIBCFill</code> verweigert die Befüllung bei leerem Fass (kein Pumpen-Trockenlauf).</li>
        <li><b>1.0.27</b> (2026-05-31): Fix: Pumpen-Watchdog wird beim Fass-leer-Not-Aus (<code>HandleBarrelEmpty</code>) explizit gestoppt. Andernfalls blieb nach gestoppter IBC-Befüllung ein verwaister Watchdog-Timer aktiv und löste Minuten später einen falschen <code>pumpOverrunAlert</code> aus, obwohl die Pumpe längst aus war.</li>
        <li><b>1.0.26</b> (2026-05-31): Fix: Kein automatisches Fass-Nachfüllen mehr, wenn das Fass durch die IBC-Befüllung geleert wurde. Bisher wurde direkt nach der IBC-Befüllung das Fass wieder aufgefüllt (aus dem IBC zurückgepumpt oder per Hauswasser) – das führte zu einem Pendeln Fass&lt;-&gt;IBC. Das Fass füllt sich nun von selbst über den Regen wieder auf; die IBC-Befüllung setzt erst fort, wenn der Fass-voll-Sensor erneut anschlägt.</li>
        <li><b>1.0.25</b> (2026-05-25): Neu: Attribut <code>barrelFillTimeout</code> – Watchdog für Fass-Befüllung. Schlägt nicht der <code>barrelFullSensorDevice</code> innerhalb der konfigurierten Minuten an, wird Reading <code>barrelFillTimeoutAlert</code> auf <code>yes</code> gesetzt (Hinweis auf leeren IBC bzw. gestörte Wasserzufuhr). Reset bei <code>barrelFull:yes</code> oder <code>raining:yes</code>.</li>
        <li><b>1.0.24</b> (2026-05-25): Fix: Pumpen-Watchdog wird auch im manuellen Ventilmodus (<code>set valve N</code>) gestartet; <code>StopCurrentValve</code> stoppt den Watchdog, damit kein verwaister <code>PumpOverrun</code>-Timer feuert</li>
        <li><b>1.0.23</b> (2026-05-24): Fix: Pumpen-Watchdog wird bei Bewässerungs-/Kreis-Pausen gestoppt und beim Resume mit voller Laufzeit neu gestartet; konsistentes Watchdog-Handling in barrelEmpty-Refill-Pausen</li>
        <li><b>1.0.22</b> (2026-05-24): Fix: <code>barrelEmpty:no</code> stoppt einen laufenden Fass-Refill nicht mehr vorzeitig; während aktivem Refill wird das Event nur geloggt</li>
        <li><b>1.0.21</b> (2026-05-19): Neu: Pumpen-Laufzeit-Watchdog (<code>pumpMaxRuntime</code>) mit Not-Aus, Reading <code>pumpOverrunAlert</code> und manuellem Reset per <code>set resetPumpOverrunAlert</code></li>
        <li><b>1.0.19</b> (2026-05-10): barrelEmpty:no startet jetzt erst eine Befüllpause; Resume erst nach barrelFull oder Pause-Timer; barrelLevel=100 nur bei echtem barrelFull</li>
        <li><b>1.0.17</b> (2026-05-10): Fix für kurze Restzeiten nach Pause: Delay-Start wird bei inaktivem Kreis verworfen, bei Laufzeit &lt;= abs(pumpStartDelay) wird ohne Delay gestartet</li>
        <li><b>1.0.16</b> (2026-05-04): Fass-leer-Sensor (barrelEmptySensorDevice): Pumpe aus wenn Fass leer, Pumpe frei wenn Fass wieder voll</li>
        <li><b>1.0.14</b> (2026-05-02): Ereignisgesteuerter IBC-Befüllungs-Trigger, Regensensor in NotifyFn, manualCircuit-Flag, IBC→Fass korrekt bei vollem Fass</li>
        <li><b>1.0.13</b> (2026-04-29): Automatische Pausen auch bei startCircuit (Einzelkreislauf)</li>
        <li><b>1.0.12</b> (2026-04-29): Endlosschleifen-Bug gefixt, negatives Delay, IBC→Fass in Pausen, IBC-Leer-Sensor, Fass-voll stoppt Pause</li>
        <li><b>1.0.11</b> (2026-04-29): Automatische Füll-Pausen während Bewässerung</li>
        <li><b>1.0.10</b> (2026-04-29): Ausführliche Dokumentation</li>
    </ul>

    <a id="Gartenbewaesserung-define"></a>
    <h4>Define</h4>
    <ul>
        <code>define &lt;name&gt; Gartenbewaesserung</code><br><br>
        Beispiel:<br>
        <code>define Garten Gartenbewaesserung</code>
    </ul>

    <a id="Gartenbewaesserung-set"></a>
    <h4>Set-Befehle</h4>
    <ul>
        <li><b>start</b> - Startet den kompletten Bewässerungszyklus mit allen aktiven Ventilen</li>
        <li><b>stop</b> - Stoppt sofort alle laufenden Operationen (Bewässerung, Pumpen, Ventile)</li>
        <li><b>startCircuit &lt;1-8&gt;</b> - Startet einen einzelnen Bewässerungskreis (mit voller Logik: Fass-Check, Pumpe, Ventil, <b>automatischen Pausen</b>). Perfekt für externe Steuerung z.B. vom Gewächshaus</li>
        <li><b>startIBCFill</b> - Startet manuelle IBC-Befüllung aus dem Fass (mit Pumpe)</li>
        <li><b>stopIBCFill</b> - Stoppt IBC-Befüllung</li>
        <li><b>startIBCtoBarrel</b> - Lässt Wasser vom IBC zurück ins Fass laufen (Schwerkraft oder Pumpe)</li>
        <li><b>stopIBCtoBarrel</b> - Stoppt IBC zu Fass Transfer</li>
        <li><b>startValve &lt;1-8&gt;</b> - Startet ein einzelnes Ventil manuell (ohne Automatik)</li>
        <li><b>stopValve</b> - Stoppt das aktuell laufende Ventil</li>
        <li><b>resetPumpOverrunAlert</b> - Setzt das Reading <code>pumpOverrunAlert</code> manuell auf <code>no</code> zurück</li>
        <li><b>refreshSensors</b> - Liest alle konfigurierten Sensor-Readings sofort neu ein und aktualisiert die Readings (z. B. nach Neustart oder Gerätetausch)</li>
        <li><b>validate</b> - Prüft die komplette Konfiguration und zeigt Fehler, Warnungen und Infos an</li>
    </ul>

    <a id="Gartenbewaesserung-get"></a>
    <h4>Get-Befehle</h4>
    <ul>
        <li><b>status</b> - Zeigt den aktuellen Status aller Komponenten</li>
        <li><b>config</b> - Zeigt die komplette Konfiguration übersichtlich an</li>
        <li><b>version</b> - Zeigt die Modulversion an</li>
    </ul>

    <a id="Gartenbewaesserung-attr"></a>
    <h4>Attribute</h4>
    <ul>
        <p><b>Geräte-Attribute (Device-Namen oder Device:Reading)</b></p>
        <li><a id="Gartenbewaesserung-attr-valve1Device"></a>
            <b>valve1Device</b> .. <b>valve8Device</b><br>
            Typ: textField. Standardwert: keiner.<br>
            FHEM-Gerätename des jeweiligen Magnetventils (z.B. <code>MQTT2_RELAIS:POWER1</code>).
            Unterstützt das Format <code>Device</code> oder <code>Device:Reading</code>.
        </li>
        <li><a id="Gartenbewaesserung-attr-pumpDevice"></a>
            <b>pumpDevice</b><br>
            Typ: textField. Standardwert: keiner.<br>
            FHEM-Gerätename der Hauptwasserpumpe (Fass → Ventile).
            Wird vor dem Öffnen eines Ventils eingeschaltet.
        </li>
        <li><a id="Gartenbewaesserung-attr-ibcToBarrelPumpDevice"></a>
            <b>ibcToBarrelPumpDevice</b><br>
            Typ: textField. Standardwert: keiner.<br>
            FHEM-Gerätename der Pumpe für den IBC→Fass-Transfer.
            Optional: Ohne Pumpe läuft der Transfer per Schwerkraft (Ventil <code>ibcToBarrelValveDevice</code> öffnen).
        </li>
        <li><a id="Gartenbewaesserung-attr-barrelFillValveDevice"></a>
            <b>barrelFillValveDevice</b><br>
            Typ: textField. Standardwert: keiner.<br>
            FHEM-Gerätename des Ventils am Hauswasseranschluss (füllt das Regenwasserfass aus dem Netz).
            Wird während Bewässerungs-Pausen geöffnet, wenn der IBC leer ist.
        </li>
        <li><a id="Gartenbewaesserung-attr-barrelFullSensorDevice"></a>
            <b>barrelFullSensorDevice</b><br>
            Typ: textField. Standardwert: keiner.<br>
            FHEM-Gerätename des Fass-voll-Sensors. Wenn konfiguriert, wird die IBC-Befüllung
            automatisch gestartet, sobald der Sensor „voll" meldet UND es gerade regnet
            (statt nach einer festen Regendauer). Stoppt außerdem Pausen und Direktbefüllung früh.
        </li>
        <li><a id="Gartenbewaesserung-attr-ibcFillValveDevice"></a>
            <b>ibcFillValveDevice</b><br>
            Typ: textField. Standardwert: keiner.<br>
            FHEM-Gerätename des Ventils Fass→IBC (pumpt Regenwasser in den IBC-Container).
        </li>
        <li><a id="Gartenbewaesserung-attr-ibcToBarrelValveDevice"></a>
            <b>ibcToBarrelValveDevice</b><br>
            Typ: textField. Standardwert: keiner.<br>
            FHEM-Gerätename des Ventils IBC→Fass (gibt Wasser aus dem IBC zurück ins Fass;
            Schwerkraft oder separate Pumpe <code>ibcToBarrelPumpDevice</code>).
        </li>
        <li><a id="Gartenbewaesserung-attr-ibcFullSensorDevice"></a>
            <b>ibcFullSensorDevice</b><br>
            Typ: textField. Standardwert: keiner.<br>
            FHEM-Gerätename des IBC-voll-Sensors. Stoppt die IBC-Befüllung automatisch,
            wenn der IBC-Container voll ist.
        </li>
        <li><a id="Gartenbewaesserung-attr-ibcEmptySensorDevice"></a>
            <b>ibcEmptySensorDevice</b><br>
            Typ: textField. Standardwert: keiner.<br>
            FHEM-Gerätename des IBC-leer-Sensors. Steuert die Quellenauswahl während Pausen:
            Wenn IBC leer → Hauswasseranschluss (<code>barrelFillValveDevice</code>),
            sonst → IBC→Fass (<code>ibcToBarrelValveDevice</code>).
        </li>
        <li><a id="Gartenbewaesserung-attr-barrelEmptySensorDevice"></a>
            <b>barrelEmptySensorDevice</b><br>
            Typ: textField. Standardwert: keiner.<br>
            FHEM-Gerätename des Fass-leer-Sensors. Wenn der Sensor „leer" meldet, wird die Pumpe
            sofort abgeschaltet und jede aktive Bewässerung gestoppt (Reading <code>barrelEmpty: yes</code>).
            Anschließend wird automatisch eine Befüllung des Fasses gestartet: Wenn <code>ibcEmpty: no</code>,
            wird Wasser über <code>ibcToBarrelValveDevice</code> (ggf. mit <code>ibcToBarrelPumpDevice</code>)
            aus dem IBC-Container ins Fass geleitet; wenn <code>ibcEmpty: yes</code>, wird der
            Hauswasseranschluss (<code>barrelFillValveDevice</code>) geöffnet.
            Die Befüllung stoppt automatisch nach der konfigurierten Dauer oder wenn der
            <code>barrelFullSensorDevice</code> anschlägt. Wenn der Fass-leer-Sensor während einer
            laufenden Befüllung wieder inaktiv wird, wird nur das Reading <code>barrelEmpty: no</code>
            aktualisiert; die Befüllung läuft bis Timer oder Fass-voll-Sensor weiter. Der State wird
            dabei auf <code>stopped - barrel empty - refilling</code> gesetzt.
            Wenn eine laufende Bewässerung oder ein aktiver Einzelkreis durch den Fass-leer-Stop
            unterbrochen wurde, versucht das Modul nach erfolgreichem Refill automatisch an der
            unterbrochenen Stelle (inkl. Restlaufzeit) weiterzumachen. Falls das nicht sicher möglich ist,
            wird dies im Log gemeldet und der State bleibt bei <code>stopped - barrel empty</code>.<br>
            Optionale Sensor-Wert-Attribute: <code>barrelEmptySensorActiveValue</code>,
            <code>barrelEmptySensorInactiveValue</code>.
        </li>
        <li><a id="Gartenbewaesserung-attr-barrelEmptySensorActiveValue"></a>
            <b>barrelEmptySensorActiveValue</b><br>
            Typ: textField. Standardwert: automatisch.<br>
            Wert des Fass-leer-Sensors wenn Fass leer ist. Leer = automatische Erkennung
            (on/1/true/yes/closed/active).
        </li>
        <li><a id="Gartenbewaesserung-attr-barrelEmptySensorInactiveValue"></a>
            <b>barrelEmptySensorInactiveValue</b><br>
            Typ: textField. Standardwert: automatisch.<br>
            Wert des Fass-leer-Sensors wenn Fass nicht leer ist. Leer = automatische Erkennung
            (off/0/false/no/open/inactive/dry).
        </li>
        <li><a id="Gartenbewaesserung-attr-rainSensorDevice"></a>
            <b>rainSensorDevice</b><br>
            Typ: textField. Standardwert: keiner.<br>
            FHEM-Gerätename des Regensensors. Bei Aktivierung des Sensors wird sofort
            <code>CheckRain</code> aufgerufen (ereignisgesteuert). Wenn <code>barrelFullSensorDevice</code>
            konfiguriert ist, startet die IBC-Befüllung erst bei vollem Fass.
            Ohne Fass-voll-Sensor wird nach <code>rainDurationForIBC</code> Minuten Regen gestartet.
        </li>
        <li><a id="Gartenbewaesserung-attr-moistureSensorDevice"></a>
            <b>moistureSensorDevice</b><br>
            Typ: textField. Standardwert: keiner.<br>
            FHEM-Gerätename des Bodenfeuchtigkeitssensors. Überspringt den Bewässerungszyklus,
            wenn die Feuchtigkeit über <code>moistureThreshold</code> liegt.
        </li>

        <p><b>Zeitdauer-Attribute (Slider)</b></p>
        <li><a id="Gartenbewaesserung-attr-valve1Duration"></a>
            <b>valve1Duration</b> .. <b>valve8Duration</b><br>
            Typ: Slider (1–120 Minuten). Standardwert: 15 Minuten.<br>
            Bewässerungsdauer des jeweiligen Ventils in Minuten.
        </li>
        <li><a id="Gartenbewaesserung-attr-barrelFillDuration"></a>
            <b>barrelFillDuration</b><br>
            Typ: Slider (1–60 Minuten). Standardwert: 10 Minuten.<br>
            Maximale Befüllungsdauer des Fasses aus dem Hauswasseranschluss (ohne Fass-voll-Sensor).
        </li>
        <li><a id="Gartenbewaesserung-attr-barrelFillThreshold"></a>
            <b>barrelFillThreshold</b><br>
            Typ: Slider (0–100 %). Standardwert: 30 %.<br>
            Simulierter Füllstand-Schwellwert: Fällt <code>barrelLevel</code> darunter,
            wird vor dem nächsten Ventil eine Befüllung gestartet.
        </li>
        <li><a id="Gartenbewaesserung-attr-ibcToBarrelDuration"></a>
            <b>ibcToBarrelDuration</b><br>
            Typ: Slider (1–60 Minuten). Standardwert: 15 Minuten.<br>
            Maximale Dauer des IBC→Fass-Transfers (wird durch Fass-voll-Sensor früh beendet).
        </li>
        <li><a id="Gartenbewaesserung-attr-moistureThreshold"></a>
            <b>moistureThreshold</b><br>
            Typ: Slider (0–100). Standardwert: 40.<br>
            Feuchtigkeitsschwellwert: Liegt die Bodenfeuchtigkeit über diesem Wert,
            wird der Bewässerungszyklus übersprungen.
        </li>
        <li><a id="Gartenbewaesserung-attr-wateringPauseInterval"></a>
            <b>wateringPauseInterval</b><br>
            Typ: Slider (0–60 Minuten). Standardwert: 8 Minuten.<br>
            Abstand zwischen automatischen Bewässerungs-Pausen (Fass-Nachfüllpausen).
            0 = Pausen deaktiviert.
        </li>
        <li><a id="Gartenbewaesserung-attr-wateringPauseDuration"></a>
            <b>wateringPauseDuration</b><br>
            Typ: Slider (0–60 Minuten). Standardwert: 20 Minuten.<br>
            Dauer der automatischen Bewässerungs-Pause zum Nachfüllen des Fasses.
        </li>
        <li><a id="Gartenbewaesserung-attr-rainDurationForIBC"></a>
            <b>rainDurationForIBC</b><br>
            Typ: Slider (5–180 Minuten, Schritt 5). Standardwert: 30 Minuten.<br>
            Nur relevant wenn <b>kein</b> <code>barrelFullSensorDevice</code> konfiguriert ist:
            Mindestdauer des Regens, bevor die IBC-Befüllung automatisch gestartet wird.
        </li>
        <li><a id="Gartenbewaesserung-attr-rainCheckInterval"></a>
            <b>rainCheckInterval</b><br>
            Typ: Slider (1–30 Minuten). Standardwert: 5 Minuten.<br>
            Polling-Intervall des Regen-Check-Timers (Fallback wenn NotifyFn nicht greift).
        </li>
        <li><a id="Gartenbewaesserung-attr-pumpStartDelay"></a>
            <b>pumpStartDelay</b><br>
            Typ: Slider (-30 bis +30 Sekunden). Standardwert: 3 Sekunden.<br>
            Startverzögerung zwischen Pumpe und Ventil.
            Positiv: Pumpe startet X Sekunden VOR dem Ventil.
            Negativ: Ventil öffnet X Sekunden VOR der Pumpe (Druckentlastung).
        </li>
        <li><a id="Gartenbewaesserung-attr-pumpMaxRuntime"></a>
            <b>pumpMaxRuntime</b><br>
            Typ: Slider (0–240 Minuten). Standardwert: 0 Minuten.<br>
            Maximale kontinuierliche Laufzeit der Pumpe. 0 = deaktiviert.
            Bei Überschreitung wird die Pumpe per Not-Aus gestoppt und
            <code>pumpOverrunAlert</code> auf <code>yes</code> gesetzt.
        </li>
        <li><a id="Gartenbewaesserung-attr-barrelFillTimeout"></a>
            <b>barrelFillTimeout</b><br>
            Typ: Slider (0–120 Minuten). Standardwert: 0 Minuten.<br>
            Watchdog für die Fass-Befüllung: Wird das Befüllventil
            (<code>barrelFillValveDevice</code> oder <code>ibcToBarrelValveDevice</code>)
            geöffnet, aber der <code>barrelFullSensorDevice</code> meldet innerhalb der
            konfigurierten Minuten kein <code>full</code>, dann wird Reading
            <code>barrelFillTimeoutAlert</code> auf <code>yes</code> gesetzt.
            Typischer Indikator: IBC leer oder Wasserzufuhr unterbrochen.
            0 = deaktiviert. Voraussetzung: <code>barrelFullSensorDevice</code> ist konfiguriert.
            Reset des Alerts bei <code>barrelFull:yes</code> oder <code>raining:yes</code>.
        </li>

        <li><a id="Gartenbewaesserung-attr-barrelEmptyMaxRefillAttempts"></a>
            <b>barrelEmptyMaxRefillAttempts</b><br>
            Typ: Slider (0–10). Standardwert: 3.<br>
            Loop-Breaker gegen endloses Nachfüll&lt;-&gt;Leerlauf-Pendeln: Läuft das Fass während
            einer Bewässerung trotz wiederholtem Nachfüllen binnen Sekunden immer wieder leer
            (typisch: IBC leer und keine Hauswasser-Reserve über <code>barrelFillValveDevice</code>),
            bricht das Modul nach so vielen erfolglosen Versuchen ab und geht in den State
            <code>stopped - no water</code> (statt Pumpe/Ventile endlos zu takten).
            Automatischer Neustart der unterbrochenen Bewässerung, sobald wieder Wasser gemeldet wird:
            <code>barrelFull:yes</code>, <code>ibcEmpty:no</code> (IBC hat wieder Wasser) oder
            <code>raining:yes</code>. 0 = deaktiviert (altes Verhalten, endlose Versuche).
        </li>

        <p><b>Zeitplan-Attribute</b></p>
        <li><a id="Gartenbewaesserung-attr-startTime1"></a>
            <b>startTime1</b>, <b>startTime2</b>, <b>startTime3</b><br>
            Typ: textField (Format HH:MM). Standardwert: keiner.<br>
            Bis zu 3 tägliche Startzeiten für den automatischen Bewässerungszyklus.
            Beispiel: <code>06:00</code>
        </li>
        <li><a id="Gartenbewaesserung-attr-activeValves"></a>
            <b>activeValves</b><br>
            Typ: textField. Standardwert: <code>1,2,3,4,5,6,7,8</code>.<br>
            Kommagetrennte Liste der aktiven Ventilnummern (1–8), die im Zyklus verwendet werden.
            Beispiel: <code>1,3,5,8</code>
        </li>

        <p><b>Boolean-Attribute</b></p>
        <li><a id="Gartenbewaesserung-attr-weekdaysOnly"></a>
            <b>weekdaysOnly</b><br>
            Typ: 0/1. Standardwert: 0.<br>
            1 = Automatische Bewässerung nur an Werktagen (Mo–Fr). 0 = täglich.
        </li>
        <li><a id="Gartenbewaesserung-attr-manualMode"></a>
            <b>manualMode</b><br>
            Typ: 0/1. Standardwert: 0.<br>
            1 = Automatischer Zeitplan deaktiviert (nur manuelle Steuerung per Set-Befehlen).
        </li>
        <li><a id="Gartenbewaesserung-attr-moistureSensorInvert"></a>
            <b>moistureSensorInvert</b><br>
            Typ: 0/1. Standardwert: 0.<br>
            1 = Feuchtigkeitssensor-Logik umkehren (nützlich wenn hoher Wert = trocken).
        </li>
        <li><a id="Gartenbewaesserung-attr-disable"></a>
            <b>disable</b><br>
            Typ: 0/1. Standardwert: 0.<br>
            1 = Modul komplett deaktivieren (keine Timer, keine Events).
        </li>

        <p><b>Sensor-Werte-Attribute</b></p>
        <li><a id="Gartenbewaesserung-attr-switchOnValue"></a>
            <b>switchOnValue</b><br>
            Typ: textField. Standardwert: <code>ON</code>.<br>
            Wert zum Einschalten von Ventilen und Pumpen (z.B. <code>ON</code>, <code>1</code>, <code>true</code>).
        </li>
        <li><a id="Gartenbewaesserung-attr-switchOffValue"></a>
            <b>switchOffValue</b><br>
            Typ: textField. Standardwert: <code>OFF</code>.<br>
            Wert zum Ausschalten von Ventilen und Pumpen (z.B. <code>OFF</code>, <code>0</code>, <code>false</code>).
        </li>
        <li><a id="Gartenbewaesserung-attr-rainSensorActiveValue"></a>
            <b>rainSensorActiveValue</b><br>
            Typ: textField. Standardwert: automatisch.<br>
            Wert des Regensensors bei aktivem Regen. Leer = automatische Erkennung
            (on/1/true/yes/rain/raining/wet/closed/active).
        </li>
        <li><a id="Gartenbewaesserung-attr-rainSensorInactiveValue"></a>
            <b>rainSensorInactiveValue</b><br>
            Typ: textField. Standardwert: automatisch.<br>
            Wert des Regensensors bei kein Regen. Leer = automatische Erkennung
            (off/0/false/no/open/inactive/dry).
        </li>
        <li><a id="Gartenbewaesserung-attr-barrelFullSensorActiveValue"></a>
            <b>barrelFullSensorActiveValue</b><br>
            Typ: textField. Standardwert: automatisch.<br>
            Wert des Fass-voll-Sensors wenn Fass voll. Leer = automatische Erkennung.
        </li>
        <li><a id="Gartenbewaesserung-attr-barrelFullSensorInactiveValue"></a>
            <b>barrelFullSensorInactiveValue</b><br>
            Typ: textField. Standardwert: automatisch.<br>
            Wert des Fass-voll-Sensors wenn Fass nicht voll. Leer = automatische Erkennung.
        </li>
        <li><a id="Gartenbewaesserung-attr-ibcFullSensorActiveValue"></a>
            <b>ibcFullSensorActiveValue</b><br>
            Typ: textField. Standardwert: automatisch.<br>
            Wert des IBC-voll-Sensors wenn IBC voll. Leer = automatische Erkennung.
        </li>
        <li><a id="Gartenbewaesserung-attr-ibcFullSensorInactiveValue"></a>
            <b>ibcFullSensorInactiveValue</b><br>
            Typ: textField. Standardwert: automatisch.<br>
            Wert des IBC-voll-Sensors wenn IBC nicht voll. Leer = automatische Erkennung.
        </li>
        <li><a id="Gartenbewaesserung-attr-ibcEmptySensorActiveValue"></a>
            <b>ibcEmptySensorActiveValue</b><br>
            Typ: textField. Standardwert: automatisch.<br>
            Wert des IBC-leer-Sensors wenn IBC leer. Leer = automatische Erkennung.
        </li>
        <li><a id="Gartenbewaesserung-attr-ibcEmptySensorInactiveValue"></a>
            <b>ibcEmptySensorInactiveValue</b><br>
            Typ: textField. Standardwert: automatisch.<br>
            Wert des IBC-leer-Sensors wenn IBC nicht leer. Leer = automatische Erkennung.
        </li>
        <li><a id="Gartenbewaesserung-attr-moistureSensorReading"></a>
            <b>moistureSensorReading</b><br>
            Typ: textField. Standardwert: <code>moisture</code>.<br>
            Name des Readings am Feuchtigkeitssensor-Device (z.B. <code>humidity</code>,
            <code>soil_moisture</code>).
        </li>
    </ul>

    <a id="Gartenbewaesserung-readings"></a>
    <h4>Readings</h4>
    <ul>
        <li><b>pumpOverrunAlert</b> - <code>yes</code>/<code>no</code>; wird auf <code>yes</code> gesetzt, wenn die Pumpe wegen überschrittener <code>pumpMaxRuntime</code> abgeschaltet wurde.</li>
        <li><b>barrelFillTimeoutAlert</b> - <code>yes</code>/<code>no</code>; wird auf <code>yes</code> gesetzt, wenn das Befüllventil länger als <code>barrelFillTimeout</code> Minuten offen war, ohne dass <code>barrelFull</code> auf <code>yes</code> ging (IBC vermutlich leer oder Wasserzufuhr gestört). Reset automatisch bei <code>barrelFull:yes</code> oder <code>raining:yes</code>.</li>
    </ul>

</ul>

=end html

=cut
