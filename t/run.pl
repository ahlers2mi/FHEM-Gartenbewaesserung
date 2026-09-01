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
sub ok_true {
    my ($c, $what) = @_;
    # Falle, die einmal zugeschlagen hat: ok_true($x =~ /y/, "text").
    # Ein FEHLGESCHLAGENER Match liefert im Listenkontext die leere Liste, nicht
    # 0 - die Argumentliste schrumpft auf einen Eintrag, der Text rutscht auf
    # $c, und ein nichtleerer Text ist wahr. Die Zusicherung wird also gruen,
    # genau wenn sie rot sein muesste, und faellt nur durch den fehlenden Text
    # auf. Ein Test, der nicht rot werden kann, ist wertlos - deshalb hier ein
    # harter Abbruch statt einer stillen Gruenmeldung. Aufrufer: !!(...) setzen.
    die "ok_true ohne Text aufgerufen - Bedingung im Listenkontext verschluckt? "
        . "Match-Bedingungen als !!(\$x =~ /y/) schreiben.\n" if(!defined($what));
    $c ? ($ok++, printf("    ok    %s\n", $what))
       : ($fail++, printf("  FAIL    %s\n", $what));
}

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

scenario("Y  Zu kurzer Schwimmer-Lauf bucht nur Rate x Zeit (v1.0.80)");
{
    # Der Fall vom 27.08.: zehn Runden buchten je ~85 l, sechs davon liefen
    # unter 1,3 Minuten. Bei 34,2 l/min sind 1,2 min hoechstens 41 l - nicht 86.
    # Der IBC stand danach auf 874 statt auf etwa 494.
    my $h = build(mains => "on");
    Gartenbewaesserung_SetIbcLevel($h, 0, "test", 1);
    main::readingsSingleUpdate($h, "barrelLevel_l", 81, 0);
    Gartenbewaesserung_StartIBCFill($h, 1, 1);
    main::advance(72);                                # 1,2 min
    sens("barrelEmpty", "yes");

    my $g = rd("lastIbcFillVolume_l");
    ok_true($g >= 38 && $g <= 48, "gebucht werden ~41 l statt 86 (ist: $g)");
    ok_true(rd("ibcLevel_l") <= 48, "und nur die kommen im IBC an (ist: "
            . rd("ibcLevel_l") . ")");
    is(rd("ibcFillFlow_lpm"), "34.2", "aus einem gekappten Lauf wird nicht gelernt");
}

scenario("Z  Ein ausreichend langer Lauf bleibt ungekappt (v1.0.80)");
{
    # Gegenprobe: 2,4 min sind bei 34,2 l/min genau die Schwimmermenge. Hier
    # darf die Schranke nicht zuschlagen, sonst waere der Fix eine Verschlimm-
    # besserung und Szenario N gaebe es nicht mehr.
    my $h = build(mains => "on");
    Gartenbewaesserung_SetIbcLevel($h, 0, "test", 1);
    main::readingsSingleUpdate($h, "barrelLevel_l", 81, 0);
    Gartenbewaesserung_StartIBCFill($h, 1, 1);
    main::advance(160);                               # 2:40
    sens("barrelEmpty", "yes");

    my $g = rd("lastIbcFillVolume_l");
    ok_true($g >= 92 && $g <= 94, "volle Schwimmermenge plus Zulauf (ist: $g)");
    ok_true(rd("ibcFillFlow_lpm") > 34.2, "und die Rate lernt weiterhin");
}

scenario("AA Nach barrelEmpty springt das Fass nicht sofort wieder auf voll (v1.0.81)");
{
    # Der Kern des 874-l-Falls. Der Ticker laeuft 20 Minuten und haelt das Fass
    # auf Schwimmerhoehe. Dann leert die Pumpe es (barrelEmpty verankert auf 0).
    # Bis v1.0.80 rechnete der Ticker aus seinem ALTEN Anker weiter und setzte
    # den Stand im naechsten Takt in einem Schritt zurueck auf 81 - woraufhin
    # MainsFillIbcTick nach einer Minute die naechste Runde startete.
    my $h = build(mains => "on");
    Gartenbewaesserung_SetBarrelLevel($h, 0, "test", 1);
    main::advance(25 * 60);                           # Ticker fuellt bis 81
    ok_true(rd("barrelLevel_l") >= 79, "Fass steht auf Schwimmerhoehe (ist: "
            . rd("barrelLevel_l") . ")");

    # Ueber den Pumpenweg leeren, nicht ueber ein Giess-Ereignis: nach einem
    # barrelEmpty beim Giessen laeuft sofort das Nachfuellen an, und dann setzt
    # MainsFillTick ohnehin aus. Der Fall vom 27.08. war eine Stadtwasser-Runde.
    # Kurz: der Lauf am 27.08. dauerte 33 Sekunden. Faellt kein Minutentakt
    # hinein, kommt MainsFillTick nie dazu, seinen Anker zu verwerfen - genau
    # das ist die Bedingung fuer den Fehler.
    Gartenbewaesserung_StartIBCFill($h, 1, 1);
    main::advance(33);
    sens("barrelEmpty", "yes");                       # Pumpe hat es geleert
    is(rd("barrelLevel_l"), 0, "auf 0 verankert");

    main::advance(70);                                # ein Takt spaeter
    my $l = rd("barrelLevel_l");
    ok_true($l <= 10, "nach einer Minute hoechstens ein paar Liter (ist: $l)");
}

scenario("BB Zu kurzer Transfer leer->voll lernt keine Schwerkraftrate (v1.0.82)");
{
    # Der Messzweig in NoteIbcToBarrelStop hatte als einziger keine Gegenprobe:
    # leeres Fass + Fass-voll-Kontakt = 148 l, egal wie kurz der Lauf war.
    # barrelEmpty ist aber keine Pegelmessung, sondern aus der Pumpenleistung
    # abgeleitet - schaltet der Schwimmer der Tauchpumpe zu frueh ab, stand noch
    # Wasser im Fass. 148 l in 2 Minuten waeren 74 l/min Schwerkraft; gemessen
    # sind 13,6 bis 15,4.
    my $h = build();
    Gartenbewaesserung_SetIbcLevel($h, 500, "test", 1);
    Gartenbewaesserung_SetBarrelLevel($h, 0, "test", 1);
    # barrelEmpty direkt setzen statt ueber den Sensor: der Sensorweg startet das
    # Nachfuellen selbst, hier soll genau EIN Transfer laufen.
    main::readingsSingleUpdate($h, "barrelEmpty", "yes", 0);
    Gartenbewaesserung_StartIBCtoBarrel($h);
    main::advance(120);                               # 2 min
    sens("barrelFull", "yes");

    is(rd("lastIbcToBarrelEnd"), "barrelFull", "Ende auf dem Kontakt");
    is(rd("ibcToBarrelFlow_lpm"), "12.2", "74 l/min werden nicht gelernt");
    my $g = rd("lastIbcToBarrelVolume_l");
    ok_true($g >= 22 && $g <= 27,
            "gebucht wird Rate x Zeit, also ~24 l statt 148 (ist: $g)");
}

scenario("CC Ein plausibler Transfer leer->voll misst weiterhin (v1.0.82)");
{
    # Gegenprobe zu BB: ohne sie waere die Bremse eine Verschlimmbesserung -
    # dieser Zweig ist die einzige Stelle, die die Schwerkraftrate ueberhaupt
    # kalibriert. 10 Minuten fuer 148 l sind 14,8 l/min, also im Rahmen.
    my $h = build();
    Gartenbewaesserung_SetIbcLevel($h, 500, "test", 1);
    Gartenbewaesserung_SetBarrelLevel($h, 0, "test", 1);
    main::readingsSingleUpdate($h, "barrelEmpty", "yes", 0);
    Gartenbewaesserung_StartIBCtoBarrel($h);
    main::advance(600);                               # 10 min
    sens("barrelFull", "yes");

    is(rd("lastIbcToBarrelVolume_l"), 148, "volles Fassmass gebucht");
    is(rd("ibcToBarrelFlow_lpm"), "13.0", "Rate lernt: 0,7 x 12,2 + 0,3 x 14,8");
    is(rd("ibcLevel_l"), 352, "und genau die 148 gehen dem IBC ab");
}

scenario("DD Bei offenem Hahn wird der Schwimmer-Anteil abgezogen (v1.0.82)");
{
    # Solange das Fass unter barrelFloatLevel steht, speist das Schwimmerventil
    # mit; bei 81 l und 12,2 + 4,4 l/min Zulauf sind das die ersten 4,9 Minuten,
    # also rund 22 l. Von den 148 l zwischen den Kontakten kamen damit ~126 aus
    # dem IBC. Ohne den Abzug bucht der Transfer dem IBC Wasser ab, das dort nie
    # wegging.
    my $h = build(mains => "on");
    Gartenbewaesserung_SetIbcLevel($h, 500, "test", 1);
    Gartenbewaesserung_SetBarrelLevel($h, 0, "test", 1);
    main::readingsSingleUpdate($h, "barrelEmpty", "yes", 0);
    Gartenbewaesserung_StartIBCtoBarrel($h);
    main::advance(600);
    sens("barrelFull", "yes");

    my $g = rd("lastIbcToBarrelVolume_l");
    ok_true($g >= 124 && $g <= 128,
            "~126 l aus dem IBC statt der vollen 148 (ist: $g)");
}

scenario("EE Ausreisser-Bremse beim Giessen (v1.0.82)");
{
    # LearnWateringFlow war die letzte Lernstelle ohne Plausibilitaetspruefung.
    # 148 l auf 2 Minuten Ventilzeit sind 74 l/min - genau der Wert, der am
    # 22.08. in valve1Flow_lpm stand, weil ein noch offenes Ventil in
    # drawMinutes fehlte. Direkt gesetzt statt ueber einen Giesslauf: die Bremse
    # soll auch dann greifen, wenn die Ursache eine andere ist als 2026-08-22.
    my $h = build();
    sens("barrelFull", "yes");                        # setzt den Lern-Anker
    main::readingsSingleUpdate($h, "valve1Flow_lpm", 14.3, 0);
    $h->{HELPER}{drawTainted} = 0;
    $h->{HELPER}{drawMinutes} = 2;
    $h->{HELPER}{drawByValve} = { 1 => 2 };
    Gartenbewaesserung_LearnWateringFlow($h);
    is(rd("valve1Flow_lpm"), "14.3", "74 l/min wird nicht gelernt");

    # Gegenprobe: 12 Minuten sind 12,3 l/min gegen ein Nennmass von 18,5 - das
    # muss durchgehen, sonst lernt der Kreis nie wieder etwas.
    $h->{HELPER}{drawTainted} = 0;
    $h->{HELPER}{drawMinutes} = 12;
    $h->{HELPER}{drawByValve} = { 1 => 12 };
    Gartenbewaesserung_LearnWateringFlow($h);
    is(rd("valve1Flow_lpm"), "13.7", "ein plausibler Lauf lernt weiterhin");
}

scenario("FF disable nimmt dem Modul nicht dauerhaft den Takt (v1.0.82)");
{
    # CheckSchedule loeschte seinen Timer, BEVOR es bei disable/manualMode
    # ausstieg - neu armiert wird nur in Define und StopAll. Ein einziges
    # "attr bw disable 1" hat den Minutentakt damit fuer immer erledigt, und mit
    # ihm MainsFillTick, MainsMeterTick und MainsFillIbcTick. Ein "disable 0"
    # holte nichts zurueck, und gemeldet wurde es nirgends.
    my $h = build(mains => "on");
    Gartenbewaesserung_SetBarrelLevel($h, 0, "test", 1);
    main::advance(120);
    my $vorher = rd("mainsDirect_total_l");
    ok_true($vorher > 0, "der Zaehler laeuft ueberhaupt (ist: $vorher)");

    $attr{bw}{disable} = 1;
    main::advance(300);
    is(rd("mainsDirect_total_l"), $vorher, "abgeschaltet zaehlt nichts weiter");

    delete $attr{bw}{disable};
    main::advance(600);
    my $nachher = rd("mainsDirect_total_l");
    ok_true($nachher > $vorher,
            "nach dem Einschalten laeuft der Takt wieder (ist: $nachher)");
}

scenario("GG Verregneter Pumpenlauf lernt keine Rate (v1.0.83)");
{
    # Der Fall vom 31.08.: waehrend der sieben Minuten Ernte regnete es weiter
    # (harvest_today_l 100,6 -> 237,9). Die Pumpe bewegte damit mehr als das
    # bekannte Fassmass, und die Rate kam zu NIEDRIG heraus - 35,4 fiel auf 32,5
    # und sah nach einem zusetzenden Filter aus.
    my $h = build(attr => { rainAmountDevice => "sens:regen_mm",
                            roofArea => 45, runoffCoefficient => 0.8 });
    main::readingsSingleUpdate($h, ".rainAccum", 10.0, 0);
    sens("barrelFull", "yes");                        # voll -> Ernte von Hand
    Gartenbewaesserung_StartIBCFill($h, 1);
    # 5 min: lang genug, dass der Durchsatz-Deckel aus v1.0.80 NICHT greift -
    # sonst prueft das Szenario den alten Deckel statt der neuen Regel.
    main::advance(300);
    main::readingsSingleUpdate($h, ".rainAccum", 13.8, 0);   # 3,8 mm = 137 l
    sens("barrelEmpty", "yes");

    is(rd("ibcFillFlow_lpm"), "34.2", "Rate bleibt stehen statt auf 32,8 zu fallen");
    ok_true(rd("lastIbcFillVolume_l") ne "(fehlt)", "gebucht wird der Lauf trotzdem");
}

scenario("HH Ohne Regen lernt derselbe Lauf weiterhin (v1.0.83)");
{
    # Gegenprobe zu GG - ohne sie waere das Veto eine Verschlimmbesserung.
    my $h = build(attr => { rainAmountDevice => "sens:regen_mm",
                            roofArea => 45, runoffCoefficient => 0.8 });
    main::readingsSingleUpdate($h, ".rainAccum", 10.0, 0);
    sens("barrelFull", "yes");
    Gartenbewaesserung_StartIBCFill($h, 1);
    main::advance(300);
    sens("barrelEmpty", "yes");                       # kein Regen dazwischen

    ok_true(rd("ibcFillFlow_lpm") != 34.2,
            "Rate lernt (ist: " . rd("ibcFillFlow_lpm") . ")");
}

scenario("II Kalibrierlauf verweigert bei offenem Hahn (v1.0.83)");
{
    # Bei offenem Hahn speist das Schwimmerventil beide Richtungen mit - das
    # Ergebnis waere ein Modell statt einer Messung.
    my $h = build(mains => "on");
    Gartenbewaesserung_SetIbcLevel($h, 500, "test", 1);
    my $err = Gartenbewaesserung_CalibrateStart($h);
    ok_true(!!(defined($err) && $err =~ /mains tap/), "abgelehnt (: " . ($err // "undef") . ")");
    is(relay("POWER8"), "OFF", "und nichts laeuft an");
    is(rd("calibration"), "(fehlt)", "kein Lauf vermerkt");
}

scenario("JJ Kalibrierlauf misst beide Raten in drei Phasen (v1.0.83)");
{
    my $h = build();
    Gartenbewaesserung_SetIbcLevel($h, 500, "test", 1);
    Gartenbewaesserung_SetBarrelLevel($h, 81, "test", 1);

    ok_true(!defined(Gartenbewaesserung_CalibrateStart($h)), "Lauf startet ohne Fehler");
    main::advance(10);                                # pumpStartDelay abwarten
    is(relay("POWER8"), "ON", "Phase 0: Pumpe laeuft");

    main::advance(160);
    sens("barrelEmpty", "yes");                       # Fass leer
    main::advance(20);                                # Tick schaltet weiter
    is(relay("POWER5"), "ON", "Phase 1: Transferventil offen");
    sens("barrelEmpty", "no");                        # Wasser steigt, Kontakt frei

    main::advance(600);                               # 10 min Schwerkraft
    sens("barrelFull", "yes");
    main::advance(20);                                # Tick startet Phase 2 (sieht fromFull)
    sens("barrelFull", "no");                         # Pegel faellt wieder
    is(relay("POWER8"), "ON", "Phase 2: Pumpe laeuft wieder");

    main::advance(280);
    sens("barrelEmpty", "yes");
    main::advance(20);

    is(rd("calibration"), "idle", "Lauf beendet");
    is(rd("calibrationResult"), "ok", "als geglueckt vermerkt");
    ok_true(rd("calibrationGravityFlow_lpm") ne "(fehlt)",
            "Schwerkraftrate gemessen (ist: " . rd("calibrationGravityFlow_lpm") . ")");
    ok_true(rd("calibrationPumpFlow_lpm") ne "(fehlt)",
            "Pumpenrate gemessen (ist: " . rd("calibrationPumpFlow_lpm") . ")");
    ok_true(!!(rd("calibrationFilter") =~ /%/),
            "Filteraussage dabei (ist: " . rd("calibrationFilter") . ")");
}

scenario("KK Regen waehrend des Kalibrierlaufs bricht ab (v1.0.83)");
{
    my $h = build(attr => { rainAmountDevice => "sens:regen_mm",
                            roofArea => 45, runoffCoefficient => 0.8 });
    main::readingsSingleUpdate($h, ".rainAccum", 10.0, 0);
    Gartenbewaesserung_SetIbcLevel($h, 500, "test", 1);
    Gartenbewaesserung_SetBarrelLevel($h, 81, "test", 1);
    ok_true(!defined(Gartenbewaesserung_CalibrateStart($h)), "Lauf startet ohne Fehler");

    main::advance(30);
    main::readingsSingleUpdate($h, ".rainAccum", 10.5, 0);   # 0,5 mm = 18 l
    main::advance(20);

    ok_true(!!(rd("calibrationResult") =~ /aborted/),
            "Regen bricht ab (: " . rd("calibrationResult") . ")");
    is(relay("POWER8"), "OFF", "Pumpe aus");
    is(rd("calibration"), "idle", "Zustand aufgeraeumt");
}

scenario("LL Vorschau: Bedarf, Vorrat und Deckung (v1.0.84)");
{
    # Raten der Testanlage, nicht die der echten Anlage:
    # 10 x 18,5 + 20 x 14,2 + 11 x 15 = 185 + 284 + 165 = 634 l
    my $h = build();
    Gartenbewaesserung_SetIbcLevel($h, 500, "test", 1);
    Gartenbewaesserung_SetBarrelLevel($h, 100, "test", 1);
    main::advance(70);                                # ein Minutentakt

    is(rd("cycleWaterNeeded_l"), 634, "Bedarf aus Dauer x Rate je Kreis");
    is(rd("cycleWaterAvailable_l"), 600, "Vorrat = IBC + Fass");
    is(rd("cycleCoverage_pct"), 95, "Deckung 600/634 = 95 %");

    # Der gelernte Wert schlaegt das Attribut - dieselbe Reihenfolge wie bei
    # der Buchung, sonst rechnete die Vorschau mit anderen Zahlen als das Modul.
    main::readingsSingleUpdate($h, "valve1Flow_lpm", 30, 0);
    main::advance(70);
    is(rd("cycleWaterNeeded_l"), 749, "gelernte Rate 30 statt Attribut 18,5 (+115 l)");
}

scenario("MM Unterbrochener Lauf verfaellt statt Stunden spaeter anzulaufen (v1.0.84)");
{
    # Der Fall: Hahn zu, IBC leer. Das Modul merkt sich den Rest und wartet auf
    # Wasser - bei zugedrehtem Hahn hebt aber nur Regen die barrelEmpty-Sperre
    # auf. Kommt der zwei Tage spaeter mittags, liefe die Nachtbewaesserung
    # dann an. Nach barrelEmptyResumeMaxAge wird stattdessen verworfen.
    my $h = build(attr => { barrelEmptyResumeMaxAge => 6 });
    sens("barrelFull", "yes");
    Gartenbewaesserung_StartWatering($h);
    main::advance(120);
    is(rd("currentValve"), 1, "Kreis 1 laeuft");

    sens("barrelEmpty", "yes");                       # Wasser ist alle
    ok_true($h->{HELPER}{barrelEmptyResumePending}, "Rest ist gemerkt");

    main::advance(7 * 3600);                          # sieben Stunden spaeter
    sens("barrelEmpty", "no");                        # jetzt kaeme Wasser
    my $st = Gartenbewaesserung_ResumeAfterBarrelEmpty($h);

    is($st, "expired", "Lauf ist verfallen");
    main::advance(10);                                # Resume oeffnet erst nach 2 s
    is(relay("POWER1"), "OFF", "und Kreis 1 laeuft NICHT wieder an");
    ok_true(rd("lastCycleAborted") ne "(fehlt)", "als verfallen protokolliert");
}

scenario("NN Innerhalb der Frist wird weiterhin fortgesetzt (v1.0.84)");
{
    # Gegenprobe zu MM - ohne sie waere das Verfallsdatum eine
    # Verschlimmbesserung: der normale Fall ist eine Pause von Minuten.
    my $h = build(attr => { barrelEmptyResumeMaxAge => 6 });
    sens("barrelFull", "yes");
    Gartenbewaesserung_StartWatering($h);
    main::advance(120);
    sens("barrelEmpty", "yes");

    main::advance(600);                               # zehn Minuten
    sens("barrelEmpty", "no");
    my $st = Gartenbewaesserung_ResumeAfterBarrelEmpty($h);

    ok_true($st eq "resumed" || $st eq "none",
            "kein Verfall nach zehn Minuten (ist: $st)");
    ok_true(rd("lastCycleAborted") eq "(fehlt)", "nichts als verfallen vermerkt");
}

scenario("OO Rotation dreht den Startkreis weiter (v1.0.84)");
{
    # Ohne Rotation trifft ein Wassermangel immer dieselben hinteren Kreise.
    my $h = build(attr => { rotateCircuits => 1 });
    sens("barrelFull", "yes");

    my @start;
    for my $runde (1 .. 4) {
        Gartenbewaesserung_StartWatering($h);
        push @start, rd("cycleFirstValve");
        Gartenbewaesserung_StopAll($h);
        main::advance(5);
    }
    is(join(",", @start), "1,2,3,1", "Startkreis wandert 1 -> 2 -> 3 -> 1");
}

scenario("PP Ohne rotateCircuits bleibt die Reihenfolge fest (v1.0.84)");
{
    my $h = build();                                  # Attribut nicht gesetzt
    sens("barrelFull", "yes");

    my @start;
    for my $runde (1 .. 3) {
        Gartenbewaesserung_StartWatering($h);
        push @start, rd("cycleFirstValve");
        Gartenbewaesserung_StopAll($h);
        main::advance(5);
    }
    is(join(",", @start), "1,1,1", "immer Kreis 1, altes Verhalten unveraendert");
}

scenario("QQ Kalibrierlauf meldet die Messung, nicht den Mittelwert (v1.0.85)");
{
    # Der Fall vom 31.08.: gemessen 148 l in 4,8 min = 30,8 l/min, im Reading
    # stand danach 31,6 - die gedaempfte Mischung 0,7 x alt + 0,3 x neu. Ein
    # Kalibrierlauf verschluckte damit 70 % seiner eigenen Neuigkeit, und die
    # Filteraussage haengt daran. Hier auf die Spitze getrieben: das Reading
    # steht auf 50, die Messung liegt bei gut 30.
    my $h = build();
    main::readingsSingleUpdate($h, "ibcFillFlow_lpm", 50, 0);
    Gartenbewaesserung_SetIbcLevel($h, 500, "test", 1);
    Gartenbewaesserung_SetBarrelLevel($h, 81, "test", 1);
    Gartenbewaesserung_CalibrateStart($h);

    main::advance(170);
    sens("barrelEmpty", "yes");
    main::advance(20);
    sens("barrelEmpty", "no");
    main::advance(600);
    sens("barrelFull", "yes");
    main::advance(20);
    sens("barrelFull", "no");
    main::advance(280);
    sens("barrelEmpty", "yes");
    main::advance(20);

    my $gemessen = rd("calibrationPumpFlow_lpm");
    ok_true($gemessen >= 28 && $gemessen <= 33,
            "gemeldet wird die Messung ~30, nicht der Mittelwert 44 (ist: $gemessen)");
    ok_true(rd("ibcFillFlow_lpm") > 40,
            "das gelernte Reading bleibt gedaempft (ist: " . rd("ibcFillFlow_lpm") . ")");

    # 30 von 34,2 sind 88 % - unter der neuen Schwelle 93, ueber der alten 85.
    ok_true(!!(rd("calibrationFilter") =~ /check the filter/),
            "Filter wird angemahnt (ist: " . rd("calibrationFilter") . ")");
    ok_true(rd("calibrationGravityAtIbc_l") ne "(fehlt)",
            "IBC-Stand zur Schwerkraftmessung dabei (ist: "
            . rd("calibrationGravityAtIbc_l") . ")");
}

scenario("RR Ein sauberer Filter wird nicht angemahnt (v1.0.85)");
{
    # Gegenprobe zu QQ: bei einer Rate auf Nennhoehe darf nichts gemeldet
    # werden, sonst waere die schaerfere Schwelle nur ein Dauerwarner.
    my $h = build();
    Gartenbewaesserung_SetIbcLevel($h, 500, "test", 1);
    Gartenbewaesserung_SetBarrelLevel($h, 81, "test", 1);
    Gartenbewaesserung_CalibrateStart($h);

    main::advance(170);
    sens("barrelEmpty", "yes");
    main::advance(20);
    sens("barrelEmpty", "no");
    main::advance(600);
    sens("barrelFull", "yes");
    main::advance(20);
    sens("barrelFull", "no");
    main::advance(245);                               # ~4,4 min -> rund 34 l/min
    sens("barrelEmpty", "yes");
    main::advance(20);

    ok_true(!!(rd("calibrationFilter") =~ /- ok$/),
            "kein Fehlalarm (ist: " . rd("calibrationFilter") . ")");
}

scenario("SS Regen waehrend der Ernte wird mitgebucht (v1.0.86)");
{
    # Der Lauf vom 31.08. 14:14-14:21: volles Fass, 7 Minuten Pumpe, und es
    # regnete durch. Gebucht wurden 148 (Fassmass), obwohl die Pumpe in der Zeit
    # rund 217 l bewegt hat - das Regenwasser lief waehrend des Pumpens nach.
    # Die Differenz fehlte dem IBC und summierte sich ueber Tage auf.
    my $h = build(attr => { rainAmountDevice => "sens:regen_mm",
                            roofArea => 45, runoffCoefficient => 0.8 });
    main::readingsSingleUpdate($h, ".rainAccum", 10.0, 0);
    Gartenbewaesserung_SetIbcLevel($h, 100, "test", 1);
    sens("barrelFull", "yes");
    Gartenbewaesserung_StartIBCFill($h, 1);
    main::advance(420);                               # 7 min
    main::readingsSingleUpdate($h, ".rainAccum", 13.8, 0);   # 3,8 mm = 137 l
    sens("barrelEmpty", "yes");

    # 34,2 l/min x 7 min = 239 l Pumpenkapazitaet; 148 + 137 = 285 waeren zu
    # viel, gedeckelt wird auf die Kapazitaet.
    my $g = rd("lastIbcFillVolume_l");
    ok_true($g > 148, "mehr als das blosse Fassmass gebucht (ist: $g)");
    ok_true($g <= 240, "aber nie mehr als die Pumpe schafft (ist: $g)");
    is(rd("ibcFillFlow_lpm"), "34.2", "gelernt wird aus dem Lauf weiterhin nichts");
}

scenario("TT Ohne Regen bleibt die Buchung auf dem Fassmass (v1.0.86)");
{
    # Gegenprobe zu SS: ohne Regen darf sich an der Buchung nichts aendern,
    # sonst schreibt der Fix dem IBC Wasser gut, das es nicht gab.
    my $h = build(attr => { rainAmountDevice => "sens:regen_mm",
                            roofArea => 45, runoffCoefficient => 0.8 });
    main::readingsSingleUpdate($h, ".rainAccum", 10.0, 0);
    Gartenbewaesserung_SetIbcLevel($h, 100, "test", 1);
    sens("barrelFull", "yes");
    Gartenbewaesserung_StartIBCFill($h, 1);
    main::advance(300);
    sens("barrelEmpty", "yes");                       # kein Regen dazwischen

    is(rd("lastIbcFillVolume_l"), 148, "genau das Fassmass, kein Zuschlag");
}

scenario("UU Transfer ohne barrelFull nach voller erlaubter Zeit meldet IBC leer (v1.0.87)");
{
    # barrelFillTimeout 0: die alte Uhr ist AUS. Kommt der Alarm trotzdem, dann
    # aus dem Transferende - genau da soll er herkommen. Auf v1.0.86 bleibt er
    # ohne die Uhr stumm.
    my $h = build(attr => { barrelFillTimeout => 0, ibcToBarrelDuration => 14 });
    Gartenbewaesserung_SetIbcLevel($h, 30, "test", 1);   # IBC praktisch leer
    Gartenbewaesserung_SetBarrelLevel($h, 0, "test", 1);
    is(rd("barrelFillTimeoutAlert"), "no", "vorher kein Alarm");

    Gartenbewaesserung_StartIBCtoBarrel($h);
    main::advance(14 * 60 + 40);                      # Deckel erreicht, kein Kontakt

    is(relay("POWER5"), "OFF", "Deckel hat zugemacht");
    is(rd("barrelFillTimeoutAlert"), "yes", "Alarm aus dem Transferende, ohne eigene Uhr");
}

scenario("VV Kein Alarm bei Kontakt oder vorzeitigem Stopp (v1.0.87)");
{
    # Gegenprobe: ein Transfer, der den Kontakt erreicht, und einer, der vor
    # Ablauf der erlaubten Zeit von Hand endet, sind beide kein Befund.
    my $h = build(attr => { barrelFillTimeout => 0, ibcToBarrelDuration => 14 });
    Gartenbewaesserung_SetIbcLevel($h, 500, "test", 1);
    Gartenbewaesserung_SetBarrelLevel($h, 0, "test", 1);

    Gartenbewaesserung_StartIBCtoBarrel($h);
    main::advance(600);
    sens("barrelFull", "yes");
    is(rd("barrelFillTimeoutAlert"), "no", "Kontakt kam nach 10 min: kein Alarm");

    sens("barrelFull", "no");
    Gartenbewaesserung_StartIBCtoBarrel($h);
    main::advance(120);
    Gartenbewaesserung_StopIBCtoBarrel($h, "manual");
    is(rd("barrelFillTimeoutAlert"), "no", "nach 2 min von Hand gestoppt: kein Befund");
}

scenario("WW validate prueft Physik < Deckel < Alarm (v1.0.87)");
{
    # Die Konfiguration vom 29.08.: Timeout 12 unter einem Deckel von 14.
    my $h = build(attr => { barrelFillTimeout => 12, ibcToBarrelDuration => 14 });
    my $r = Gartenbewaesserung_ValidateConfig($h);
    ok_true(!!($r =~ /barrelFillTimeout \(12 min\) is not above ibcToBarrelDuration/),
            "Timeout unter dem Deckel wird angemahnt");

    # Ohne Timeout: dazu keine Zeile. Der Deckel 14 gegen 148/12,2 = 12,1 min
    # ist knapp und wird zu Recht angemahnt - das ist eine andere Meldung.
    my $h2 = build(attr => { barrelFillTimeout => 0, ibcToBarrelDuration => 14 });
    my $r2 = Gartenbewaesserung_ValidateConfig($h2);
    ok_true(!!($r2 !~ /barrelFillTimeout/), "ohne Timeout keine Meldung dazu");
    ok_true(!!($r2 =~ /ibcToBarrelDuration \(14 min\) leaves little room/),
            "Deckel zu knapp ueber der Physik wird angemahnt");

    # Deckel 20 gegen 12,1 min Bedarf: in Ordnung, keine Warnung dazu.
    my $h3 = build(attr => { barrelFillTimeout => 0, ibcToBarrelDuration => 20 });
    my $r3 = Gartenbewaesserung_ValidateConfig($h3);
    ok_true(!!($r3 !~ /leaves little room/), "Deckel 20 ist nicht knapp");
}

print "\n";
printf("%d ok, %d fehlgeschlagen\n", $ok, $fail);
exit($fail ? 1 : 0);
