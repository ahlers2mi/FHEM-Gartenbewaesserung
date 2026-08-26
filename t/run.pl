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
    main::advance(60);                              # erster Takt setzt nur den Anker
    main::advance(5 * 60);
    my $a = rd("barrelLevel_l");
    main::advance(10 * 60);
    my $b = rd("barrelLevel_l");
    # Steigung statt Absolutwert: der Rundungsfehler haeufte sich frueher an und
    # machte aus 4,4 l/min sichtbare 4,0. Zehn Minuten muessen 44 l bringen.
    ok_true(($b - $a) >= 43 && ($b - $a) <= 45,
            "10 weitere Minuten bringen 44 l, nicht 40 (ist: " . ($b - $a) . ")");
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
    # Die Rate haette 5 min x 12,2 = 61 l ergeben. Ins Fass passen aber nur
    # 148 - 100 = 48 l, und waehrend eines Transfers giesst nichts. Bis v1.0.73
    # wurden die 61 gebucht - 13 l, die es nie gab. Seit v1.0.74 deckelt die
    # Buchung am Fassmass.
    ok_true(rd("ibcLevel_l") >= 348 && rd("ibcLevel_l") <= 356,
            "IBC von 400 auf ~352 gebucht, am Kopfraum gedeckelt (ist: "
            . rd("ibcLevel_l") . ")");
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

scenario("N  Stadtwasser-Runde bei OFFENEM Hahn: Zulauf wird eingerechnet (v1.0.76)");
{
    # 81 l Schwimmerhoehe, 2:40 Laufzeit - aber der Hahn speist mit 4,4 l/min
    # weiter. Bewegt wurden also 81 + 4,4 x 2,667 = 92,7 l, und die Pumpe
    # schafft 92,7/2,667 = 34,8 l/min. Ohne den Zulauf-Term lernte das Modul
    # 30,3 und haette eine gesunde Pumpe fuer verschlissen gehalten.
    my $h = build(mains => "on");
    main::readingsSingleUpdate($h, "barrelLevel_l", 81, 0);
    Gartenbewaesserung_StartIBCFill($h, 1, 1);        # Schwimmerhoehe -> leer
    main::advance(160);                               # 2:40
    sens("barrelEmpty", "yes");

    my $vol = rd("lastIbcFillVolume_l");
    ok_true($vol >= 92 && $vol <= 94, "gebucht: 81 + Zulauf = 93 l (ist: $vol)");
    my $neu = rd("ibcFillFlow_lpm");
    # gemessen 34,8, gedaempft 0,7*34,2 + 0,3*34,8 = 34,4
    ok_true($neu > 34.2 && $neu < 34.7, "Rate bleibt oben: 34,2 -> $neu");
    is(rd("lastIbcFillRain_l"), 0, "nichts davon zaehlt als Regen");
}

scenario("N2 Dieselbe Runde bei ZUGEDREHTEM Hahn lernt die kleinere Rate (v1.0.76)");
{
    # Gegenprobe: ohne Zulauf sind es wirklich nur 81 l in 2:40 = 30,4 l/min.
    # Der Unterschied zwischen N und N2 ist genau die Zweideutigkeit, die aus
    # dem Log allein nicht aufzuloesen war.
    my $h = build(mains => "off");
    main::readingsSingleUpdate($h, "barrelLevel_l", 81, 0);
    Gartenbewaesserung_StartIBCFill($h, 1, 1);
    main::advance(160);
    sens("barrelEmpty", "yes");

    is(rd("lastIbcFillVolume_l"), 81, "gebucht: nur die Schwimmermenge");
    my $neu = rd("ibcFillFlow_lpm");
    ok_true($neu > 32.8 && $neu < 33.4, "Rate zieht nach unten: 34,2 -> $neu");
    is(rd("lastIbcFillRain_l"), 0, "und auch hier ist es kein Regen");
}

scenario("N3 Ein Wechsel am Stadtwasser kommt als Ereignis an (v1.0.76)");
{
    my $h = build(mains => "off");
    is(rd("mainsSupply"), "off", "Ausgangslage");
    sens("stadtwasser", "on");
    is(rd("mainsSupply"), "on", "Aufdrehen wird sofort uebernommen");
    sens("stadtwasser", "off");
    is(rd("mainsSupply"), "off", "Zudrehen ebenso");
}

scenario("O  Schwimmer-Lauf ohne Trockenlauf lernt nichts (v1.0.74)");
{
    # Vorzeitig beendet - die bewegte Menge ist unbekannt, also darf die Rate
    # sich nicht verbiegen. Ein Test, der sonst nur die Gutwetterseite prueft.
    my $h = build(mains => "on");
    main::readingsSingleUpdate($h, "barrelLevel_l", 81, 0);
    Gartenbewaesserung_StartIBCFill($h, 1, 1);
    main::advance(40);
    Gartenbewaesserung_StopIBCFill($h, "stopped by hand");

    is(rd("ibcFillFlow_lpm"), "34.2", "Rate unveraendert");
    ok_true(rd("lastIbcFillVolume_l") ne "81", "und die 81 werden nicht gebucht");
}

scenario("P  Leergelaufene Strecke: Buchung am Kopfraum gedeckelt (v1.0.74)");
{
    # Die Nacht zum 24.08.: Transferventil 20 min offen, IBC gibt nichts mehr
    # her, Ende auf maxDuration. 20,1 x 12,7 = 255 l wurden in ein 148-l-Fass
    # gebucht - dreimal hintereinander.
    my $h = build(attr => { ibcToBarrelDuration => 20 });
    Gartenbewaesserung_SetIbcLevel($h, 500, "test", 1);
    Gartenbewaesserung_SetBarrelLevel($h, 0, "test", 1);
    Gartenbewaesserung_StartIBCtoBarrel($h);
    main::advance(20 * 60 + 30);                      # laeuft in maxDuration

    # Der Dauer-Timer meldet "stopped", der Pausen-Pfad "maxDuration" - beiden
    # gemeinsam ist, dass der Fass-voll-Kontakt NIE kam. Genau das ist das
    # Kennzeichen eines Laufs, dessen Menge niemand gemessen hat.
    ok_true(rd("lastIbcToBarrelEnd") ne "barrelFull",
            "Kontakt nie erreicht (Ende: " . rd("lastIbcToBarrelEnd") . ")");
    my $gebucht = rd("lastIbcToBarrelVolume_l");
    ok_true($gebucht <= 148,
            "nie mehr als ins Fass passt (ist: $gebucht, Rate haette 244 ergeben)");
    ok_true(rd("ibcLevel_l") >= 352,
            "IBC hoechstens um ein Fass gesunken (ist: " . rd("ibcLevel_l") . ")");
}

scenario("Q  Regen in Wippenschritten verliert keinen Nachkommaanteil (v1.0.75)");
{
    # roofArea 45 x runoff 0.8 = 36 l/mm. Ein 0,2-mm-Kipp bringt 7,2 l.
    # Bis v1.0.74 wurde daraus jedes Mal 7 - 0,2 l je Kipp, immer nach unten.
    my $h = build(attr => { roofArea => 45, runoffCoefficient => 0.8 });
    Gartenbewaesserung_SetBarrelLevel($h, 0, "test", 1);
    for my $i (1 .. 15) {                             # 15 Kippen = 3,0 mm = 108 l
        setr("sens", "regen_mm", sprintf("%.1f", $i * 0.2));
        Gartenbewaesserung_AdjustBarrelLevel($h, 0.2 * 45 * 0.8, "rain");
    }
    my $ist = rd("barrelLevel_l");
    # exakt 108; v1.0.74 kommt auf 105 (15 x 7)
    ok_true($ist >= 107 && $ist <= 109,
            "15 Kippen a 7,2 l ergeben 108 l (ist: $ist)");
}

scenario("R  Anker und Bruchteil zaehlen nicht doppelt (v1.0.75)");
{
    # MainsFillTick rechnet gegen einen Anker, AdjustBarrelLevel fuehrt jetzt den
    # Bruchteil mit. Wuerde der Tick den GERUNDETEN Stand lesen, kaeme der
    # Bruchteil zweimal an und das Fass stiege zu schnell.
    my $h = build(mains => "on", attr => { mainsFillFlow_lpm => 4.4 });
    Gartenbewaesserung_SetBarrelLevel($h, 0, "test", 1);
    main::advance(60);                                # erster Takt setzt nur den Anker
    my $start = rd("barrelLevel_l");
    main::advance(10 * 60);
    my $zu = rd("barrelLevel_l") - $start;
    ok_true($zu >= 43 && $zu <= 45,
            "10 Minuten bringen 44 l, nicht mehr und nicht weniger (ist: $zu)");
}

scenario("S  Transfer aus leerem IBC erfindet kein Wasser (v1.0.77)");
{
    # 25.08., 05:07: Fass leer, Nachfuellen aus einem IBC, der auf 0 steht.
    # 20 min x Rate = 314 l, gedeckelt auf den Kopfraum 148 - und diese 148
    # wurden gebucht. Das Fass sprang auf 100 %, obwohl nichts ankam.
    my $h = build(attr => { ibcToBarrelDuration => 20 });
    Gartenbewaesserung_SetIbcLevel($h, 0, "test", 1);
    Gartenbewaesserung_SetBarrelLevel($h, 0, "test", 1);
    Gartenbewaesserung_StartIBCtoBarrel($h);
    main::advance(20 * 60 + 30);

    is(rd("barrelLevel_l"), 0, "Fass bleibt leer");
    is(rd("barrelLevel"), 0, "auch in Prozent");
    my $g = rd("lastIbcToBarrelVolume_l");
    ok_true($g eq "unknown" || $g == 0, "nichts gebucht (ist: $g)");
}

scenario("T  Teilvorrat wird nur bis zum Vorrat gebucht (v1.0.77)");
{
    # Gegenprobe: 40 l im IBC, die Rate wuerde 244 l hergeben. Gebucht werden
    # duerfen genau die 40 - nicht 0 und nicht 148.
    my $h = build(attr => { ibcToBarrelDuration => 20 });
    Gartenbewaesserung_SetIbcLevel($h, 40, "test", 1);
    Gartenbewaesserung_SetBarrelLevel($h, 0, "test", 1);
    Gartenbewaesserung_StartIBCtoBarrel($h);
    main::advance(20 * 60 + 30);

    is(rd("lastIbcToBarrelVolume_l"), 40, "genau der Vorrat");
    is(rd("barrelLevel_l"), 40, "und der steht im Fass");
    is(rd("ibcLevel_l"), 0, "IBC ist danach leer");
}

scenario("U  Leitungswasser-Zaehler laeuft nur bei offenem Ventil (v1.0.78)");
{
    # Hahn auf, Fass leer -> das Schwimmerventil steht offen, 4,4 l/min.
    my $h = build(mains => "on");
    Gartenbewaesserung_SetBarrelLevel($h, 0, "test", 1);
    main::advance(60);                                # erster Takt setzt den Anker
    main::advance(10 * 60);
    my $a = rd("mainsDirect_total_l");
    ok_true($a >= 43 && $a <= 45, "10 min offen = 44 l (ist: $a)");

    # Fass auf Schwimmerhoehe -> Ventil zu, es darf nichts mehr dazukommen.
    Gartenbewaesserung_SetBarrelLevel($h, 81, "test", 1);
    main::advance(10 * 60);
    is(rd("mainsDirect_total_l"), $a, "bei vollem Schwimmer steht der Zaehler");

    # Hahn zu, Fass wieder leer -> ebenfalls nichts.
    Gartenbewaesserung_SetBarrelLevel($h, 0, "test", 1);
    sens("stadtwasser", "off");
    main::advance(10 * 60);
    is(rd("mainsDirect_total_l"), $a, "bei zugedrehtem Hahn ebenso");
}

scenario("V  Zaehlt weiter, waehrend MainsFillTick aussetzt (v1.0.78)");
{
    # Der Grund, warum der Zaehler NEBEN MainsFillTick sitzt und nicht darin:
    # sobald ein Transport laeuft, steigt MainsFillTick aus - der Hahn fuellt
    # aber weiter. In der Nacht zum 25.08. waren das acht Nachfuellpausen.
    # Zugleich der Nachkomma-Test: bei 4,4 l/min wuerde ein Liter-Zaehler je
    # Minute 0,4 l wegrunden, ueber 60 Takte also 24 l von 264.
    my $h = build(mains => "on");
    $h->{HELPER}{watering} = 1;                       # MainsFillTick setzt aus
    Gartenbewaesserung_SetBarrelLevel($h, 0, "test", 1);
    main::advance(60);                                # erster Takt setzt den Anker
    for (1 .. 60) { main::advance(60) }
    my $v = rd("mainsDirect_total_l");
    is(rd("barrelLevel_l"), 0, "MainsFillTick hat wirklich ausgesetzt");
    ok_true($v >= 263 && $v <= 265, "60 Minuten ergeben 264 l, nicht 240 (ist: $v)");
}

scenario("W  Schwimmer-Runde unterhalb der Schwimmerhoehe zaehlt nicht (v1.0.79)");
{
    # MainsFillIbcTick hat den Lauf gestartet, das Fass stand aber nur bei 40 l.
    # Bis v1.0.78 galt allein der Start durch den Tick als Nachweis - und der
    # entscheidet anhand von barrelLevel_l, das daneben liegen kann.
    my $h = build(mains => "on");
    main::readingsSingleUpdate($h, "barrelLevel_l", 40, 0);
    Gartenbewaesserung_StartIBCFill($h, 1, 1);
    main::advance(80);
    sens("barrelEmpty", "yes");

    is(rd("ibcFillFlow_lpm"), "34.2", "Rate unveraendert");
    ok_true(rd("lastIbcFillVolume_l") ne "81", "und die 81 werden nicht gebucht");
}

scenario("X  Ausreisser wird am Attribut gemessen, nicht am Reading (v1.0.79)");
{
    # Der Fall vom 25.08. um 10:17: Schwimmer-Runde in 61 Sekunden, also gut
    # 83 l/min. Steht das gelernte Reading schon auf 49,6, liess die alte
    # Bremse (2 x Reading = 99) den Wert durch - so kroch die Rate immer weiter.
    # Das Attribut bleibt bei 34,2 und haelt die Grenze fest.
    my $h = build(mains => "on");
    main::readingsSingleUpdate($h, "ibcFillFlow_lpm", 49.6, 0);
    main::readingsSingleUpdate($h, "barrelLevel_l", 81, 0);
    Gartenbewaesserung_StartIBCFill($h, 1, 1);
    main::advance(61);
    sens("barrelEmpty", "yes");

    is(rd("ibcFillFlow_lpm"), "49.6", "Rate bleibt stehen, statt weiter zu klettern");
}

print "\n";
printf("%d ok, %d fehlgeschlagen\n", $ok, $fail);
exit($fail ? 1 : 0);
