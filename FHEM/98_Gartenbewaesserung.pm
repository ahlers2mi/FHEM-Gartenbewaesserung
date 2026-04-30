##############################################################################
#
#     98_Gartenbewaesserung.pm
#
#     FHEM Modul für intelligente Gartenbewässerung mit IBC-Container
#     Version 1.0.13 - 2026-04-29
#
#     Unterstützt MQTT2 Relay Boards (z.B. Tasmota)
#     Dynamische Werte-Erkennung (on/off, true/false, 1/0, etc.)
#     Automatische Füll-Pausen während Bewässerung
#
##############################################################################
#
# Versionshistorie:
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

    $hash->{VERSION}    = '1.0.13';
    $hash->{DefFn}      = "Gartenbewaesserung_Define";
    $hash->{UndefFn}    = "Gartenbewaesserung_Undef";
    $hash->{SetFn}      = "Gartenbewaesserung_Set";
    $hash->{GetFn}      = "Gartenbewaesserung_Get";
    $hash->{AttrFn}     = "Gartenbewaesserung_Attr";
    $hash->{NotifyFn}   = "Gartenbewaesserung_Notify";
    
    $hash->{AttrList} = 
        "valve1Device valve2Device valve3Device valve4Device " .
        "valve5Device valve6Device valve7Device valve8Device " .
        "pumpDevice " .
        "ibcToBarrelPumpDevice " .
        "barrelFillValveDevice " .
        "barrelFullSensorDevice " .
        "ibcFillValveDevice " .
        "ibcToBarrelValveDevice " .
        "ibcFullSensorDevice " .
        "ibcEmptySensorDevice " .
        "rainSensorDevice " .
        "moistureSensorDevice " .
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
        "startTime1 startTime2 startTime3 " .
        "rainDurationForIBC:slider,5,5,180 " .
        "rainCheckInterval:slider,1,1,30 " .
        "pumpStartDelay:slider,-30,1,30 " .
        "activeValves " .
        "weekdaysOnly:0,1 " .
        "manualMode:0,1 " .
        "switchOnValue switchOffValue " .
        "rainSensorActiveValue rainSensorInactiveValue " .
        "barrelFullSensorActiveValue barrelFullSensorInactiveValue " .
        "ibcFullSensorActiveValue ibcFullSensorInactiveValue " .
        "ibcEmptySensorActiveValue ibcEmptySensorInactiveValue " .
        "moistureSensorReading moistureSensorInvert:0,1 " .
        "disable:0,1 " .
        $readingFnAttributes;
}

##############################################################################
sub Gartenbewaesserung_Define {
    my ($hash, $def) = @_;
    my @a = split("[ \t][ \t]*", $def);
    
    return "Usage: define <name> Gartenbewaesserung" if(@a != 2);
    
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
    $attr{$name}{wateringPauseInterval} = 8 if(!defined($attr{$name}{wateringPauseInterval}));
    $attr{$name}{wateringPauseDuration} = 20 if(!defined($attr{$name}{wateringPauseDuration}));
    
    # Default values for switches and sensors
    $attr{$name}{switchOnValue} = "ON" if(!defined($attr{$name}{switchOnValue}));
    $attr{$name}{switchOffValue} = "OFF" if(!defined($attr{$name}{switchOffValue}));
    
    # Read initial sensor values
    InternalTimer(gettimeofday() + 2, sub {
        Gartenbewaesserung_UpdateSensorReadings($hash);
    }, $hash);
    
    # Start timer for scheduled watering
    InternalTimer(gettimeofday() + 60, "Gartenbewaesserung_CheckSchedule", $hash);
    
    # Start timer for rain monitoring
    InternalTimer(gettimeofday() + 30, "Gartenbewaesserung_CheckRain", $hash);
    
    Log3 $name, 3, "$name: Gartenbewaesserung v" . $hash->{VERSION} . " initialized";
    
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
    
    # Update sensor readings when sensor attributes change
    if($cmd eq "set" && $attrName =~ /(barrel|ibc|rain|moisture).*Device/) {
        InternalTimer(gettimeofday() + 1, sub {
            Gartenbewaesserung_UpdateSensorReadings($hash);
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
    
    # Monitor sensor changes
    foreach my $event (@{$events}) {
        # Barrel full sensor
        my $barrelSensorDef = AttrVal($name, "barrelFullSensorDevice", "");
        if($barrelSensorDef ne "") {
            my ($barrelDev, $barrelReading) = Gartenbewaesserung_ParseDevice($barrelSensorDef);
            if($devName eq $barrelDev) {
                my $activeValue = AttrVal($name, "barrelFullSensorActiveValue", "");
                if(Gartenbewaesserung_CheckSensorActive($name, $event, $barrelReading, $activeValue)) {
                    readingsSingleUpdate($hash, "barrelFull", "yes", 1);
                    Gartenbewaesserung_CheckBarrelFull($hash);
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
            if($devName eq $ibcEmptyDev) {
                my $activeValue = AttrVal($name, "ibcEmptySensorActiveValue", "");
                if(Gartenbewaesserung_CheckSensorActive($name, $event, $ibcEmptyReading, $activeValue)) {
                    readingsSingleUpdate($hash, "ibcEmpty", "yes", 1);
                }
                elsif(Gartenbewaesserung_CheckSensorInactive($name, $event, $ibcEmptyReading,
                      AttrVal($name, "ibcEmptySensorInactiveValue", ""))) {
                    readingsSingleUpdate($hash, "ibcEmpty", "no", 1);
                }
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
            my $delayInfo = $delay < 0 ? "valve opens ${delay}s BEFORE pump" : 
                           $delay > 0 ? "pump starts ${delay}s BEFORE valve" : "simultaneous";
            push @info, "Pump: $pumpDevice ($delayInfo) OK";
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
    if($barrelFullSensor eq "") {
        push @warnings, "No barrel full sensor configured (barrelFullSensorDevice)";
    }
    else {
        my ($device, $reading) = Gartenbewaesserung_ParseDevice($barrelFullSensor);
        if(!defined($defs{$device})) {
            push @errors, "Barrel full sensor device '$device' does not exist";
        }
        else {
            $reading = "state" if($reading eq "");
            my $value = ReadingsVal($device, $reading, "unknown");
            push @info, "Barrel full sensor: $barrelFullSensor (current: $value) OK";
        }
    }
    
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
    if($ibcFullSensor eq "") {
        push @warnings, "No IBC full sensor configured (ibcFullSensorDevice)";
    }
    else {
        my ($device, $reading) = Gartenbewaesserung_ParseDevice($ibcFullSensor);
        if(!defined($defs{$device})) {
            push @errors, "IBC full sensor device '$device' does not exist";
        }
        else {
            $reading = "state" if($reading eq "");
            my $value = ReadingsVal($device, $reading, "unknown");
            push @info, "IBC full sensor: $ibcFullSensor (current: $value) OK";
        }
    }
    
    # Check IBC empty sensor
    my $ibcEmptySensor = AttrVal($name, "ibcEmptySensorDevice", "");
    if($ibcEmptySensor eq "") {
        push @info, "No IBC empty sensor (optional, defaults to: use IBC if not full)";
    }
    else {
        my ($device, $reading) = Gartenbewaesserung_ParseDevice($ibcEmptySensor);
        if(!defined($defs{$device})) {
            push @errors, "IBC empty sensor device '$device' does not exist";
        }
        else {
            $reading = "state" if($reading eq "");
            my $value = ReadingsVal($device, $reading, "unknown");
            push @info, "IBC empty sensor: $ibcEmptySensor (current: $value) OK";
        }
    }
    
    # Check rain sensor
    my $rainSensor = AttrVal($name, "rainSensorDevice", "");
    if($rainSensor eq "") {
        push @warnings, "No rain sensor configured (rainSensorDevice) - IBC auto-fill disabled";
    }
    else {
        my ($device, $reading) = Gartenbewaesserung_ParseDevice($rainSensor);
        if(!defined($defs{$device})) {
            push @errors, "Rain sensor device '$device' does not exist";
        }
        else {
            $reading = "state" if($reading eq "");
            my $value = ReadingsVal($device, $reading, "unknown");
            my $activeVal = AttrVal($name, "rainSensorActiveValue", "auto");
            my $inactiveVal = AttrVal($name, "rainSensorInactiveValue", "auto");
            push @info, "Rain sensor: $rainSensor (current: $value, active=$activeVal, inactive=$inactiveVal) OK";
        }
    }
    
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
    my $delayText = $pumpDelay < 0 ? "valve opens " . abs($pumpDelay) . " sec BEFORE pump" :
                    $pumpDelay > 0 ? "pump starts $pumpDelay sec BEFORE valve" : "simultaneous";
    $config .= "  Main pump: $pump\n";
    $config .= "  Pump timing: $delayText\n";
    
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
    my $barrelDur = AttrVal($name, "barrelFillDuration", 10);
    my $barrelThreshold = AttrVal($name, "barrelFillThreshold", 30);
    $config .= "  Fill valve (water supply): $barrelValve\n";
    $config .= "  Full sensor: $barrelSensor\n";
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
    my @activeValues = ('on', '1', 'true', 'yes', 'closed', 'active', 'wet', 'rain', 'raining');
    
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
    my @inactiveValues = ('off', '0', 'false', 'no', 'open', 'inactive', 'dry');
    
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
    my @activeValues = ('on', '1', 'true', 'yes', 'closed', 'active', 'wet', 'rain', 'raining');
    foreach my $val (@activeValues) {
        return 1 if($value =~ /^$val$/i);
    }
    
    return 0;
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
    $hash->{HELPER}{circuitNumber} = $circuitNum;
    $hash->{HELPER}{circuitStartTime} = time();  # Track start time for pauses
    delete $hash->{HELPER}{valveRemainingTime};  # Clear any leftover remaining time
    
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
    readingsSingleUpdate($hash, "barrelLevel", 100, 1);
    
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
    
    if($pumpDevice ne "") {
        if($delay < 0) {
            # Negative delay: Open valve FIRST, then pump
            Gartenbewaesserung_SwitchDevice($name, $valveDevice, "on");
            Log3 $name, 4, "$name: Circuit $circuitNum valve opened (negative delay)";
            
            InternalTimer(gettimeofday() + abs($delay), sub {
                Gartenbewaesserung_SwitchDevice($name, $pumpDevice, "on");
                Log3 $name, 4, "$name: Pump started after valve (negative delay)";
            }, $hash);
        }
        elsif($delay > 0) {
            # Positive delay: Start pump FIRST, wait, then valve
            Gartenbewaesserung_SwitchDevice($name, $pumpDevice, "on");
            Log3 $name, 4, "$name: Pump started for circuit $circuitNum";
            
            InternalTimer(gettimeofday() + $delay, sub {
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
    
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "state", "paused");
    readingsBulkUpdate($hash, "phase", "pause - refilling");
    readingsBulkUpdate($hash, "pauseActive", "yes");
    readingsEndUpdate($hash, 1);
    
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
    InternalTimer($hash->{HELPER}{pauseEndTimer}, sub {
        Gartenbewaesserung_EndCircuitPause($hash, $circuitNum);
    }, $hash);
}

##############################################################################
# End circuit pause and resume
##############################################################################
sub Gartenbewaesserung_EndCircuitPause {
    my ($hash, $circuitNum) = @_;
    my $name = $hash->{NAME};
    
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
    
    readingsSingleUpdate($hash, "barrelLevel", 100, 1);
    Gartenbewaesserung_ClearPauseTime($hash);
    
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "state", "circuit mode");
    readingsBulkUpdate($hash, "phase", "resuming circuit $circuitNum");
    readingsBulkUpdate($hash, "pauseActive", "no");
    readingsEndUpdate($hash, 1);
    
    # Resume circuit with remaining time
    InternalTimer(gettimeofday() + 2, sub {
        Gartenbewaesserung_RunCircuit($hash, $circuitNum);
    }, $hash);
}

##############################################################################
# Finish circuit watering
##############################################################################
sub Gartenbewaesserung_FinishCircuit {
    my ($hash, $circuitNum) = @_;
    my $name = $hash->{NAME};
    
    $hash->{HELPER}{circuitMode} = 0;
    delete $hash->{HELPER}{circuitNumber};
    delete $hash->{HELPER}{circuitStartTime};
    delete $hash->{HELPER}{lastPauseEnd};
    delete $hash->{HELPER}{valveRemainingTime};
    
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
    
    readingsBeginUpdate($hash);
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
    
    # Mark as paused
    $hash->{HELPER}{pauseActive} = 1;
    $hash->{HELPER}{pauseStartTime} = time();
    
    # Clear valve end time, set pause end time
    Gartenbewaesserung_ClearEndTime($hash);
    Gartenbewaesserung_SetPauseEndTime($hash, $pauseDuration);
    
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
    InternalTimer($hash->{HELPER}{pauseEndTimer}, sub {
        Gartenbewaesserung_EndWateringPause($hash);
    }, $hash);
}

##############################################################################
# End watering pause and resume
##############################################################################
sub Gartenbewaesserung_EndWateringPause {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    
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
    
    # Reset barrel level
    readingsSingleUpdate($hash, "barrelLevel", 100, 1);
    
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
    
    if($pumpDevice ne "") {
        if($delay < 0) {
            # Negative delay: Open valve FIRST, then pump
            Gartenbewaesserung_SwitchDevice($name, $valveDevice, "on");
            Log3 $name, 4, "$name: Valve $valveNum opened (negative delay)";
            
            InternalTimer(gettimeofday() + abs($delay), sub {
                Gartenbewaesserung_SwitchDevice($name, $pumpDevice, "on");
                Log3 $name, 4, "$name: Pump started after valve (negative delay)";
            }, $hash);
        }
        elsif($delay > 0) {
            # Positive delay: Start pump FIRST, wait, then valve
            Gartenbewaesserung_SwitchDevice($name, $pumpDevice, "on");
            Log3 $name, 4, "$name: Pump started";
            
            InternalTimer(gettimeofday() + $delay, sub {
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
    readingsSingleUpdate($hash, "barrelLevel", 100, 1);
    
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
    
    # If filling barrel directly
    if($hash->{HELPER}{barrelFilling}) {
        Log3 $name, 3, "$name: Stopping barrel fill (sensor triggered)";
        Gartenbewaesserung_StopBarrelFill($hash);
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
            RemoveInternalTimer($hash, "Gartenbewaesserung_EndCircuitPause");
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
    my ($hash) = @_;
    my $name = $hash->{NAME};
    
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
    
    # Start pump
    my $pumpDevice = AttrVal($name, "pumpDevice", "");
    if($pumpDevice ne "") {
        Gartenbewaesserung_SwitchDevice($name, $pumpDevice, "on");
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
    
    # Check if IBC is already full
    if(ReadingsVal($name, "ibcFull", "no") eq "yes") {
        Log3 $name, 3, "$name: IBC already full";
        return "IBC already full" if($manual);
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
    readingsBulkUpdate($hash, "barrelLevel", 100);
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
            
            my $rainDuration = time() - $hash->{HELPER}{rainingSince};
            my $requiredDuration = AttrVal($name, "rainDurationForIBC", 30) * 60;
            
            if($rainDuration >= $requiredDuration && !$hash->{HELPER}{ibcFilling}) {
                Log3 $name, 3, "$name: Rain duration threshold reached, starting IBC fill";
                Gartenbewaesserung_StartIBCFill($hash, 0);
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
            if(!$hash->{HELPER}{watering}) {
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
    $status .= "Barrel Full: " . ReadingsVal($name, "barrelFull", "not configured") . "\n";
    $status .= "IBC Full: " . ReadingsVal($name, "ibcFull", "not configured") . "\n";
    $status .= "IBC Empty: " . ReadingsVal($name, "ibcEmpty", "not configured") . "\n";
    $status .= "Raining: " . ReadingsVal($name, "raining", "not configured") . "\n";
    $status .= "Rain Since: " . ReadingsVal($name, "rainDetectedSince", "never") . "\n";
    $status .= "Soil Moisture: " . ReadingsVal($name, "soilMoisture", "not configured") . "\n";
    $status .= "Last Watering: " . ReadingsVal($name, "lastWatering", "never") . "\n";
    $status .= "Last Circuit: " . ReadingsVal($name, "lastCircuitWatering", "never") . "\n";
    
    return $status;
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
    <p><b>Version: 1.0.13</b></p>
    
    <h4>Features</h4>
    <ul>
        <li>Bis zu 8 Magnetventile für verschiedene Bewässerungsbereiche</li>
        <li>Unterstützt MQTT2 Relay Boards (z.B. Tasmota mit 8-Kanal Relay Board)</li>
        <li>Automatische Füll-Pausen während der Bewässerung (IBC → Fass oder Hauswasseranschluss)</li>
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
        <li><b>validate</b> - Prüft die komplette Konfiguration und zeigt Fehler, Warnungen und Infos an</li>
    </ul>

    <a id="Gartenbewaesserung-get"></a>
    <h4>Get-Befehle</h4>
    <ul>
        <li><b>status</b> - Zeigt den aktuellen Status aller Komponenten</li>
        <li><b>config</b> - Zeigt die komplette Konfiguration übersichtlich an</li>
        <li><b>version</b> - Zeigt die Modulversion an</li>
    </ul>

</ul>

=end html

=cut
