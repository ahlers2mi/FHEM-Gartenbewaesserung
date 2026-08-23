#!/usr/bin/env perl
# Szenario-Tests fuer 98_Gartenbewaesserung gegen die FHEM-Attrappe.
use strict; use warnings;
use FindBin;
use lib $FindBin::Bin;   # FhemStub.pm liegt neben dieser Datei
use FhemStub;

my $MODULE = $ARGV[0] or die "Aufruf: run.pl <pfad/98_Gartenbewaesserung.pm>\n";
our (%defs, %attr);
my ($ok, $fail) = (0, 0);

sub is {
    my ($got, $want, $what) = @_;
    $got = "(undef)" if(!defined($got));
    if("$got" eq "$want") { $ok++;  printf("    ok    %-46s = %s\n", $what, $got) }
    else { $fail++; printf("  FAIL    %-46s = %s (erwartet %s)\n", $what, $got, $want) }
}
sub ok_true { my ($c,$what)=@_; $c ? ($ok++, printf("    ok    %s\n",$what)) : ($fail++, printf("  FAIL    %s\n",$what)) }

# --- Testanlage: Attrappen fuer alle Aktoren und Sensoren -------------------
sub dev { my ($n,$s)=@_; $defs{$n} = { NAME=>$n, TYPE=>"dummy", STATE=>$s//"off", READINGS=>{} }; }
sub setr { my ($n,$r,$v)=@_; main::readingsSingleUpdate($defs{$n}, $r, $v, 1) }

sub build {
    my (%o) = @_;
    %defs = (); %attr = (); @main::TIMERS = (); @main::EVENTS = (); @main::LOG = ();
    dev("relais");                       # traegt POWER1..POWER10
    dev("pumpe"); dev("sens");
    setr("relais", "POWER$_", "OFF") for (1..10);
    setr("sens", "barrelFull", "no");
    setr("sens", "barrelEmpty", "no");
    setr("sens", "ibcFull", "no");
    setr("sens", "ibcEmpty", "no");
    setr("sens", "stadtwasser", $o{mains} // "off");

    # Relais, die schon VOR dem Define an sind - simuliert einen Neustart
    # mitten im Betrieb.
    setr("relais", $_, "ON") for @{$o{relaysOn} || []};

    my $h = { NAME=>"bw", TYPE=>"Gartenbewaesserung", READINGS=>{}, HELPER=>{} };
    $defs{bw} = $h;
    my %a = (
        activeValves => "1,2,3",
        valve1Device => "relais:POWER1", valve1Duration => 10, valve1Name => "Magnolie",
        valve2Device => "relais:POWER4", valve2Duration => 20, valve2Name => "Weg Anbau",
        valve3Device => "relais:POWER3", valve3Duration => 11, valve3Name => "Pool",
        pumpDevice => "relais:POWER8", pumpStartDelay => -3, pumpMaxRuntime => 20,
        ibcFillValveDevice => "relais:POWER6", ibcToBarrelValveDevice => "relais:POWER5",
        ibcToBarrelDuration => 14,
        barrelFullSensorDevice => "sens:barrelFull",   barrelFullSensorActiveValue => "yes",
        barrelEmptySensorDevice => "sens:barrelEmpty", barrelEmptySensorActiveValue => "yes",
        ibcFullSensorDevice => "sens:ibcFull", ibcEmptySensorDevice => "sens:ibcEmpty",
        mainsSupplyDevice => "sens:stadtwasser",
        barrelUsableVolume => 148, barrelFloatLevel => 81, ibcUsableVolume => 2000,
        barrelFillThreshold => 30, barrelFillDuration => 20, barrelFillTimeout => 12,
        wateringPauseInterval => 8, wateringPauseDuration => 20,
        switchOnValue => "ON", switchOffValue => "OFF",
        valve1Flow_lpm => 18.5, valve2Flow_lpm => 14.2, valve3Flow_lpm => 15,
        ibcFillFlow_lpm => 34.2, ibcToBarrelFlow_lpm => 12.2, mainsFillFlow_lpm => 4.4,
        %{$o{attr} || {}},
    );
    $attr{bw} = \%a;
    Gartenbewaesserung_Define($h, "bw Gartenbewaesserung");
    # Die Foerderraten liest das Modul als READING (es lernt sie), nicht als Attribut.
    main::readingsSingleUpdate($h, "ibcFillFlow_lpm", 34.2, 0);
    main::readingsSingleUpdate($h, "ibcToBarrelFlow_lpm", 12.2, 0);
    main::advance(10);
    return $h;
}
sub relay { return main::ReadingsVal("relais", $_[0], "?") }
sub rd    { return main::ReadingsVal("bw", $_[0], "(fehlt)") }
sub sens  { my ($r,$v)=@_; setr("sens",$r,$v);
            Gartenbewaesserung_Notify($defs{bw}, $defs{sens}) if(defined(&Gartenbewaesserung_Notify)); }

# Modul laden. Nicht per require: das Modul laeuft unter "use strict" und
# erwartet die FHEM-Globals als bereits deklariert. Also Quelle lesen, eine
# use-vars-Praeambel davorsetzen und im Paket main auswerten - genau wie es
# fhem.pl beim Einlesen der Module tut.
{
    open(my $fh, "<", $MODULE) or die "$MODULE: $!\n";
    my $src = do { local $/; <$fh> };
    close($fh);
    my $pre = 'package main; use vars qw(%defs %attr %modules %data %cmds %intAt '
            . '$init_done $reread_active $readingFnAttributes);' . "\n";
    local $SIG{__WARN__} = sub {};
    eval $pre . $src . "\n1;\n" or die "Modul laesst sich nicht laden: $@\n";
}
Gartenbewaesserung_Initialize($main::modules{Gartenbewaesserung} = {});

print "\n";

# ---------------------------------------------------------------- Szenarien
sub scenario { printf("\n%s\n", $_[0]) }
sub guarded {                       # Rekursionen abfangen statt den Rechner zu fluten
    my ($what, $code) = @_;
    my $err = "";
    eval { local $SIG{ALRM} = sub { die "HAENGT: $what kehrt nicht zurueck\n" };
           alarm 5; $code->(); alarm 0; 1 } or $err = $@;
    alarm 0;
    $err ? do { $fail++; print "  FAIL    $err" } : do { $ok++; print "    ok    $what kehrt zurueck\n" };
    return !$err;
}

scenario("A  Endlosrekursion ohne barrelFillValveDevice (Regression 22.08.2026)");
{
    my $h = build();
    main::readingsSingleUpdate($h, "barrelLevel", 20, 1);
    guarded("StartWatering", sub { Gartenbewaesserung_StartWatering($h); main::advance(60) });
    my $n = grep { /Barrel level low, filling before valve/ } @main::LOG;
    ok_true($n <= 3, "hoechstens 3x 'Barrel level low' (war: $n)");
    is(relay("POWER1"), "ON", "Ventil 1 laeuft trotzdem");
}

scenario("B  Vollstaendiger Zyklus mit Wasser: alle drei Kreise, in der richtigen Reihenfolge");
{
    my $h = build();
    main::readingsSingleUpdate($h, "barrelLevel", 100, 1);
    main::readingsSingleUpdate($h, "barrelLevel_l", 148, 1);
    sens("barrelFull", "yes");                     # Fass voll -> keine Pause noetig
    Gartenbewaesserung_StartWatering($h);
    my @seen;
    for (1..120) {                                  # 120 x 30 s = eine Stunde
        main::advance(30);
        my $v = rd("currentValve");
        push @seen, $v if($v =~ /^\d+$/ && (!@seen || $seen[-1] ne $v));
    }
    is(join(",", @seen), "1,2,3", "Reihenfolge der Kreise");
    is(rd("state"), "idle", "Zyklus beendet");
    ok_true(rd("lastWatering") ne "(fehlt)", "lastWatering wurde gesetzt");
    is(relay("POWER8"), "OFF", "Pumpe ist aus");
}

scenario("C  Volles Fass: Nachfuellpause entfaellt, es wird weitergegossen (v1.0.62)");
{
    my $h = build();
    main::readingsSingleUpdate($h, "barrelLevel", 100, 1);
    sens("barrelFull", "yes");
    Gartenbewaesserung_StartWatering($h);
    main::advance(9 * 60);                          # ueber den 8-Minuten-Punkt hinaus
    is(rd("pauseActive"), "no", "keine Pause trotz abgelaufenem Intervall");
    is(relay("POWER5"), "OFF", "IBC-Ventil bleibt zu");
    ok_true((grep { /skipping the refill pause/ } @main::LOG) > 0, "Log nennt den uebersprungenen Grund");
}

scenario("D  Nachlauf in ein volles Fass wird vom Waechter gestoppt (v1.0.62)");
{
    my $h = build();
    sens("barrelFull", "yes");                      # Fass ist VOR dem Oeffnen schon voll
    $h->{HELPER}{pauseActive} = 1;
    $h->{HELPER}{pauseSource} = "ibc";
    Gartenbewaesserung_SwitchDevice("bw", "relais:POWER5", "on");
    Gartenbewaesserung_NoteIbcToBarrelStart($h);
    is(relay("POWER5"), "ON", "Ventil ist offen");
    main::advance(60);                              # Waechter guckt nach 5 s
    is(relay("POWER5"), "OFF", "Waechter hat nach spaetestens 60 s zugemacht");
}

scenario("E  Stadtwasser hebt den Fuellstand, gedeckelt auf barrelFloatLevel (v1.0.63)");
{
    my $h = build(mains => "on");
    Gartenbewaesserung_SetBarrelLevel($h, 0, "test", 1);
    main::advance(10 * 60);                         # 10 min x 4,4 l/min = 44 l
    my $l = rd("barrelLevel_l");
    ok_true($l >= 35 && $l <= 50, "nach 10 min etwa 44 l (ist: $l)");
    main::advance(60 * 60);
    is(rd("barrelLevel_l"), 81, "gedeckelt auf die Schwimmerhoehe");
}

scenario("F  mainsFillIbc dreht Runden bis zum Ziel (v1.0.64)");
{
    my $h = build(mains => "on");
    Gartenbewaesserung_SetBarrelLevel($h, 0, "test", 1);
    Gartenbewaesserung_SetIbcLevel($h, 0, "test", 1);
    my $r = Gartenbewaesserung_MainsFillIbcStart($h, "150");
    is(rd("mainsFillIbcTarget"), 150, "Ziel uebernommen");
    for (1..200) {
        main::advance(30);
        # Pumpe an -> Fass laeuft leer, Sensor meldet das
        if(relay("POWER8") eq "ON" && main::ReadingsVal("sens","barrelEmpty","no") eq "no") {
            main::advance(150);
            sens("barrelEmpty", "yes"); sens("barrelEmpty", "no");
        }
        last if(rd("mainsFillIbcTarget") eq "0");
    }
    is(rd("mainsFillIbcTarget"), 0, "Auftrag beendet");
    is(rd("mainsFillIbcState"), "done", "Grund: Ziel erreicht");
    ok_true(rd("mainsFillIbcDone") >= 150, "mindestens 150 l gebucht (ist: " . rd("mainsFillIbcDone") . ")");
    if($ENV{DEBUG}) { print "      | $_\n" for grep { !/^[45]:/ } @main::LOG[-40..-1] }
}

scenario("G  Offenes Ventil wird vor dem Lernen abgerechnet (v1.0.62)");
{
    my $h = build();
    main::readingsSingleUpdate($h, "barrelLevel", 100, 1);
    sens("barrelFull", "yes");                      # setzt den Lern-Anker
    Gartenbewaesserung_StartWatering($h);
    main::advance(7 * 60);                          # Kreis 1 laeuft noch
    is(rd("currentValve"), 1, "Kreis 1 laeuft");
    sens("barrelEmpty", "yes");                     # Fass leer WAEHREND Ventil 1 offen
    my $learned = rd("valve1Flow_lpm");
    ok_true($learned > 5 && $learned < 40,
            "gelernte Rate plausibel, nicht 148/kurz (ist: $learned)");
}

scenario("H  Neustart mitten im Pumpen: verwaiste Aktoren werden abgeschaltet (v1.0.68)");
{
    # Pumpe und Fass->IBC-Ventil waren vor dem Neustart an, das Reading ebenso.
    my $h = build(mains => "on", relaysOn => ["POWER6", "POWER8"]);
    is(relay("POWER8"), "OFF", "Pumpe abgeschaltet");
    is(relay("POWER6"), "OFF", "Fass->IBC-Ventil abgeschaltet");
    ok_true(rd("orphanShutdown") ne "(fehlt)", "orphanShutdown protokolliert");
    ok_true((grep { /were still switched on after the restart/ } @main::LOG) > 0,
            "Log nennt den Grund deutlich");
}

scenario("I  Ohne Waisen passiert nichts");
{
    my $h = build(mains => "on");
    is(rd("orphanShutdown"), "(fehlt)", "kein orphanShutdown ohne Anlass");
}

scenario("J  Foerderrate nur als ATTRIBUT gesetzt, Reading fehlt (v1.0.69)");
{
    my $h = build(attr => { ibcToBarrelFlow_lpm => 12.2 });
    # bewusst KEIN Reading setzen - genau die Lage vom 23.08.
    main::readingsSingleUpdate($h, "ibcToBarrelFlow_lpm", "", 0);
    delete $h->{READINGS}{ibcToBarrelFlow_lpm};
    is(Gartenbewaesserung_FlowRate($h, "ibcToBarrelFlow_lpm"), 12.2, "Attribut greift");

    # und das Reading schlaegt das Attribut, wenn es da ist
    main::readingsSingleUpdate($h, "ibcToBarrelFlow_lpm", 14.3, 0);
    is(Gartenbewaesserung_FlowRate($h, "ibcToBarrelFlow_lpm"), 14.3, "Reading hat Vorrang");

    # Achtung: der Standardaufbau SETZT das Attribut - fuer diesen Fall leeren.
    my $leer = build(attr => { ibcToBarrelFlow_lpm => "" });
    delete $leer->{READINGS}{ibcToBarrelFlow_lpm};
    is(Gartenbewaesserung_FlowRate($leer, "ibcToBarrelFlow_lpm"), 0, "ohne beides: 0, nichts erfunden");
}

scenario("K  Manuelles startIBCtoBarrel wird abgerechnet (v1.0.70)");
{
    my $h = build();
    Gartenbewaesserung_SetIbcLevel($h, 400, "test", 1);
    Gartenbewaesserung_SetBarrelLevel($h, 100, "test", 1);
    Gartenbewaesserung_StartIBCtoBarrel($h);
    is(relay("POWER5"), "ON", "Ventil offen");
    main::advance(5 * 60);
    sens("barrelFull", "yes");                       # Fass wird voll -> Ende

    is(rd("lastIbcToBarrelEnd"), "barrelFull", "Ende protokolliert");
    ok_true(rd("lastIbcToBarrelDuration") >= 4.9 && rd("lastIbcToBarrelDuration") <= 5.2,
            "Dauer ~5 min (ist: " . rd("lastIbcToBarrelDuration") . ")");
    # 5 min x 12,2 l/min = 61 l muessen vom IBC abgehen
    ok_true(rd("ibcLevel_l") >= 330 && rd("ibcLevel_l") <= 345,
            "IBC von 400 auf ~339 gebucht (ist: " . rd("ibcLevel_l") . ")");
}

scenario("L  Manueller Transfer in ein volles Fass: Waechter greift (v1.0.70)");
{
    my $h = build();
    sens("barrelFull", "yes");                       # schon voll VOR dem Start
    Gartenbewaesserung_StartIBCtoBarrel($h);
    is(relay("POWER5"), "ON", "Ventil geht erstmal auf");
    main::advance(60);
    is(relay("POWER5"), "OFF", "Waechter macht binnen 60 s zu");
}

scenario("M  Giessen, dann Rest abpumpen: keine falsche Giessrate (v1.0.71)");
{
    # wie am 23.08.: Pausenintervall aus, Kreis laeuft in einem Stueck durch
    my $h = build(attr => { wateringPauseInterval => 0 });
    sens("barrelFull", "yes");                        # Anker, Taint geloescht
    Gartenbewaesserung_StartCircuit($h, 3);
    main::advance(11 * 60 + 30);                      # valve3Duration + Luft
    is(rd("currentValve"), "none", "Kreis 3 fertig");
    my $vorher = rd("valve3Flow_lpm");

    Gartenbewaesserung_StartIBCFill($h, 1);           # Rest hochpumpen
    main::advance(120);
    sens("barrelEmpty", "yes");                       # Pumpe macht das Fass leer

    is(rd("valve3Flow_lpm"), $vorher, "valve3Flow_lpm unveraendert, nichts Falsches gelernt");
    ok_true(rd("wateringFlow_lpm") eq "(fehlt)", "auch keine Sammelrate erfunden");
    ok_true(rd("lastIbcFillVolume_l") ne "(fehlt)", "der Pumpenlauf wird trotzdem verbucht");
}

print "\n";
printf("%d ok, %d fehlgeschlagen\n", $ok, $fail);
exit($fail ? 1 : 0);
