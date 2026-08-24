##############################################################################
#
#     98_Gartenbewaesserung.pm
#
#     FHEM Modul für intelligente Gartenbewässerung mit IBC-Container
#     Die laufende Version ist der oberste Eintrag der Änderungsliste unten;
#     Gartenbewaesserung_Version() liest sie von dort. Hier stand sie früher
#     zusätzlich, und war zuletzt 28 Versionen alt.
#
#     Unterstützt MQTT2 Relay Boards (z.B. Tasmota)
#     Dynamische Werte-Erkennung (on/off, true/false, 1/0, etc.)
#     Automatische Füll-Pausen während Bewässerung
#
##############################################################################
#
# 1.0.75 - 2026-08-24  Fix: der Nachkommaanteil ging bei JEDER Buchung verloren,
#                      nicht nur beim Stadtwasser-Zulauf.
#                      v1.0.73 hat das Symptom an einer Stelle behoben (Anker in
#                      MainsFillTick), die Ursache lag aber tiefer: SetBarrelLevel
#                      speichert ganze Liter, und AdjustBarrelLevel rechnet vom
#                      GERUNDETEN Reading weiter. Jede wiederholte kleine Buchung
#                      verliert damit ihren Bruchteil, und zwar systematisch in
#                      dieselbe Richtung, weil der Bruchteil bei gleichartigen
#                      Schritten immer gleich ist. Zweiter Betroffener: der Regen.
#                      Bei roofArea 45 und runoffCoefficient 0.8 sind das 36 l je
#                      mm; ein 0,2-mm-Kipp der Wippe bringt 7,2 l und wurde als 7
#                      gebucht - 0,2 l je Kipp, ueber 10 mm Regen rund 10 l oder
#                      knapp 3 % der Ernte, immer zu wenig.
#                      Jetzt liegt der Rest in den versteckten Readings
#                      .barrelLevelFrac / .ibcLevelFrac und geht in die naechste
#                      Buchung ein. Die sichtbaren Readings bleiben ganzzahlig.
#                      MainsFillTick liest den Stand seitdem exakt (neue Funktion
#                      BarrelLevelExact), sonst zaehlte sein Anker doppelt.
#                      Ausserdem: die Version wird nicht mehr von Hand gepflegt.
#                      $hash->{VERSION} stand fest verdrahtet auf 1.0.73, die
#                      Zeile im Dateikopf auf 1.0.47 - beide waren beim Anheben
#                      vergessen worden, die commandref warnt seit laengerem
#                      genau davor ("eine Zahl, die nicht mitwaechst, ist
#                      schlimmer als keine"). Gartenbewaesserung_Version() liest
#                      sie jetzt aus dem obersten Eintrag dieser Liste, die
#                      ohnehin bei jeder Aenderung gepflegt wird. Der
#                      Rueckfallwert $FALLBACK greift nur, wenn die Datei nicht
#                      lesbar ist; dass er zur Liste passt, prueft t/cref.py.
#
# 1.0.74 - 2026-08-24  Gemessen wird am Fass, gerechnet nur noch als Rueckfall.
#                      Jeder Durchfluss im System ist veraenderlich: die Schwerkraft
#                      IBC->Fass haengt am Fuellstand, Pumpe und Gieszkreise am
#                      Verschmutzungsgrad des Filters. Fest ist allein, was ins Fass
#                      passt. Daraus zwei Aenderungen.
#                      (a) Dritter Messfall: eine Stadtwasser-Runde laeuft von der
#                      Schwimmerhoehe bis zum Trockenlauf und bewegt damit ebenfalls
#                      eine BEKANNTE Menge - barrelFloatLevel, am Wasserzaehler
#                      gemessen. Sie lernt jetzt die Pumpenrate mit. Vorher konnte das
#                      nur ein Lauf aus dem vollen Fass, und der braucht Regen: die
#                      Rate stand deshalb fuenf Tage lang auf 34,2 l/min, waehrend die
#                      Pumpe real nur noch 30,3 schaffte (verschmutzter Filter). Jede
#                      Runde wurde dadurch um rund 11 l zu hoch gebucht.
#                      (b) Ratenbasierte Buchungen werden am Fassmass gedeckelt. Ein
#                      Transfer ins Fass kann nie mehr bewegen, als ins Fass passt -
#                      in der Nacht zum 24.08. wurden dreimal 255 l in ein 148-l-Fass
#                      gebucht, weil 20,1 min mit der (veralteten) Rate multipliziert
#                      wurden. Fuer die Grafik bleiben die Raten unveraendert nutzbar,
#                      auch bei unvollstaendigen Laeufen; nur die Buchhaltung haengt
#                      jetzt an den Kontakten.
#
# 1.0.73 - 2026-08-23  Fix: MainsFillTick verlor je Minute den Nachkommaanteil.
#                      Der Ticker addierte je Takt "rate * 60 s" und rueckte seinen
#                      Startpunkt vor. SetBarrelLevel speichert aber ganze Liter, und
#                      AdjustBarrelLevel rechnet vom GERUNDETEN Reading weiter - bei
#                      4,4 l/min gingen damit jede Minute 0,4 l verloren. Im Log gut zu
#                      sehen: der Pegel stieg in exakten 4er-Schritten (36, 40, 44 ...)
#                      statt 4,4. Folge: das Fass galt rund zwei Minuten zu spaet als
#                      voll, jeder mainsFillIbc-Zyklus dauerte entsprechend laenger.
#                      Jetzt wird gegen einen Anker gerechnet (Zeitpunkt + Pegel beim
#                      Start), der Rundungsfehler haeuft sich also nicht mehr an,
#                      sondern bleibt bei hoechstens einem halben Liter.
#
# 1.0.72 - 2026-08-23  Doku: wann wateringPauseInterval ueberhaupt gebraucht wird.
#                      Der einzige Zweck ist, die Pumpe abzuschalten, BEVOR das Fass
#                      leerlaeuft. Schuetzt sich die Pumpe selbst (Tauchpumpe mit
#                      Schwimmer, oder ein echter Leer-Kontakt als
#                      barrelEmptySensorDevice), gehoert das Attribut auf 0 - dann
#                      uebernimmt barrelEmpty, und Giesszeit geht dabei nicht verloren,
#                      weil die Restminuten gesichert und fortgesetzt werden.
#                      Dazu der Hinweis, dass ein fester Wert grob wird, sobald sich die
#                      Kreise im Durchfluss unterscheiden: er muss auf den durstigsten
#                      passen und unterbricht alle anderen zu frueh.
#
# 1.0.71 - 2026-08-23  Fix: Abpumpen ins IBC entwertet den Lauf fuer die Giessraten.
#                      drawTainted markierte bisher nur Wasser, das DAZUKOMMT. Die
#                      Pumpe Fass->IBC ist der einzige Weg, auf dem Wasser ANDERS
#                      abgeht als durch ein Ventil - und LearnWateringFlow rechnet
#                      stur das ganze Fassvolumen der Ventilzeit zu.
#                      Am 23.08.: Kreis 3 lief 11 min und verbrauchte 78 l, danach
#                      hob die Pumpe die restlichen 70 l in den IBC. Gelernt wurden
#                      148/11 = 13,5 l/min statt der tatsaechlichen 7,1 - Faktor
#                      knapp zwei daneben, und der falsche Wert stand danach im
#                      Reading.
#                      Jetzt wird aus so einem Lauf gar nichts gelernt statt etwas
#                      Falsches. Die Foerderrate der Pumpe bleibt unberuehrt:
#                      RecordIbcFillRun lernt ueber $complete (voll -> leer, ohne
#                      Stadtwasser) und liest drawTainted nirgends.
#
# 1.0.70 - 2026-08-23  Fix: drei von vier Wegen IBC->Fass wurden nie abgerechnet.
#                      Nur die Giess-Pause rief Start UND Stop. Es fehlten:
#                      NoteIbcToBarrelStart in StartIBCtoBarrel (beide Zweige) und in
#                      HandleBarrelEmpty, NoteIbcToBarrelStop in EndCircuitPause.
#                      Folge: kein lastIbcToBarrel*, keine Buchung auf ibcLevel_l und
#                      barrelLevel_l, keine gelernte Schwerkraftrate - und der Waechter
#                      aus v1.0.62 wurde nicht scharf, weil er in NoteIbcToBarrelStart
#                      armiert wird. Am 23.08. lief ein manueller Transfer von 7 min
#                      voellig unbemerkt: ibcLevel_l stand danach unveraendert auf 390.
#                      Der Stop sitzt jetzt zentral in StopIBCtoBarrel, damit auch der
#                      eigene Dauer-Timer und "set stopIBCtoBarrel" abrechnen.
#
# 1.0.69 - 2026-08-23  Fix: Foerderraten fallen auf das gleichnamige Attribut zurueck.
#                      ibcFillFlow_lpm und ibcToBarrelFlow_lpm wurden nur als Reading
#                      gelesen. Gelernt werden sie aber nur aus vollstaendigen Laeufen,
#                      und ein Statefile-Rueckfall kostet sie wieder - am 23.08. war
#                      ibcToBarrelFlow_lpm schlicht weg. Folge: das Modul rechnet die
#                      Fuellstaende waehrend eines Transports nicht mit, und die
#                      watertank-Kachel steht still, obwohl das Rohr leuchtet.
#                      Neu FlowRate(): Reading zuerst, dann Attribut - dieselbe
#                      Reihenfolge wie bei wateringFlow_lpm und valve<N>Flow_lpm, die
#                      das laengst so machen. Beide Namen sind jetzt in der AttrList.
#
# 1.0.68 - 2026-08-23  Fix: nach einem Neustart liefen Pumpe und Ventil weiter, ohne
#                      dass noch jemand zusieht.
#                      HELPER ist Arbeitsspeicher - nach dem Neustart weiss das Modul
#                      von nichts mehr, die Aktoren bleiben aber an. Damit sind BEIDE
#                      Sicherungen weg: der Pumpen-Watchdog (pumpMaxRuntime) lebt in
#                      HELPER, ein per defmod angelegtes Timeout-at ueberlebt den
#                      Neustart ebenfalls nicht. Am 23.08. lief die Pumpe deshalb nach
#                      einem Update-Neustart rund zehn Minuten trocken.
#                      Neu AdoptOrStopOrphans, gerufen 5 s nach dem Define (im Define
#                      selbst ist der Statefile noch nicht angewendet, die
#                      Geraete-Readings waeren leer): schaltet alles ab, was noch laeuft,
#                      und schreibt das Reading orphanShutdown.
#                      Bewusst abschalten statt uebernehmen - das Modul kann nach dem
#                      Start nicht wissen, ob im Fass noch Wasser steht. Ein
#                      abgebrochener Lauf laesst sich neu starten, eine trockengelaufene
#                      Pumpe nicht reparieren. Nur eine laufende IBC-Befuellung geht
#                      ueber StopIBCFill, damit das gefoerderte Volumen noch verbucht
#                      wird; abgeschaltet wird sie genauso.
#
# 1.0.67 - 2026-08-23  Doku: veraltete Versionsangabe aus der commandref entfernt.
#                      Dort stand fest verdrahtet "Version: 1.0.28", also 38 Versionen
#                      zu alt. Statt sie zu pflegen faellt sie weg - massgeblich sind
#                      das Internal VERSION und "get <name> version".
#                      Dazu t/cref.py: prueft die Set-/Get-Liste aus dem Quelltext gegen
#                      die commandref-Anker, in beide Richtungen. Vorlage fuer die
#                      Ankerform war 98_PoolControl.pm aus dem Repo FHEM-Pool, das
#                      dieselbe Konvention benutzt.
#
# 1.0.66 - 2026-08-23  Doku: Anker fuer jeden Set- und Get-Befehl in der commandref.
#                      FHEMWEB blendet zu einem im Dropdown gewaehlten Befehl den
#                      passenden Absatz ein, wenn dort <a id="<TYPE>-set-<befehl>">
#                      steht. Die 64 Attribute hatten ihre Anker laengst
#                      (<a id="Gartenbewaesserung-attr-...">), die 17 Set- und drei
#                      Get-Befehle nicht - dort blieb das Hilfefeld leer.
#                      Beim Setzen gegengeprueft: Set-Liste aus dem Quelltext gegen die
#                      commandref. Keine Luecke in beide Richtungen, alle 17 sind
#                      dokumentiert und es gibt keinen Eintrag ohne Befehl.
#                      Reine Dokumentation, kein Verhalten geaendert.
#
# 1.0.65 - 2026-08-23  Fix: Endlosrekursion, wenn der Fuellstand unter
#                      barrelFillThreshold liegt und kein barrelFillValveDevice
#                      konfiguriert ist.
#                      NextValve sah den niedrigen Stand und rief FillBarrel, FillBarrel
#                      fand kein Ventil und rief NextValve - ohne den Index zu erhoehen
#                      und ohne Timer dazwischen. Die Kette lief damit in derselben
#                      Sekunde tausendfach durch und blockierte FHEM komplett; im Log
#                      stehen "Barrel level low, filling before valve 2" und "No barrel
#                      fill valve configured" abwechselnd mit identischem Zeitstempel.
#                      Der Kreis-Modus machte es schon richtig: FillBarrelForCircuit ruft
#                      ohne Ventil RunCircuit, also den Verbraucher, nicht den Verteiler.
#                      FillBarrel macht es jetzt genauso und oeffnet das anstehende
#                      Ventil direkt.
#                      Sofortmassnahme ohne Modul-Update: attr barrelFillThreshold 0 -
#                      der Zweig ist ohne Fuellventil ohnehin wirkungslos.
#
# 1.0.64 - 2026-08-22  Neu: set <name> mainsFillIbc <liter>|<prozent>%|stop - den IBC
#                      aus der Hauswasserleitung fuellen.
#                      Das Fass ist der Trichter: Schwimmerventil laesst bis
#                      barrelFloatLevel nach, Pumpe hebt es in den IBC, Ventil macht
#                      wieder auf. Eine Runde bringt rund barrelFloatLevel Liter in
#                      barrelFloatLevel/mainsFillFlow_lpm Minuten plus gut zwei Minuten
#                      Pumpen - gemessen 81 l in ~21 min, also ~260 l/h.
#                      Zweck ist NICHT, mit Leitungswasser zu giessen (mit 4,4 l/min
#                      koennte der Zulauf das gar nicht, ein Giesskreis zieht das
#                      Dreifache), sondern den Vorrat tagsueber aufzubauen, wenn das
#                      Schwimmerventil hoerbar sein darf, und ihn nachts leise zu
#                      verbrauchen.
#                      Ohne eigenes Ventil: der Hahn bleibt offen, das Schwimmerventil
#                      regelt, das Modul steuert nur die Pumpe. Kommt das Fass nicht auf
#                      Schwimmerhoehe, bricht der Waechter nach der doppelten erwarteten
#                      Nachlaufzeit ab statt endlos zu warten.
#                      Giessen hat Vorrang - der Auftrag setzt aus und laeuft danach
#                      weiter. Readings mainsFillIbcTarget/-Done/-State.
#                      Dabei mitgenommen: RecordIbcFillRun liefert das bewegte Volumen
#                      jetzt zurueck, statt dass der Aufrufer es aus lastIbcFillVolume_l
#                      liest. Bei einem der beiden fruehen returns stuende dort noch der
#                      Wert der VORIGEN Runde - der waere doppelt gebucht worden.
#
# 1.0.63 - 2026-08-22  Neu: attr mainsFillFlow_lpm - Leitungswasser-Zulauf mitrechnen.
#                      Bisher stand der Fuellstand waehrend einer Stadtwasser-Befuellung
#                      still: keiner der fuenf Buchungsanlaesse (Pumpe, IBC->Fass, Regen,
#                      Ventil, Anker) trifft zu. Der einzige Ansatz dafuer war
#                      ApplyBarrelFloatFloor, ein SPRUNG auf barrelFloatLevel - und der lief
#                      im Betrieb nie: aufgerufen wird er nur aus UpdateSensorReadings, und
#                      das passiert bloss beim Define, bei "set refreshSensors" und beim
#                      Aendern eines Sensor-Attributs. Am 22.08. war der einzige Lauf um
#                      11:26:01, da stand barrelEmpty noch auf yes und die Funktion stieg
#                      genau deswegen aus - der Fuellstand blieb 20 Minuten auf 0, waehrend
#                      real 81 l einliefen.
#                      Jetzt: MainsFillTick im 60-s-Takt aus CheckSchedule (der einzige
#                      Timer, der zuverlaessig laeuft). Mit gesetzter Rate steigt der Pegel
#                      mit, gedeckelt auf barrelFloatLevel - ueber ein Schwimmerventil steigt
#                      er nur bis zur Schwimmerhoehe, stur weiterzuzaehlen wuerde ein volles
#                      Fass vortaeuschen, das es nie gibt. Ohne Rate bleibt es beim Sprung,
#                      der damit aber erstmals ueberhaupt ausgefuehrt wird.
#                      Laeuft ein anderer Transport, ruht der Ticker - der hat seine eigene
#                      Buchhaltung, sonst zaehlte dasselbe Wasser zweimal.
#
# 1.0.62 - 2026-08-22  Fix: Nachlauf IBC -> Fass lief in ein volles Fass und entleerte
#                      den IBC ueber den Fassueberlauf.
#                      In der Nacht zum 22.08. stand das Ventil zweimal 20,0 min offen
#                      (lastIbcToBarrelEnd: pauseEnd) statt der sonst ueblichen
#                      0,2-12,1 min mit barrelFull. Rund 200 l gingen ungesehen ins
#                      Fallrohr, der IBC war danach leer und der Zyklus blieb bei 2/3
#                      stehen. Drei Fehler mussten dafuer zusammenkommen:
#                      1. Die Uhr fuer wateringPauseInterval mass WANDZEIT statt
#                         Giesszeit - ein Fass-leer-Nachfuellen setzte sie nicht zurueck.
#                         Nach 12 min Nachfuellen stand sie auf 19 von 8 Minuten, das
#                         Ventil bekam eine Laufzeit von NULL Minuten und stiess sofort
#                         die naechste Pause an. Jetzt setzen StopBarrelEmptyRefill und
#                         StopBarrelEmptyRefillPause lastPauseEnd.
#                      2. Die Pause wurde gestartet, ohne zu fragen, ob das Fass ueber-
#                         haupt Wasser braucht - es war voll. Neu: BarrelNeedsRefill;
#                         bei barrelFull entfaellt die Pause und der Kreis laeuft weiter.
#                         Das spart nebenbei 20 min Giesszeit je Fall.
#                      3. Geschlossen wurde nur beim EREIGNIS barrelFull. War das Fass
#                         beim Oeffnen schon voll, konnte dieses Ereignis nicht mehr
#                         kommen. Neu: IbcToBarrelWatchdog prueft den ZUSTAND (erst nach
#                         5 s, dann alle 30 s) und zieht ibcToBarrelDuration als harte
#                         Grenze ein - das Attribut galt bisher nur fuer die Ernte.
#                      Dazu die Lernfalle daneben: LearnWateringFlow lief, bevor ein noch
#                      offenes Ventil abgerechnet war. 148 l wurden durch 2 statt 6,8 min
#                      geteilt und dem falschen Kreis gutgeschrieben - valve1Flow_lpm 74
#                      l/min, obwohl Kreis 2 gelaufen war. NoteOpenValveDrawTime bucht die
#                      offene Ventilzeit jetzt vorher ein.
#
# 1.0.61 - 2026-08-19  Doku: die Luecken in der commandref geschlossen.
#                      Ein Abgleich von AttrList, Set-Liste und allen readings*Update-Aufrufen
#                      gegen die commandref ergab: die Set-Befehle sind vollstaendig, bei den
#                      Attributen fehlten mainsSupplyActiveValue/mainsSupplyInactiveValue, und
#                      18 Readings waren gar nicht beschrieben - darunter die Zustands-Readings,
#                      an denen man einen Lauf ueberhaupt erst mitlesen kann (phase, ibcFilling,
#                      ibcFillStarted, ibcToBarrelActive, pauseActive, cycleProgress, nextValve,
#                      remainingTime, barrelFull/barrelEmpty, ibcFull/ibcEmpty, raining,
#                      rainDetectedSince, soilMoisture, lastWatering, lastCircuitWatering).
#                      Nur Dokumentation, kein Verhalten geaendert.
#
# 1.0.60 - 2026-08-19  Neu: set <name> waterSource rain|other fuer Wasser, das nicht vom Dach kommt
#                      - Poolwasser ins Fass ablassen, Nachbars Regentonne umfuellen, was auch immer.
#                      Ohne das griff die Einstufung dreimal daneben: solches Wasser galt als
#                      'rain' und verunreinigte pumpedRain_total_l, ein volles Fass gab dem
#                      Sammel-Watchdog eine falsche Entwarnung (ein verstopftes Fallrohr waere
#                      unsichtbar geworden), und geerntet wurde es gar nicht erst, weil die Ernte
#                      auf rainSinceHarvest_mm wartet - das Fass waere schlicht stehen geblieben.
#                      Solange waterSource auf 'other' steht: Ernte startet allein bei vollem Fass,
#                      das Volumen zaehlt in pumpedOther_total_l, und barrelFull gilt nicht als
#                      Beleg fuer die Regensammlung. Endet von selbst beim naechsten barrelEmpty -
#                      dann ist das Fremdwasser oben und der Normalfall gilt wieder.
# 1.0.59 - 2026-08-19  Fix: Eine laufende Befuellung Fass->IBC war im state nicht zu sehen. Die
#                      Gegenrichtung setzt 'ibc to barrel', die Ernte setzte gar nichts - das Geraet
#                      stand waehrend des ganzen Laufs auf 'idle' und schrieb am Ende nochmal
#                      'idle'. Auf der FHEMWEB-Geraeteseite war der Lauf damit unsichtbar, sofern
#                      man nicht wusste, dass man auf ibcFilling schauen muss. Jetzt 'ibc filling',
#                      am Ende zurueck auf 'idle' - aber nur, wenn nicht gerade gegossen wird:
#                      StopIBCFill wird auch aus einer startenden Bewaesserung heraus gerufen.
# 1.0.58 - 2026-08-19  Fix: Ein Neustart oder Modul-Reload mitten in einer Befuellung liess den
#                      ganzen Lauf aus der Statistik fallen. Die Messung haengt an $hash->{HELPER},
#                      und das ist reiner Arbeitsspeicher - nach dem Reload wusste das Modul nicht
#                      mehr, dass gerade gefoerdert wird, und StopIBCFill stieg sofort wieder aus.
#                      Weder Dauer noch Volumen wurden geschrieben, pumped_total_l blieb stehen.
#                      Die Readings wissen es dagegen noch: ibcFilling und ibcFillStarted sind
#                      persistent. Daraus wird der Lauf jetzt wieder aufgenommen, sofern der
#                      Startzeitpunkt plausibel ist (nicht aelter als pumpMaxRuntime plus Reserve) -
#                      sonst wuerde ein stehengebliebenes Reading spaeter eine absurde Laufzeit
#                      buchen. Nachweis: 19.08. lief die Ernte von 09:57:47 bis 10:02:15, dazwischen
#                      um 09:59:54 ein Reload - 250 l Ertrag ohne jede Spur in den Zaehlern.
# 1.0.57 - 2026-08-19  Fix: Der Fass-leer-Refill aus dem IBC wurde nicht gemessen. Genau dieser
#                      Weg startet bei LEEREM Fass und endet auf barrelFull, bewegt also die
#                      bekannte barrelUsableVolume - er ist der einzige, aus dem sich
#                      ibcToBarrelFlow_lpm ueberhaupt lernen laesst. Der Aufruf fehlte auf beiden
#                      Seiten: NoteIbcToBarrelStop im ibcToBarrelActive-Zweig von CheckBarrelFull
#                      und beim Abbruch. Nachweis: 19.08. lief die Nachspeisung von 05:00:00 (Fass
#                      leer) bis 05:10:20 (barrelFull) - zehneinhalb Minuten fuer 250 l, rund
#                      24 l/min - und im Log steht dazu kein einziges Reading.
# 1.0.56 - 2026-08-19  Neu: Die Entnahmerate wird jetzt AUF DEN KREIS gelernt, wenn zwischen den
#                      beiden Ankern nur ein einziger Kreis gelaufen ist - dann steht das bewegte
#                      Volumen fest und gehoert eindeutig ihm. Ergebnis landet im Reading
#                      valve<N>Flow_lpm und hat Vorrang vor allem anderen. Waren mehrere Kreise
#                      beteiligt, bleibt es beim gemeinsamen wateringFlow_lpm wie bisher.
#                      Erreichbar ist das nur fuer Kreise, die ein volles Fass allein leerziehen;
#                      kuerzere schaffen das nicht und brauchen weiter das Attribut.
# 1.0.55 - 2026-08-19  Neu: Entnahmerate je Kreis - valve<N>Flow_lpm. Jeder Kreis hat andere
#                      Sprenger und nicht gleich viele, eine gemeinsame Rate ist deshalb bestenfalls
#                      ein Mittelwert. Die Reihenfolge ist jetzt: Rate des Kreises, dann die
#                      gelernte Gesamtrate, dann das Attribut wateringFlow_lpm, zuletzt der
#                      Pauschalabzug.
# 1.0.54 - 2026-08-19  Fix: Die Entnahme beim Giessen wurde mit einem Pauschalwert gebucht - 12 % der
#                      nutzbaren Kapazitaet je Ventil, UNABHAENGIG von der Laufzeit. Ein Ventil mit
#                      zwei Minuten kostete damit so viel wie eines mit zwanzig. In der Anlage des
#                      Autors: zwoelf Minuten Giessen zogen rund 115 l, gebucht wurden 30 - der
#                      Fass-Stand meldete danach 245 l, im Fass standen 135.
#                      Neues Attribut wateringFlow_lpm (Liter je Minute Ventil-Offenzeit). Damit
#                      wird nach Zeit gerechnet statt pauschal. Der gelernte Wert hat weiter Vorrang;
#                      ohne beides bleibt es beim alten Pauschalabzug, dann aber mit Log-Hinweis.
#                      Hintergrund: die Lernbedingung (volles Fass laeuft allein durchs Giessen bis
#                      barrelEmpty leer) ist nicht ueberall erreichbar - endet die Bewaesserung
#                      vorher, etwa auf Schwimmerhoehe, greift sie nie. Dann ist das Attribut der
#                      einzige Weg zu einer brauchbaren Zahl.
# 1.0.53 - 2026-08-18  Neu: set <name> barrelLevel <liter>|<prozent>% als Gegenstueck zu ibcLevel.
#                      Das Fass verankert sich zwar mehrmals taeglich von selbst an barrelFull oder
#                      barrelEmpty - bis der erste Kontakt kommt, hat die Schaetzung aber keinen
#                      Startwert und zeigt nichts. Beide Befehle teilen sich jetzt einen Parser und
#                      nehmen Liter oder Prozent.
# 1.0.52 - 2026-08-18  Neu: Attribut ibcFullFromLevel (0/1). Damit darf die Fuellstandsschaetzung
#                      selbst 'IBC voll' melden, statt dass der Voll-Zustand nur aus dem Sensor bzw.
#                      einem von Hand gesetzten Dummy kommt. Beim Start einer Befuellung rechnet das
#                      Modul aus dem freien Rest und der gelernten Foerderrate aus, wann der Behaelter
#                      voll ist, und stellt einen Wecker - der Lauf endet dann von selbst, statt
#                      ueberzulaufen. Faellt der Stand spaeter wieder unter die Kapazitaet, geht
#                      ibcFull von allein zurueck auf no.
#                      Wichtig: Die Schaetzung ist damit steuernd, nicht mehr nur beschreibend. Zu
#                      hoch geschaetzt heisst Regen verschenkt, zu niedrig heisst weiterhin
#                      Ueberlauf. Der Sensor bzw. der Dummy hat weiter Vorrang und verankert den
#                      Stand - er bleibt die Korrektur von aussen. Ohne das Attribut aendert sich
#                      nichts.
# 1.0.51 - 2026-08-18  Fix: Der Sammel-Watchdog schlug nach jeder erfolgreichen Ernte Alarm. Die
#                      Pruefung 'Fass ist voll geworden, also sammelt die Anlage' stand im
#                      barrelFull-Zweig NACH dem Start der Ernte - und die setzt ibcFilling auf yes.
#                      Der Waechter 'ibcFilling eq no' sah damit immer die Befuellung, die er selbst
#                      gerade ausgeloest hatte, und rainSinceFill_mm wurde nie zurueckgesetzt.
#                      Dasselbe galt fuer ibcToBarrelActive, das CheckBarrelFull vorher abraeumt.
#                      Beide Kennzeichen werden jetzt VOR der Verarbeitung festgehalten; zusaetzlich
#                      zaehlt eine laufende Fassbefuellung aus der Leitung nicht mehr als Beleg.
#                      Nachweis: 18.08., zwei Ernten um 08:58 und 10:21, rainSinceFill_mm lief
#                      trotzdem von 0,68 auf 6,30 mm durch und loeste um 12:26 den Alarm aus.
#                      Bewusst NICHT ergaenzt: der Wegfall des Fass-leer-Kontakts als zweites,
#                      frueheres Signal. barrelEmptySensorDevice ist haeufig kein Pegelschalter,
#                      sondern ein von einer Regel gefuellter Dummy - in der Anlage des Autors aus
#                      der Pumpenleistung abgeleitet und von einer Regel zurueckgesetzt, die auf
#                      REGEN reagiert. Das waere ein Zirkelschluss: Regen setzt das Reading zurueck,
#                      das zurueckgesetzte Reading belegt, dass der Regen gesammelt wurde - ein
#                      verstopftes Fallrohr fiele nie auf. Eine falsche Entwarnung ist schlimmer als
#                      ein Fehlalarm.
# 1.0.50 - 2026-08-18  Neu: Fuellstandsschaetzung fuer das Fass (barrelLevel_l, barrelLevelAnchor).
#                      Das Fass ist besser vermessen als der IBC - drei Ankerpunkte statt zwei:
#                      barrelFull -> barrelUsableVolume, barrelEmpty -> 0, und bei offener
#                      Hauswasserzufuhr haelt das Schwimmerventil barrelFloatLevel als Untergrenze,
#                      sobald der Leer-Kontakt frei ist und nichts entnimmt. Dazu Zu- und Abfluesse:
#                      Regen (mm x roofArea x runoffCoefficient), Rueckfluss aus dem IBC, Foerderung
#                      ins IBC und die Entnahme beim Giessen.
#                      Das bisherige barrelLevel war reine Simulation - Start bei 100, minus 12 je
#                      Ventil - und stand zuletzt auf 38 %, waehrend das Fass leer war. Es wird jetzt
#                      aus barrelLevel_l abgeleitet, sobald barrelUsableVolume gesetzt ist; ohne das
#                      Attribut bleibt die alte Simulation unveraendert. barrelFillThreshold liest
#                      weiterhin dasselbe Reading und arbeitet damit ohne Aenderung auf echten Zahlen.
#                      Die Entnahmerate beim Giessen wird gelernt (wateringFlow_lpm): laeuft ein
#                      volles Fass allein durch Giessen leer, entspricht die summierte Ventil-Offenzeit
#                      genau barrelUsableVolume. Bis dahin gelten die alten 12 % je Ventil.
# 1.0.49 - 2026-08-18  Neu: Fuellstandsschaetzung fuer den IBC. Neues Attribut ibcUsableVolume
#                      (Liter) und neue Readings ibcLevel_l, ibcLevel_pct, ibcLevelAnchor. Der IBC
#                      hat keinen Pegelgeber, nur zwei Endschalter - der Stand wird deshalb
#                      mitgefuehrt: was hochgepumpt wird kommt drauf, was per Schwerkraft
#                      zurueckfliesst geht ab. Weil beide Raten gelernte Mittelwerte sind, driftet
#                      das; jeder Ankerpunkt setzt es darum zurueck (ibcEmpty -> 0, ibcFull ->
#                      ibcUsableVolume, set <name> ibcLevel <liter> -> abgelesener Wert).
#                      ibcLevelAnchor haelt fest, woher der aktuelle Wert stammt. Die Rate der
#                      Schwerkraftrichtung wird analog zur Pumpe gelernt: ein Lauf IBC->Fass, der
#                      bei leerem Fass beginnt und mit barrelFull endet, hat barrelUsableVolume
#                      bewegt (neues Reading ibcToBarrelFlow_lpm, dazu lastIbcToBarrelVolume_l).
#                      Ohne ibcUsableVolume aendert sich nichts.
# 1.0.48 - 2026-08-18  Neu: Ein Lauf mit offener Hauswasserzufuhr wird nicht mehr komplett verworfen,
#                      sondern aufgeteilt. Neues Attribut barrelFloatLevel (Liter): Hoehe, auf der das
#                      Schwimmerventil das Fass haelt. Alles darueber ist Regen, alles darunter kam aus
#                      der Leitung - der Regenanteil eines Misch-Laufs ist damit konstant
#                      barrelUsableVolume - barrelFloatLevel, unabhaengig von der Laufzeit. Neue
#                      Readings lastIbcFillRain_l, lastIbcFillMains_l und mains_total_l;
#                      pumpedRain_total_l bekommt jetzt auch aus Misch-Laeufen seinen Anteil.
#                      Ausserdem Fix: die Foerderrate wird aus Misch-Laeufen nicht mehr gelernt. Dort
#                      laeuft waehrend des Pumpens Wasser nach, der Lauf dauert also laenger als
#                      barrelUsableVolume / Rate - die gelernte Rate fiel dadurch systematisch zu
#                      niedrig aus. Gemessen: Fass voll -> leer 258 s, Schwimmer -> leer 132 s, der
#                      Schwimmer sitzt also auf 51 % der nutzbaren Kapazitaet.
# 1.0.47 - 2026-08-18  Neu: Das Modul kann wissen, ob die Hauswasserzufuhr offen ist. Neues Attribut
#                      mainsSupplyDevice (Device:Reading, dazu mainsSupplyActiveValue/-InactiveValue).
#                      Hintergrund: Steht im Fass ein Schwimmerventil, fuellt es waehrend einer
#                      Befuellung Fass->IBC staendig nach - das ins IBC gefoerderte Wasser ist dann
#                      nicht reiner Regen, und harvest_*_l passt nicht zur tatsaechlich bewegten
#                      Menge. Neue Readings: mainsSupply (on/off), lastIbcFillSource (rain/mixed/
#                      unknown) sowie die kumulierten Foerdermengen pumped_total_l und
#                      pumpedRain_total_l. Letzteres zaehlt nur Laeufe ohne Hauswasser und laesst
#                      sich damit direkt gegen harvest_total_l halten - daraus ergibt sich der echte
#                      Wert fuer roofArea. Reine Statistik, die Steuerung bleibt unberuehrt; ohne
#                      mainsSupplyDevice aendert sich nichts.
# 1.0.46 - 2026-08-18  Revert von 1.0.45. Die dortige Annahme war falsch: barrelEmpty: yes->no wurde
#                      als Erfolg des Fass-Fuell-Watchdogs gewertet. Steht im Fass aber ein
#                      Schwimmerventil aus der Hauswasserleitung, wird barrelEmpty auch bei
#                      staubtrockenem IBC binnen Minuten wieder 'no' - 'Wasser ist da' sagt dann
#                      nichts ueber die konfigurierte Quelle aus. Das eigentliche Unterscheidungs-
#                      merkmal ist barrelFull: Ein IBC mit Wasser hebt das Fass bis zum Voll-Kontakt
#                      (und zwar schneller als ibcToBarrelDuration), ein Schwimmer allein bleibt
#                      darunter stehen. 1.0.45 haette damit genau die Erkennung eines leeren IBC
#                      stillgelegt. Die Alarme, die den Umbau ausgeloest hatten, waren keine
#                      Fehlalarme, sondern richtig - der IBC war tatsaechlich leer.
# 1.0.45 - 2026-08-18  Fix: Der Fass-Fuell-Watchdog pruefte auf das falsche Kriterium. Er galt nur dann
#                      als erfuellt, wenn barrelFull meldet. Wo eine Nachspeisung das Fass aber nur bis
#                      zu einem Schwimmerniveau deutlich UNTER dem Voll-Sensor bringt - z.B. bis etwa
#                      einem Drittel -, kann barrelFull waehrend einer Giesspause nie erreicht werden.
#                      barrelFillTimeoutAlert feuerte dort bei JEDER Pause, ohne dass irgendetwas
#                      gestoert war. An einer realen Anlage waren das fuenf Fehlalarme in einer Nacht,
#                      obwohl das Log zeigte, dass die Nachspeisung nach 3,4 Minuten Wasser lieferte.
#                      Setups, die daraus einen IBC-leer-Zustand ableiten, bekamen so einen dauerhaft
#                      falschen Alarm. Jetzt beendet bereits barrelEmpty: yes->no den Watchdog und
#                      loescht einen anstehenden Alarm - Wasser ist angekommen, genau das sollte er
#                      pruefen.
# 1.0.44 - 2026-08-18  Fix: Die Regen- und Ertrags-Readings wurden bei JEDEM Durchlauf von
#                      UpdateRainAmount geschrieben, also alle rainCheckInterval Minuten (Default 5)
#                      auch dann, wenn sich nichts geaendert hat. Das sind rund 290 Ereignisse je
#                      Reading und Tag, die durch DoTrigger, saemtliche Notifies und DbLog laufen und
#                      das FileLog des Geraets zumuellen: In einem realen 6000-Zeilen-Auszug entfielen
#                      allein auf rainAmount_mm und rainSinceFill_mm zusammen rund 3000 Zeilen - die
#                      Haelfte, und entsprechend weniger Historie. Sichtbare Readings werden jetzt nur
#                      noch bei echter Wertaenderung geschrieben. Die versteckten .rain*-Readings
#                      bleiben ausgenommen: sie aendern sich bauartbedingt staendig und erzeugen als
#                      Punkt-Readings ohnehin keine Ereignisse.
# 1.0.43 - 2026-08-17  Fix: Der mit 1.0.40 eingebaute Pendelschutz griff beim haeufigsten Fall nicht.
#                      CheckBarrelFull hat zwei getrennte Zweige - einen fuer HELPER{ibcToBarrelActive}
#                      (nur von StartIBCtoBarrel gesetzt) und einen fuer eine aktive Giesspause. Die
#                      normale Schwerkraft-Nachspeisung in einer Pause laeuft ueber den zweiten Zweig
#                      und setzt ibcToBarrelActive nie, sie merkt sich nur pauseSource. Der
#                      Ernte-Trigger wurde dort also nicht verbraucht: Regen -> Bewaesserung leert das
#                      Fass -> Pause fuellt es aus dem IBC -> nach dem Giessen wandert dasselbe Wasser
#                      wieder hoch. NoteNonRainFill wird jetzt auch im Pausen-Zweig aufgerufen.
#                      Neu: Messung der Gegenrichtung. Ein IBC->Fass-Lauf in einer Pause war bisher
#                      voellig unsichtbar (ibcToBarrelActive blieb 'no'). Neue Readings
#                      lastIbcToBarrelDuration und lastIbcToBarrelEnd halten Dauer und Endgrund fest -
#                      die 'Raus'-Seite fuer eine spaetere Fuellstandsbilanz.
# 1.0.42 - 2026-08-17  Fix: Regen loescht barrelFillTimeoutAlert nicht mehr. Der Alarm besagt, dass
#                      eine Fass-Befuellung nicht geklappt hat - Regen sagt darueber nichts aus.
#                      Setups, die daraus einen IBC-leer-Zustand ableiten (Dummy per notify), bekamen
#                      dadurch bei JEDEM Regenbeginn ein falsches 'Wasser vorhanden'. Der Alarm wird
#                      dort geloescht, wo er hingehoert: wenn barrelFull tatsaechlich meldet.
#                      Fix: RainCollectionSeenFill wird bei ibcEmpty nur noch auf der echten Flanke
#                      yes->no ausgeloest. Ein Sensor oder Dummy, der seinen 'nicht leer'-Zustand
#                      wiederholt, hat sonst die Sammel-Ueberwachung dauerhaft zurueckgesetzt - sie
#                      konnte nie anschlagen.
#                      Neu: Messgrundlage fuer eine spaetere IBC-Fuellstandsschaetzung. Je Lauf
#                      Fass->IBC werden Dauer und Endgrund festgehalten (lastIbcFillDuration,
#                      lastIbcFillEnd, lastIbcFillVolume_l). Laeuft ein Zyklus von vollem Fass bis
#                      barrelEmpty durch, ist das bewegte Volumen bekannt (neues Attribut
#                      barrelUsableVolume) - daraus lernt das Modul die aktuelle Foerderrate
#                      (ibcFillFlow_lpm, gedaempft gemittelt). So wandert die Rate mit, wenn der
#                      Filter zusetzt, statt in einem festen Attribut zu veralten.
# 1.0.41 - 2026-08-17  Neu: Fehlt der gespeicherte Ausgangswert .rainLastRaw - frisches Geraet oder
#                      geloeschte Readings -, war das Delta der ersten Messung 0. Die mit 1.0.36
#                      ergaenzte Fenster-Vorbelegung rettete dabei rainAmount_mm, nicht aber die
#                      Zaehler, die ueber das Delta laufen: harvest_*_l, rainSinceFill_mm und
#                      rainSinceHarvest_mm. Bei einem Tageszaehler (dailyrain_mm) wird der aktuelle
#                      Stand jetzt als bereits gefallener Regen uebernommen statt verworfen.
#                      Doppelt gezaehlt wird nichts: Ist eine Basis vorhanden, greift wie bisher die
#                      Delta-Rechnung.
# 1.0.40 - 2026-08-17  Fix: Stadtwasser-Befuellung setzt den Ernte-Trigger jetzt zurueck. Bisher deckte
#                      der Schutz nur den Moment ab, in dem das Fuellventil offen war. Nach einer
#                      Bewaesserung ist das Fass leer und wird in der Giesspause aus der
#                      Hauswasserleitung nachgefuellt - meldete es danach 'voll' und lag noch Regen im
#                      Zaehler, waere Leitungswasser in den IBC gepumpt worden. An der realen Anlage
#                      gut sichtbar: barrelFull-Ereignisse haeufen sich direkt nach den Giesszeiten.
#                      Neu: An allen sechs Stellen, an denen das Modul Stadtwasser aufdreht, wird
#                      rainSinceHarvest_mm auf 0 gesetzt (NoteNonRainFill). Die naechste Ernte
#                      verlangt damit neuen Regen. Wichtig: Ein rein MECHANISCHER Schwimmer in der
#                      Hauswasserleitung bleibt fuer das Modul unsichtbar - haelt der das Fass bis zum
#                      barrelFull-Sensor, greift dieser Schutz nicht; der Schwimmer sollte darunter
#                      abregeln.
#                      Fix: Gleiches Problem beim IBC->Fass-Transfer. Fuellte der das Fass bis
#                      barrelFull, stoppte CheckBarrelFull zwar den Transfer, der Ernte-Trigger im
#                      NotifyFn lief danach aber trotzdem an (ibcToBarrelActive war da schon
#                      zurueckgesetzt) - dasselbe Wasser waere sofort wieder hochgepumpt worden.
#                      CheckBarrelFull verbraucht den Trigger jetzt ebenfalls, und der Notify-Trigger
#                      schliesst einen laufenden Transfer zusaetzlich aus.
# 1.0.39 - 2026-08-17  Fix: Der mit 1.0.38 eingefuehrte Mengen-Trigger fuer die IBC-Befuellung wurde
#                      nicht verbraucht - er prueft rainAmount_mm, und der bleibt das ganze
#                      rainAmountWindow (Default 24 h) ueber der Schwelle. Wurde das Fass nach dem
#                      Umpumpen in einer Giesspause per Schwerkraft aus dem IBC wieder gefuellt,
#                      meldete barrelFull erneut und dasselbe Wasser waere zurueck in den IBC gepumpt
#                      worden (Fass<->IBC-Pendeln). Neu: Reading rainSinceHarvest_mm zaehlt den Regen
#                      seit der letzten Befuellung und wird beim Start einer Befuellung auf 0 gesetzt.
#                      Eine neue automatische Ernte verlangt damit immer NEUEN Regen. Eine bereits
#                      laufende Befuellung und die Sammel-Ueberwachung bewerten weiterhin
#                      rainAmount_mm, laufen also unveraendert weiter.
# 1.0.38 - 2026-08-17  Neu: Attribut ibcFillRainAmount (mm, 0 = aus). Die IBC-Befuellung setzte bisher
#                      voraus, dass es GENAU in dem Moment regnet, in dem der Fass-voll-Sensor
#                      anschlaegt. In der Praxis wird das Fenster fast immer verfehlt, weil Dach und
#                      Rinne nach Regenende nachlaufen und das Fass erst danach voll meldet (real
#                      beobachtet: Regen endete 08:27, barrelFull kam 09:41 - keine Befuellung).
#                      Mit gesetztem ibcFillRainAmount genuegt jetzt, dass im Fenster rainAmountWindow
#                      mindestens X mm gefallen sind; ein volles Fass wird dann auch nach dem Regen
#                      noch geerntet, und eine laufende Befuellung wird bei Regenende nicht mehr
#                      abgebrochen. Schutz gegen Hauswasser: Wurde das Fass aus der Hauswasserleitung
#                      gefuellt (Refill-Quelle water_supply oder Fuellventil offen), greift die
#                      Mengen-Bedingung nicht - es wird also kein Leitungswasser in den IBC gepumpt.
#                      Ohne das Attribut bleibt das Verhalten exakt wie bisher.
# 1.0.37 - 2026-08-16  Neu: Regenwasser-Ertragsstatistik. Mit den Attributen roofArea (Dachflaeche am
#                      Fallrohr in m2) und runoffCoefficient (Abflussbeiwert, Default 0.8) rechnet das
#                      Modul die gemessene Regenmenge in Liter um und fuehrt laufende Summen:
#                      harvest_today_l, harvest_month_l, harvest_year_l und harvest_total_l. Die
#                      Perioden-Zaehler laufen bei Tages-/Monats-/Jahreswechsel automatisch auf 0.
#                      Neu: set resetHarvestStats setzt alle vier Summen zurueck. Rein additiv, die
#                      Steuerlogik bleibt unveraendert; ohne roofArea passiert nichts.
# 1.0.36 - 2026-08-16  Fix: rainAmount_mm blieb dauerhaft 0.00, egal wie viel Regen fiel. Ursache: in
#                      Installationen, die Time::HiRes' time() nach main:: importieren, liefert time()
#                      eine Kommazahl. Die Zeitstempel im Puffer .rainBuffer bekamen dadurch einen
#                      Nachkommateil, den der Filter /^\d+:/ nicht akzeptierte - der Puffer wurde bei
#                      jedem Aufruf verworfen und neu angelegt, die Fenstersumme damit immer
#                      accum - accum = 0. Jetzt werden ganzzahlige Zeitstempel geschrieben und
#                      bestehende Puffer mit Nachkommateil weiterhin gelesen.
#                      Fix: Readings mit Historie (rainDetectedSince, rainAmount_mm, rainSinceFill_mm,
#                      rainCollectionAlert) wurden bei JEDEM FHEM-Neustart geleert. DefFn laeuft vor
#                      dem Einlesen der Statefile, die dortige Initialisierung ueberschrieb also die
#                      wiederhergestellten Werte. Diese Readings werden in Define nicht mehr gesetzt;
#                      alle Leser nutzen ohnehin einen ReadingsVal-Default.
#                      Neu: Ist der Fensterpuffer leer (neues Geraet oder Neustart ohne aktuelle
#                      Statefile), wird er aus dem Tageszaehler (dailyrain_mm) mit einem Basispunkt um
#                      Mitternacht vorbelegt - rainAmount_mm zeigt dann sofort wieder den Regen des
#                      laufenden Tages statt 0.
# 1.0.35 - 2026-08-13  Fix: pumpStartDelay-Reihenfolge jetzt auch in ALLEN pumpengestuetzten Fuell-/
#                      Transfer-Pfaden respektiert: StartIBCFill, StartIBCtoBarrel, der IBC-Zweig der
#                      Bewaesserungs- und der Kreis-Pause (StartWateringPause/StartCircuitPause), die
#                      Fass-leer-Nachfuellpause (StartBarrelEmptyRefillPause) und der Fass-leer-Not-
#                      Refill (HandleBarrelEmpty). Diese starteten bisher IMMER die Pumpe zuerst und
#                      oeffneten das Ventil erst abs(pumpStartDelay) Sekunden spaeter (Vorzeichen
#                      ignoriert) - die Pumpe lief in dem Fenster gegen ein geschlossenes Ventil.
#                      Jetzt gilt ueberall: positiv = Pumpe zuerst, negativ/0 = Ventil zuerst.
#                      Zusaetzlich abgesichert: wird die Aktion im Delay-Fenster gestoppt, schaltet
#                      der Timer das zweite Geraet nicht mehr nachtraeglich ein.
# 1.0.34 - 2026-08-13  Fix: pumpStartDelay wurde nicht in allen Pfaden respektiert - die Pumpe lief
#                      teils VOR dem Ventil, obwohl das Ventil zuerst oeffnen sollte. (1) Der
#                      Gleichzeitig-Zweig (Delay 0, bzw. wenn eine kurze Restlaufzeit den Delay intern
#                      auf 0 kuerzte) schaltete erst die Pumpe, dann das Ventil - jetzt Ventil zuerst.
#                      (2) 'set startValve N' (StartSingleValve) ignorierte pumpStartDelay komplett und
#                      startete immer die Pumpe zuerst - respektiert jetzt dieselbe Reihenfolge wie
#                      OpenValve (positiv = Pumpe zuerst, negativ/0 = Ventil zuerst). Damit laeuft die
#                      Pumpe nie mehr gegen ein geschlossenes Ventil an.
# 1.0.33 - 2026-07-26  Neu: Regenmengen-Integration (mm) ueber eine Wetterstation mit Regenmesser.
#                      Neues Attribut rainAmountDevice (Device:Reading, z.B. MQTT2_xxx:dailyrain_mm) plus
#                      rainAmountReading und rainAmountWindow (gleitendes Fenster in Stunden, Default 24).
#                      Das Modul summiert die Regenmenge selbst gleitend auf (reset-fest gegen den taeglichen
#                      Nullstellen der Station) -> Reading rainAmount_mm. Neu: rainSkipsWateringAmount (mm) -
#                      ist im Fenster mind. so viel Regen gefallen, wird der geplante Zyklus uebersprungen
#                      (state 'skipped - enough rain'). Neu: Regenwasser-Sammel-Ueberwachung -
#                      rainCollectionCheckAmount (mm) + rainCollectionCheckDelay (min): faellt so viel Regen,
#                      ohne dass Fass/IBC eine Fuellstands-Reaktion zeigen, wird Reading rainCollectionAlert
#                      auf yes gesetzt (Hinweis auf verstopften Zulauf/Dachrinne/Filter). Readings
#                      rainAmount_mm, rainSinceFill_mm, rainCollectionAlert.
# 1.0.32 - 2026-06-15  Fix: Reading 'ibcToBarrelActive' blieb beim automatischen Fass-Nachfuellen aus dem IBC
#                      (HandleBarrelEmpty -> Quelle 'ibc') auf 'no' haengen, obwohl der IBC->Fass-Transfer lief -
#                      nur das interne HELPER-Flag wurde gesetzt. Jetzt wird das Reading korrekt auf 'yes' gesetzt.
#                      Fix: StopAll setzt 'ibcToBarrelActive' und 'ibcFilling' wieder auf 'no' zurueck (sonst blieben
#                      diese Readings nach einem Not-Stop waehrend Transfer/IBC-Befuellung auf 'yes' haengen).
# 1.0.31 - 2026-06-09  Neu: Attribut rainSkipsWatering (0/1) - bei Regen wird der geplante Bewaesserungszyklus
#                      (StartWatering / activeValves) uebersprungen; unabhaengige Kreise via startCircuit
#                      (z.B. ueberdachtes Gewaechshaus) bleiben unberuehrt. Neu: Kreis-Namen ueber Attribute
#                      valve1Name..valve8Name - erscheinen in Logs, phase-Reading und neuem Reading
#                      currentValveName (z.B. 'watering circuit 8 (Gewaechshaus)').
# 1.0.30 - 2026-06-09  Neu: Loop-Breaker gegen endloses Nachfuell<->Leerlauf-Pendeln. Laeuft das Fass trotz
#                      wiederholtem Nachfuellen binnen Sekunden wieder leer (z.B. IBC leer und keine Hauswasser-
#                      Reserve), bricht das Modul nach barrelEmptyMaxRefillAttempts Versuchen (Default 3) ab,
#                      State 'stopped - no water'. Automatischer Neustart sobald wieder Wasser gemeldet wird:
#                      barrelFull (massgebliches Signal) oder ibcEmpty:no (IBC hat Wasser). Regen allein zaehlt
#                      bewusst nicht (Nieselregen fuellt das Fass nicht; fuellt Regen es, meldet das der Fass-voll-
#                      Sensor). Neues Attribut barrelEmptyMaxRefillAttempts (0 = aus = altes Verhalten).
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
# Die laufende Version aus der Aenderungsliste im Dateikopf lesen.
#
# Fest verdrahtet stand sie hier schon zweimal falsch: erst 38 Versionen alt,
# dann wieder zwei. Eine Zahl, die von Hand nachgezogen werden muss, wird
# irgendwann vergessen - und eine falsche Version ist schlimmer als keine, weil
# man ihr glaubt. Die Aenderungsliste wird dagegen bei jeder Aenderung ohnehin
# gepflegt, sie ist also die einzige Quelle, die nicht veralten kann.
#
# Gelesen wird einmal beim Laden des Moduls, gesucht wird nur im Kopf. $FALLBACK
# greift, wenn die Datei nicht lesbar ist (sehr unwahrscheinlich - FHEM hat sie
# gerade selbst geladen) oder die Liste ihr Format aendert.
{
    my $FALLBACK = '1.0.75';
    my $cached;
    sub Gartenbewaesserung_Version {
        return $cached if(defined($cached));
        $cached = $FALLBACK;
        if(open(my $fh, "<", __FILE__)) {
            my $lines = 0;
            while(my $l = <$fh>) {
                last if(++$lines > 80);
                if($l =~ /^#\s*(\d+\.\d+\.\d+)\s+-\s+\d{4}-\d{2}-\d{2}/) {
                    $cached = $1;      # der oberste Eintrag ist der neueste
                    last;
                }
            }
            close($fh);
        }
        return $cached;
    }
}

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
        "valve1Flow_lpm:textField valve2Flow_lpm:textField valve3Flow_lpm:textField valve4Flow_lpm:textField " .
        "valve5Flow_lpm:textField valve6Flow_lpm:textField valve7Flow_lpm:textField valve8Flow_lpm:textField " .
        "valve1Name:textField valve2Name:textField valve3Name:textField valve4Name:textField " .
        "valve5Name:textField valve6Name:textField valve7Name:textField valve8Name:textField " .
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
        "rainAmountDevice:textField " .
        "rainAmountReading:textField " .
        "rainAmountWindow:slider,1,1,72 " .
        "rainSkipsWateringAmount:slider,0,0.5,50 " .
        "rainCollectionCheckAmount:slider,0,0.5,50 " .
        "rainCollectionCheckDelay:slider,5,5,720 " .
        "ibcFillRainAmount:slider,0,0.1,20 " .
        "roofArea:textField " .
        "barrelUsableVolume:textField barrelFloatLevel:textField " .
        "wateringFlow_lpm:textField " .
        "ibcFillFlow_lpm:textField ibcToBarrelFlow_lpm:textField " .
        "ibcUsableVolume:textField ibcFullFromLevel:0,1 " .
        "mainsSupplyDevice:textField mainsFillFlow_lpm:textField " .
        "mainsSupplyActiveValue:textField mainsSupplyInactiveValue:textField " .
        "runoffCoefficient:textField " .
        "pumpStartDelay:slider,-30,1,30 " .
        "pumpMaxRuntime:slider,0,1,240 " .
        "barrelFillTimeout:slider,0,1,120 " .
        "barrelEmptyMaxRefillAttempts:slider,0,1,10 " .
        "rainSkipsWatering:0,1 " .
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

    $hash->{VERSION}    = Gartenbewaesserung_Version();

    my $name = $a[0];

    # Initialize readings
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "state", "initialized");
    readingsBulkUpdate($hash, "phase", "idle");
    readingsBulkUpdate($hash, "currentValve", "none");
    readingsBulkUpdate($hash, "currentValveName", "none");
    readingsBulkUpdate($hash, "cycleProgress", "0/0");
    readingsBulkUpdate($hash, "ibcFilling", "no");
    readingsBulkUpdate($hash, "ibcToBarrelActive", "no");
    readingsBulkUpdate($hash, "remainingTime", "-");
    readingsBulkUpdate($hash, "pauseActive", "no");
    readingsBulkUpdate($hash, "pauseTimeRemaining", "-");
    readingsBulkUpdate($hash, "barrelEmpty", "no");
    readingsBulkUpdate($hash, "barrelFillTimeoutAlert", "no");
    readingsEndUpdate($hash, 1);

    # NOTE: readings carrying history across restarts (rainDetectedSince,
    # rainAmount_mm, rainSinceFill_mm, rainCollectionAlert) are deliberately NOT
    # initialized here. DefFn runs before the statefile is applied, so writing them
    # here overwrites the restored values on every FHEM restart. All readers use a
    # ReadingsVal default instead, so a brand-new device behaves the same.

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
    $attr{$name}{rainAmountWindow} = 24 if(!defined($attr{$name}{rainAmountWindow}));
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
    Gartenbewaesserung_UpdateRainAmount($hash);
    InternalTimer(gettimeofday() + 5, sub {
        Gartenbewaesserung_UpdateSensorReadings($hash);
        Gartenbewaesserung_UpdateRainAmount($hash);
        # Erst hier, nicht im Define: waehrend des Einlesens der fhem.cfg ist der
        # Statefile noch nicht angewendet, die Geraete-Readings sind also leer.
        Gartenbewaesserung_AdoptOrStopOrphans($hash);
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
               "mainsFillIbc:textField " .
               "startIBCtoBarrel:noArg stopIBCtoBarrel:noArg " .
               "startValve:1,2,3,4,5,6,7,8 stopValve:noArg " .
               "resetPumpOverrunAlert:noArg " .
               "resetHarvestStats:noArg " .
               "ibcLevel:textField barrelLevel:textField " .
               "waterSource:rain,other " .
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
        return Gartenbewaesserung_StopIBCFill($hash, "manual");
    }
    elsif($cmd eq "mainsFillIbc") {
        my $spec = $args[0];
        return "Usage: set $name mainsFillIbc <liter>|<prozent>%|stop" if(!defined($spec));
        if(lc($spec) eq "stop" || $spec eq "0") {
            return "no mains fill is running" if(!Gartenbewaesserung_MainsFillIbcActive($hash));
            Gartenbewaesserung_MainsFillIbcStop($hash, "stopped by hand");
            return undef;
        }
        return Gartenbewaesserung_MainsFillIbcStart($hash, $spec);
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
    elsif($cmd eq "resetHarvestStats") {
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash, "harvest_today_l", "0.0");
        readingsBulkUpdate($hash, "harvest_month_l", "0.0");
        readingsBulkUpdate($hash, "harvest_year_l",  "0.0");
        readingsBulkUpdate($hash, "harvest_total_l", "0.0");
        readingsBulkUpdate($hash, "pumped_total_l", "0");
        readingsBulkUpdate($hash, "pumpedRain_total_l", "0");
        readingsBulkUpdate($hash, "mains_total_l", "0");
        readingsBulkUpdate($hash, "pumpedOther_total_l", "0");
        readingsEndUpdate($hash, 1);
        Log3 $name, 3, "$name: harvest statistics reset";
        return undef;
    }
    elsif($cmd eq "ibcLevel" || $cmd eq "barrelLevel") {
        # Beide Behaelter, ein Parser. Liter, oder Prozent mit angehaengtem
        # Prozentzeichen - am Tank ist "etwa ein Drittel" oft leichter
        # abzulesen als eine Litermenge.
        my $isIbc  = ($cmd eq "ibcLevel");
        my $volAttr = $isIbc ? "ibcUsableVolume" : "barrelUsableVolume";
        my $capacity = AttrVal($name, $volAttr, 0);
        return "Set $volAttr first" if($capacity <= 0);

        my $value = defined($args[0]) ? $args[0] : "";
        return "Usage: set $name $cmd <liter> | <prozent>%"
            if($value !~ /^(\d+(?:\.\d+)?)\s*(%?)$/);
        my ($number, $isPercent) = ($1, $2);
        my $liters = $isPercent ? ($capacity * $number / 100) : $number;
        return "$cmd must not exceed $volAttr ($capacity l)" if($liters > $capacity);

        if($isIbc) {
            Gartenbewaesserung_SetIbcLevel($hash, $liters, "manual", 1);
        }
        else {
            Gartenbewaesserung_SetBarrelLevel($hash, $liters, "manual", 1);
            # Von Hand gesetzt heisst: wir wissen nicht, was vorher hineinlief -
            # die gesammelte Ventilzeit taugt danach nicht mehr zum Lernen.
            $hash->{HELPER}{drawTainted} = 1;
        }
        Log3 $name, 3, sprintf("%s: %s anchored at %.0f l (manual)", $name, $cmd, $liters);
        return undef;
    }
    elsif($cmd eq "waterSource") {
        my $value = defined($args[0]) ? lc($args[0]) : "";
        return "Usage: set $name waterSource rain|other"
            if($value ne "rain" && $value ne "other");
        readingsSingleUpdate($hash, "waterSource", $value, 1);
        Log3 $name, 3, ($value eq "other")
            ? "$name: water source set to 'other' - harvesting on a full barrel alone, "
              . "volume booked separately, collection watchdog not credited. "
              . "Falls back to 'rain' at the next barrelEmpty."
            : "$name: water source back to 'rain'";
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

    if($cmd eq "set" && $attrName eq "roofArea") {
        return "roofArea must be a positive number (square metres)"
            if($attrVal !~ /^\d+(?:\.\d+)?$/ || $attrVal <= 0);
    }

    if($cmd eq "set" && $attrName eq "runoffCoefficient") {
        return "runoffCoefficient must be a number between 0 and 1 (e.g. 0.8)"
            if($attrVal !~ /^\d*(?:\.\d+)?$/ || $attrVal <= 0 || $attrVal > 1);
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
                    # Snapshot BEFORE anything below runs: CheckBarrelFull clears
                    # ibcToBarrelActive, and the harvest a few lines down sets
                    # ibcFilling. Reading those flags afterwards would show the
                    # module its own doing and never credit the rain.
                    my $notFromRain = (ReadingsVal($name, "ibcToBarrelActive", "no") eq "yes"
                                    || ReadingsVal($name, "ibcFilling", "no") eq "yes"
                                    || ReadingsVal($name, "waterSource", "rain") eq "other"
                                    || $hash->{HELPER}{barrelFilling}) ? 1 : 0;
                    readingsSingleUpdate($hash, "barrelFull", "yes", 1);
                    # Hard anchor for the level estimate, and the starting line
                    # for learning the watering draw rate
                    Gartenbewaesserung_SetBarrelLevel($hash,
                        AttrVal($name, "barrelUsableVolume", 0), "barrelFull", 1);
                    $hash->{HELPER}{drawMinutes} = 0;
                    delete $hash->{HELPER}{drawTainted};
                    delete $hash->{HELPER}{drawBooked};
                    Gartenbewaesserung_CheckBarrelFull($hash);
                    # Barrel full after (or during) rain and idle -> harvest into the IBC
                    if(Gartenbewaesserung_HarvestDue($hash) &&
                       !$hash->{HELPER}{ibcFilling} &&
                       !$hash->{HELPER}{ibcToBarrelActive} &&
                       !$hash->{HELPER}{watering} &&
                        !$hash->{HELPER}{circuitMode}) {
                        Log3 $name, 3, "$name: Barrel full after rain ("
                            . ReadingsVal($name, "rainAmount_mm", "?") . " mm in window), starting IBC fill";
                        Gartenbewaesserung_StartIBCFill($hash, 0);
                    }
                    if($hash->{HELPER}{barrelEmptyResumePending} && $hash->{HELPER}{barrelEmptyRefillPause}) {
                        Log3 $name, 3, "$name: Barrel full during refill pause, resuming interrupted operation";
                        Gartenbewaesserung_StopBarrelEmptyRefillPause($hash);
                        Gartenbewaesserung_ResumeAfterBarrelEmpty($hash);
                    }
                    # Recover from a no-water abort: the barrel is physically full again
                    Gartenbewaesserung_RecoverFromNoWater($hash, 1);
                    # Barrel gained water from rain (not from an IBC->barrel transfer or house-water
                    # fill) -> the rainwater collection is working
                    if(Gartenbewaesserung_RainRecentEnough($hash) && !$notFromRain) {
                        Gartenbewaesserung_RainCollectionSeenFill($hash, "barrelFull (rain)");
                    }
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
                    # IBC reported full -> water is being collected
                    Gartenbewaesserung_RainCollectionSeenFill($hash, "ibcFull");
                    # Hard anchor for the level estimate: wipes accumulated drift
                    Gartenbewaesserung_SetIbcLevel($hash,
                        AttrVal($name, "ibcUsableVolume", 0), "ibcFull", 1);
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
                    # Hard anchor for the level estimate: wipes accumulated drift
                    Gartenbewaesserung_SetIbcLevel($hash, 0, "ibcEmpty", 1);
                }
                elsif(Gartenbewaesserung_CheckSensorInactive($name, $event, $ibcEmptyReading,
                      AttrVal($name, "ibcEmptySensorInactiveValue", ""))) {
                    # Only a real yes->no edge counts as a fill response. A sensor that
                    # repeats its "not empty" state - or a dummy fed by an automation -
                    # would otherwise reset the collection watchdog over and over.
                    my $wasEmpty = (ReadingsVal($name, "ibcEmpty", "") eq "yes");
                    readingsSingleUpdate($hash, "ibcEmpty", "no", 1);
                    # IBC has water again -> recover from a no-water abort if active
                    Gartenbewaesserung_RecoverFromNoWater($hash, 0);
                    if($wasEmpty) {
                        # IBC gained water (no longer empty) -> rainwater collection works
                        Gartenbewaesserung_RainCollectionSeenFill($hash, "ibcEmpty:no");
                    }
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
                    # Emptied by watering alone? Then the accumulated valve time
                    # corresponds to a known volume - learn before anchoring.
                    # Ein Ventil, das JETZT noch offen ist, wurde noch nicht
                    # abgerechnet: NoteValveDraw laeuft erst beim Schliessen. Ohne
                    # das fehlen seine Minuten in der Rechnung und sein Kreis in der
                    # Zuordnung. Am 21.08.2026 wurden so 148 l durch 2 statt durch
                    # 6,8 Minuten geteilt - valve1Flow_lpm 74 l/min, und das auch
                    # noch auf dem falschen Kreis (gelaufen war Kreis 2).
                    Gartenbewaesserung_NoteOpenValveDrawTime($hash);
                    Gartenbewaesserung_LearnWateringFlow($hash);
                    Gartenbewaesserung_SetBarrelLevel($hash, 0, "barrelEmpty", 1);
                    # Fremdwasser ist raus - ab jetzt gilt wieder der Normalfall.
                    if(ReadingsVal($name, "waterSource", "rain") ne "rain") {
                        readingsSingleUpdate($hash, "waterSource", "rain", 1);
                        Log3 $name, 3, "$name: barrel empty - water source back to 'rain'";
                    }
                    Log3 $name, 3, "$name: Barrel empty detected, stopping pump and watering";
                    Gartenbewaesserung_HandleBarrelEmpty($hash);
                }
                elsif(Gartenbewaesserung_CheckSensorInactive($name, $event, $barrelEmptyReading,
                      AttrVal($name, "barrelEmptySensorInactiveValue", ""))) {
                    # NOTE: deliberately does NOT stop the fill watchdog. A mains float
                    # valve in the barrel makes barrelEmpty clear within minutes even
                    # when the IBC is bone dry, so "water arrived" says nothing about
                    # the configured source. barrelFull is the discriminating signal:
                    # a working IBC lifts the barrel to the full contact, a float alone
                    # stops well below it. Cancelling here would silently disable the
                    # empty-IBC detection (was briefly the case in 1.0.45).
                    # NOTE: this edge is deliberately NOT counted as evidence for
                    # the collection watchdog either, even with the mains closed.
                    # barrelEmptySensorDevice is often not a level switch but a
                    # dummy fed by an automation - in the author's installation it
                    # is derived from the pump's power draw and cleared by a rule
                    # that reacts to RAIN. Crediting it would close a circle: rain
                    # clears the reading, the cleared reading proves the rain was
                    # collected, and a blocked downpipe would never be noticed.
                    # A false all-clear is worse than a false alarm. barrelFull is
                    # the only signal that cannot be faked by an inference.

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
                    # NOTE: rain does NOT clear barrelFillTimeoutAlert any more. The alert
                    # states that a barrel fill did not succeed - rain says nothing about
                    # that, and clearing it here produced a false "water is available"
                    # signal for setups that derive an IBC-empty flag from the alert.
                    # It is cleared where it belongs: when barrelFull actually reports.
                    Log3 $name, 4, "$name: Rain sensor active (event), triggering CheckRain immediately";
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
                        Gartenbewaesserung_StopIBCFill($hash, "watering");
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

        # Rain amount (mm) sensor - accumulate rolling window + collection check
        my $rainAmountDef = AttrVal($name, "rainAmountDevice", "");
        if($rainAmountDef ne "") {
            my ($raDev, $raReading) = Gartenbewaesserung_ParseDevice($rainAmountDef);
            $raReading = AttrVal($name, "rainAmountReading", "dailyrain_mm") if($raReading eq "");
            if($devName eq $raDev && $event =~ /^$raReading:\s*(.+)$/) {
                Gartenbewaesserung_UpdateRainAmount($hash);
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
        my $full = $value || Gartenbewaesserung_IbcFullByLevelState($hash);
        readingsBulkUpdate($hash, "ibcFull", $full ? "yes" : "no");
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

    my $mains = Gartenbewaesserung_MainsSupplyState($hash);
    readingsBulkUpdate($hash, "mainsSupply", $mains) if($mains ne "");

    readingsEndUpdate($hash, 1);

    Gartenbewaesserung_ApplyBarrelFloatFloor($hash);

    # Refresh rolling rain amount (separate readings transaction)
    Gartenbewaesserung_UpdateRainAmount($hash);
}

##############################################################################
# Optional human-readable name for a circuit/valve (attribute valveNName).
# Returns "" if none configured.
##############################################################################
sub Gartenbewaesserung_ValveName {
    my ($hash, $num) = @_;
    return "" if(!defined($num) || $num !~ /^\d+$/);
    return AttrVal($hash->{NAME}, "valve${num}Name", "");
}

##############################################################################
# Label for logs/phase: "8" or "8 (Gewaechshaus)" if a name is configured.
##############################################################################
sub Gartenbewaesserung_CircuitLabel {
    my ($hash, $num) = @_;
    my $vn = Gartenbewaesserung_ValveName($hash, $num);
    return $vn ne "" ? "$num ($vn)" : "$num";
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
    Gartenbewaesserung_StopIBCFill($hash, "watering");

    my $circuitLabel = Gartenbewaesserung_CircuitLabel($hash, $circuitNum);

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "state", "circuit mode");
    readingsBulkUpdate($hash, "phase", "starting circuit $circuitLabel");
    readingsBulkUpdate($hash, "cycleProgress", "1/1");
    readingsBulkUpdate($hash, "pauseActive", "no");
    readingsEndUpdate($hash, 1);

    Log3 $name, 3, "$name: Starting circuit $circuitLabel (independent mode - no IBC collection)";

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
    Gartenbewaesserung_NoteNonRainFill($hash, "mains supply");
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
    Gartenbewaesserung_StopIBCFill($hash, "watering");

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
            # Zero delay: open valve FIRST, then pump (valve must lead so the
            # pump never runs against a closed valve)
            Gartenbewaesserung_SwitchDevice($name, $valveDevice, "on");
            Gartenbewaesserung_SwitchDevice($name, $pumpDevice, "on");
            Log3 $name, 4, "$name: Circuit $circuitNum valve opened, then pump (no delay)";
        }
    }
    else {
        # No pump, just open valve
        Gartenbewaesserung_SwitchDevice($name, $valveDevice, "on");
    }

    # Set end time
    Gartenbewaesserung_SetEndTime($hash, $duration);

    my $circuitLabel = Gartenbewaesserung_CircuitLabel($hash, $circuitNum);

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "phase", "watering circuit $circuitLabel");
    $hash->{HELPER}{valveOpenTime} = int(time());
    readingsBulkUpdate($hash, "currentValve", $circuitNum);
    readingsBulkUpdate($hash, "currentValveName", Gartenbewaesserung_ValveName($hash, $circuitNum));
    readingsEndUpdate($hash, 1);

    Log3 $name, 3, "$name: Circuit $circuitLabel watering for $duration minutes";

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
    Gartenbewaesserung_NoteValveDraw($hash, $circuitNum);

    readingsSingleUpdate($hash, "currentValve", "none", 1);
    readingsSingleUpdate($hash, "currentValveName", "none", 1);

    # Check if we have remaining time (pause is needed)
    if(defined($hash->{HELPER}{valveRemainingTime}) && $hash->{HELPER}{valveRemainingTime} > 0) {
        if(!Gartenbewaesserung_BarrelNeedsRefill($hash)) {
            Log3 $name, 3, "$name: Circuit $circuitNum has remaining time, but the barrel is "
                . "full - skipping the refill pause and carrying on";
            $hash->{HELPER}{lastPauseEnd} = time();
            InternalTimer(gettimeofday() + 2, sub {
                Gartenbewaesserung_RunCircuit($hash, $circuitNum);
            }, $hash);
            return;
        }
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
            Gartenbewaesserung_NoteNonRainFill($hash, "mains supply");
            $hash->{HELPER}{pauseSource} = "water_supply";
        }
    }
    else {
        # Fill from IBC
        Log3 $name, 3, "$name: IBC has water, filling barrel from IBC";

        my $ibcToBarrelPump = AttrVal($name, "ibcToBarrelPumpDevice", "");
        my $ibcToBarrelValve = AttrVal($name, "ibcToBarrelValveDevice", "");

        if($ibcToBarrelPump ne "") {
            # Ordering follows pumpStartDelay (positive = pump first, negative/zero
            # = valve first); bail out if the pause ended during the delay window.
            my $delay = AttrVal($name, "pumpStartDelay", 3);
            if($delay > 0) {
                Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelPump, "on");
                InternalTimer(gettimeofday() + $delay, sub {
                    return if(!$hash->{HELPER}{pauseActive});
                    Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelValve, "on") if($ibcToBarrelValve ne "");
                }, $hash);
            }
            elsif($delay < 0) {
                Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelValve, "on") if($ibcToBarrelValve ne "");
                InternalTimer(gettimeofday() + abs($delay), sub {
                    return if(!$hash->{HELPER}{pauseActive});
                    Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelPump, "on");
                }, $hash);
            }
            else {
                Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelValve, "on") if($ibcToBarrelValve ne "");
                Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelPump, "on");
            }
        }
        else {
            if($ibcToBarrelValve ne "") {
                Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelValve, "on");
            }
        }

        $hash->{HELPER}{pauseSource} = "ibc";
        Gartenbewaesserung_NoteIbcToBarrelStart($hash);
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
        # Fehlte hier, im Gegensatz zu EndWateringPause - deshalb wurde eine
        # Kreis-Pause nie abgerechnet.
        Gartenbewaesserung_NoteIbcToBarrelStop($hash, "pauseEnd");

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
    readingsBulkUpdate($hash, "currentValveName", "none");
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

    # Skip the scheduled watering cycle while it is raining (optional).
    # Only affects StartWatering (activeValves); independent circuits started via
    # "set ... startCircuit N" (e.g. a rain-protected greenhouse) are NOT affected.
    if(AttrVal($name, "rainSkipsWatering", 0) && ReadingsVal($name, "raining", "no") eq "yes") {
        Log3 $name, 3, "$name: Watering skipped - currently raining (rainSkipsWatering)";
        readingsSingleUpdate($hash, "state", "skipped - raining", 1);
        return "Skipped - raining";
    }

    # Skip the scheduled cycle if enough rain fell within the rolling window (optional).
    # Uses the accumulated rain amount (mm) from a weather station rain gauge.
    my $skipAmount = AttrVal($name, "rainSkipsWateringAmount", 0);
    if($skipAmount > 0 && AttrVal($name, "rainAmountDevice", "") ne "") {
        Gartenbewaesserung_UpdateRainAmount($hash);   # make sure the value is current
        my $rainAmount = ReadingsVal($name, "rainAmount_mm", 0);
        my $windowH = AttrVal($name, "rainAmountWindow", 24);
        if($rainAmount >= $skipAmount) {
            Log3 $name, 3, "$name: Watering skipped - ${rainAmount} mm rain in last ${windowH}h (>= ${skipAmount} mm)";
            readingsSingleUpdate($hash, "state", "skipped - enough rain (${rainAmount} mm)", 1);
            return "Skipped - enough rain";
        }
    }

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
# Braucht das Fass ueberhaupt Wasser?
#
# Eine Nachfuellpause ist ein Mittel, kein Zweck - sie soll dem Fass Zeit geben,
# sich zu fuellen. Ist es schon voll, gibt es nichts zu warten: dann wird
# weitergegossen, statt 20 Minuten Nacht zu verschenken UND das Ventil in ein
# volles Fass zu oeffnen.
#
# Bewusst nur barrelFull, nicht barrelLevel gegen barrelFillThreshold: der
# Fuellstand ist eine Schaetzung und haengt an den gelernten Ventilraten. Am
# 21.08.2026 zeigte er 85 %, waehrend das Fass real fast leer war - haette man
# ihm geglaubt, waere eine noetige Pause ausgefallen. barrelFull ist dagegen ein
# physischer Kontakt. Im Zweifel lieber eine Pause zu viel als eine zu wenig.
##############################################################################
sub Gartenbewaesserung_BarrelNeedsRefill {
    my ($hash) = @_;
    return (ReadingsVal($hash->{NAME}, "barrelFull", "no") eq "yes") ? 0 : 1;
}

##############################################################################
# Waechter fuer die Strecke IBC -> Fass.
#
# Zugemacht wurde bisher nur beim EREIGNIS barrelFull (CheckBarrelFull). War das
# Fass beim Oeffnen schon voll, kann dieses Ereignis gar nicht mehr kommen - das
# Ventil blieb dann bis zum Pausenende offen und der IBC lief ueber den
# Fassueberlauf ins Fallrohr ab. Am 21.08.2026 zweimal 20,0 min statt der sonst
# ueblichen 0,2-12,1 min; rund 200 l sind so verschwunden, unsichtbar, weil der
# Ueberlauf in den Ablauf geht.
#
# Der Waechter prueft deshalb den ZUSTAND statt der Flanke und zieht zusaetzlich
# ibcToBarrelDuration als harte Grenze ein - das Attribut galt bisher nur fuer
# die Ernte-Richtung, auf die Pausen-Nachlaeufe wirkte es nie.
##############################################################################
sub Gartenbewaesserung_IbcToBarrelWatchdog {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    RemoveInternalTimer($hash, "Gartenbewaesserung_IbcToBarrelWatchdog");
    my $start = $hash->{HELPER}{ibcToBarrelStartTime};
    return if(!$start);

    my $minutes = (int(time()) - $start) / 60;

    if(ReadingsVal($name, "barrelFull", "no") eq "yes") {
        Log3 $name, 3, sprintf("%s: IBC-to-barrel transfer is running into a FULL barrel "
            . "(%.1f min) - stopping. No barrelFull event could arrive, the barrel was "
            . "already full when the valve opened.", $name, $minutes);
        Gartenbewaesserung_CheckBarrelFull($hash);
        return;
    }

    my $limit = AttrVal($name, "ibcToBarrelDuration", 0);
    if($limit > 0 && $minutes >= $limit) {
        Log3 $name, 3, sprintf("%s: IBC-to-barrel transfer reached ibcToBarrelDuration "
            . "(%.1f of %g min) without barrelFull - stopping", $name, $minutes, $limit);
        Gartenbewaesserung_StopIbcToBarrelTransfer($hash, "maxDuration");
        return;
    }

    InternalTimer(gettimeofday() + 30, "Gartenbewaesserung_IbcToBarrelWatchdog", $hash);
}

# Armaturen der Strecke zumachen, ohne den Pausenkontext anzutasten. Die Pause
# laeuft weiter - kam in ihrer Zeit kein barrelFull, meldet das der
# barrelFillTimeout, und das ist die ehrlichere Aussage als ein stiller Abbruch.
sub Gartenbewaesserung_StopIbcToBarrelTransfer {
    my ($hash, $reason) = @_;
    my $name = $hash->{NAME};

    Gartenbewaesserung_NoteIbcToBarrelStop($hash, $reason);

    my $valve = AttrVal($name, "ibcToBarrelValveDevice", "");
    Gartenbewaesserung_SwitchDevice($name, $valve, "off") if($valve ne "");
    my $pump = AttrVal($name, "ibcToBarrelPumpDevice", "");
    Gartenbewaesserung_SwitchDevice($name, $pump, "off") if($pump ne "");

    delete $hash->{HELPER}{pauseSource}
        if(($hash->{HELPER}{pauseSource} || "") eq "ibc");
    delete $hash->{HELPER}{barrelEmptyRefillPauseSource}
        if(($hash->{HELPER}{barrelEmptyRefillPauseSource} || "") eq "ibc");
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
            Gartenbewaesserung_NoteNonRainFill($hash, "mains supply");
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
            # Ordering follows pumpStartDelay: positive = pump first, negative/zero
            # = valve first so the pump never runs against a closed valve. The
            # delayed callbacks bail out if the pause has meanwhile ended.
            my $delay = AttrVal($name, "pumpStartDelay", 3);
            if($delay > 0) {
                Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelPump, "on");
                Log3 $name, 4, "$name: Started IBC to barrel pump";
                InternalTimer(gettimeofday() + $delay, sub {
                    return if(!$hash->{HELPER}{pauseActive});
                    Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelValve, "on") if($ibcToBarrelValve ne "");
                    Log3 $name, 4, "$name: Opened IBC to barrel valve after pump delay";
                }, $hash);
            }
            elsif($delay < 0) {
                Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelValve, "on") if($ibcToBarrelValve ne "");
                Log3 $name, 4, "$name: Opened IBC to barrel valve (negative delay)";
                InternalTimer(gettimeofday() + abs($delay), sub {
                    return if(!$hash->{HELPER}{pauseActive});
                    Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelPump, "on");
                    Log3 $name, 4, "$name: Started IBC to barrel pump after valve";
                }, $hash);
            }
            else {
                Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelValve, "on") if($ibcToBarrelValve ne "");
                Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelPump, "on");
                Log3 $name, 4, "$name: Opened IBC to barrel valve, then pump (no delay)";
            }
        }
        else {
            # Gravity feed
            if($ibcToBarrelValve ne "") {
                Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelValve, "on");
                Log3 $name, 4, "$name: Opened IBC to barrel valve (gravity)";
            }
        }

        $hash->{HELPER}{pauseSource} = "ibc";
        Gartenbewaesserung_NoteIbcToBarrelStart($hash);
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
        Gartenbewaesserung_NoteIbcToBarrelStop($hash, "pauseEnd");
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
    Gartenbewaesserung_StopIBCFill($hash, "watering");

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
            # Zero delay: open valve FIRST, then pump (valve must lead so the
            # pump never runs against a closed valve)
            Gartenbewaesserung_SwitchDevice($name, $valveDevice, "on");
            Gartenbewaesserung_SwitchDevice($name, $pumpDevice, "on");
            Log3 $name, 4, "$name: Valve $valveNum opened, then pump (no delay)";
        }
    }
    else {
        Gartenbewaesserung_SwitchDevice($name, $valveDevice, "on");
    }

    # Set end time
    Gartenbewaesserung_SetEndTime($hash, $duration);

    my $index = $hash->{HELPER}{wateringIndex} + 1;
    my $total = $hash->{HELPER}{totalValves};

    my $valveLabel = Gartenbewaesserung_CircuitLabel($hash, $valveNum);

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "phase", "watering");
    $hash->{HELPER}{valveOpenTime} = int(time());
    readingsBulkUpdate($hash, "currentValve", $valveNum);
    readingsBulkUpdate($hash, "currentValveName", Gartenbewaesserung_ValveName($hash, $valveNum));
    readingsBulkUpdate($hash, "cycleProgress", "$index/$total");
    readingsEndUpdate($hash, 1);

    Log3 $name, 3, "$name: Valve $valveLabel opened for $duration minutes ($index/$total)";

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
    readingsSingleUpdate($hash, "currentValveName", "none", 1);

    # Turn off pump
    my $pumpDevice = AttrVal($name, "pumpDevice", "");
    if($pumpDevice ne "") {
        Gartenbewaesserung_SwitchDevice($name, $pumpDevice, "off");
    }

    Gartenbewaesserung_NoteValveDraw($hash, $valveNum);

    # Check if we have remaining time (pause is needed)
    if(defined($hash->{HELPER}{valveRemainingTime}) && $hash->{HELPER}{valveRemainingTime} > 0) {
        # Pause nur, wenn das Fass sie braucht. Bei vollem Fass gibt es nichts
        # nachzufuellen und nichts abzuwarten - dann laeuft der Kreis einfach
        # weiter (siehe BarrelNeedsRefill).
        if(!Gartenbewaesserung_BarrelNeedsRefill($hash)) {
            Log3 $name, 3, "$name: Valve $valveNum has remaining time, but the barrel is "
                . "full - skipping the refill pause and carrying on";
            $hash->{HELPER}{lastPauseEnd} = time();
            InternalTimer(gettimeofday() + 2, sub {
                Gartenbewaesserung_OpenValve($hash, $valveNum);
            }, $hash);
            return;
        }
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
        # NICHT zurueck nach NextValve: dort steht der Index unveraendert, die
        # Fuellstandspruefung faellt wieder gleich aus und ruft wieder hierher -
        # eine Endlosrekursion ohne Timer, die FHEM in derselben Sekunde
        # blockiert (in der Nacht zum 23.08.2026 genau so passiert). Der
        # Kreis-Modus macht es schon richtig: FillBarrelForCircuit ruft ohne
        # Ventil RunCircuit, also den Verbraucher statt des Verteilers.
        Log3 $name, 2, "$name: No barrel fill valve configured, continuing with the valve";
        my $queue = $hash->{HELPER}{wateringQueue};
        my $index = $hash->{HELPER}{wateringIndex};
        if(ref($queue) eq "ARRAY" && defined($index) && $index < scalar(@$queue)) {
            Gartenbewaesserung_OpenValve($hash, $queue->[$index]);
        }
        else {
            Gartenbewaesserung_FinishWatering($hash);
        }
        return;
    }

    Gartenbewaesserung_SwitchDevice($name, $fillValve, "on");
    Gartenbewaesserung_NoteNonRainFill($hash, "mains supply");
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
        # This water came from the IBC, not from the sky. Clear the harvest trigger,
        # otherwise the caller would pump it straight back up once the transfer ends.
        Gartenbewaesserung_NoteNonRainFill($hash, "IBC-to-barrel transfer");
        if($hash->{HELPER}{barrelEmptyRefilling}) {
            # Dieser Weg beginnt bei leerem Fass und endet hier auf barrelFull -
            # er hat also genau barrelUsableVolume bewegt und ist der einzige,
            # aus dem sich die Schwerkraftrate lernen laesst. Der Aufruf fehlte.
            Gartenbewaesserung_NoteIbcToBarrelStop($hash, "barrelFull");
            Gartenbewaesserung_StopBarrelEmptyRefill($hash);
        }
        else {
            Gartenbewaesserung_NoteIbcToBarrelStop($hash, "barrelFull");
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
            # The barrel was filled from the IBC, not by rain. Clear the harvest
            # trigger - otherwise this water is pumped straight back up once the
            # watering cycle ends. The ibcToBarrelActive branch above does not cover
            # this path: a watering pause never sets that flag, it only records
            # pauseSource.
            Gartenbewaesserung_NoteNonRainFill($hash, "IBC-to-barrel (pause)");
            Gartenbewaesserung_NoteIbcToBarrelStop($hash, "barrelFull");

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
        readingsBulkUpdate($hash, "currentValveName", "none");
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
        readingsBulkUpdate($hash, "currentValveName", "none");
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
            # Ordering follows pumpStartDelay (positive = pump first, negative/zero
            # = valve first); bail out if the refill pause ended during the delay.
            my $delay = AttrVal($name, "pumpStartDelay", 3);
            if($delay > 0) {
                Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelPump, "on");
                InternalTimer(gettimeofday() + $delay, sub {
                    return if(!$hash->{HELPER}{barrelEmptyRefillPause});
                    Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelValve, "on") if($ibcToBarrelValve ne "");
                }, $hash);
            }
            elsif($delay < 0) {
                Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelValve, "on") if($ibcToBarrelValve ne "");
                InternalTimer(gettimeofday() + abs($delay), sub {
                    return if(!$hash->{HELPER}{barrelEmptyRefillPause});
                    Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelPump, "on");
                }, $hash);
            }
            else {
                Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelValve, "on") if($ibcToBarrelValve ne "");
                Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelPump, "on");
            }
        }
        elsif($ibcToBarrelValve ne "") {
            Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelValve, "on");
        }

        $hash->{HELPER}{barrelEmptyRefillPauseSource} = "ibc";
        Gartenbewaesserung_NoteIbcToBarrelStart($hash);
        Log3 $name, 3, "$name: Refill pause: using IBC as source";
    }
    else {
        my $fillValve = AttrVal($name, "barrelFillValveDevice", "");
        if($fillValve ne "") {
            Gartenbewaesserung_SwitchDevice($name, $fillValve, "on");
            Gartenbewaesserung_NoteNonRainFill($hash, "mains supply");
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

    # Auch das hier war ein Nachfuellen - die Uhr fuer wateringPauseInterval muss
    # deshalb neu anlaufen. Ohne das zaehlt sie WANDZEIT statt Giesszeit: am
    # 21.08.2026 lag zwischen dem letzten Pausenende (22:49:28) und dem Weiter-
    # giessen (23:08:29) ein 12-minuetiges Fass-leer-Nachfuellen. Die Uhr stand
    # damit auf 19 min, das Ventil bekam eine Laufzeit von NULL Minuten, ging in
    # derselben Sekunde wieder zu und stiess die naechste Pause an - in ein
    # gerade eben vollgelaufenes Fass hinein.
    $hash->{HELPER}{lastPauseEnd} = time();

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
# Recover from a no-water abort once a water source reports water again:
# barrel full (the authoritative signal when barrelFullSensorDevice exists) or
# IBC no longer empty. Rain alone is NOT used - light drizzle does not actually
# refill the barrel; if rain fills it, the barrel-full sensor reports it anyway.
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
        Gartenbewaesserung_StopIBCFill($hash, "barrelEmpty");
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
            Gartenbewaesserung_NoteNonRainFill($hash, "mains supply");
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
            Gartenbewaesserung_NoteIbcToBarrelStart($hash);

            if($ibcToBarrelPump ne "") {
                # Ordering follows pumpStartDelay (positive = pump first, negative/zero
                # = valve first); bail out if the refill was stopped during the delay.
                my $delay = AttrVal($name, "pumpStartDelay", 3);
                if($delay > 0) {
                    Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelPump, "on");
                    Log3 $name, 4, "$name: Started IBC to barrel pump (barrel empty refill)";
                    InternalTimer(gettimeofday() + $delay, sub {
                        return if(!$hash->{HELPER}{barrelEmptyRefilling});
                        Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelValve, "on");
                        Log3 $name, 4, "$name: Opened IBC to barrel valve (barrel empty refill)";
                    }, $hash);
                }
                elsif($delay < 0) {
                    Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelValve, "on");
                    Log3 $name, 4, "$name: Opened IBC to barrel valve (barrel empty refill, negative delay)";
                    InternalTimer(gettimeofday() + abs($delay), sub {
                        return if(!$hash->{HELPER}{barrelEmptyRefilling});
                        Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelPump, "on");
                        Log3 $name, 4, "$name: Started IBC to barrel pump after valve (barrel empty refill)";
                    }, $hash);
                }
                else {
                    Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelValve, "on");
                    Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelPump, "on");
                    Log3 $name, 4, "$name: Opened IBC to barrel valve, then pump (barrel empty refill, no delay)";
                }
            }
            else {
                Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelValve, "on");
                Log3 $name, 4, "$name: Opened IBC to barrel valve (barrel empty refill, gravity)";
            }

            my $duration = AttrVal($name, "ibcToBarrelDuration", 15);
            InternalTimer(gettimeofday() + ($duration * 60), sub {
                Gartenbewaesserung_StopBarrelEmptyRefill($hash);
            }, $hash);

            readingsBeginUpdate($hash);
            readingsBulkUpdate($hash, "ibcToBarrelActive", "yes");
            readingsBulkUpdate($hash, "state", "stopped - barrel empty - refilling");
            readingsEndUpdate($hash, 1);
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

    # Auch das war ein Nachfuellen: die Uhr fuer wateringPauseInterval neu
    # starten, sonst zaehlt sie Wandzeit statt Giesszeit (siehe
    # StopBarrelEmptyRefillPause - dort steht die ausfuehrliche Begruendung).
    $hash->{HELPER}{lastPauseEnd} = time();

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
    readingsBulkUpdate($hash, "currentValveName", "none");
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

    # "stop" heisst stop - auch eine laufende Leitungswasser-Befuellung. Die
    # Runde selbst ist oben schon abgeschaltet worden, hier faellt der Auftrag.
    Gartenbewaesserung_MainsFillIbcStop($hash, "stopped by hand");

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
    readingsBulkUpdate($hash, "currentValveName", "none");
    readingsBulkUpdate($hash, "pauseActive", "no");
    readingsBulkUpdate($hash, "ibcToBarrelActive", "no");
    readingsBulkUpdate($hash, "ibcFilling", "no");
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
    Gartenbewaesserung_StopIBCFill($hash, "watering");
    Gartenbewaesserung_StopIBCtoBarrel($hash);

    # Check if barrel is empty - do not run pump
    if(ReadingsVal($name, "barrelEmpty", "no") eq "yes") {
        return "Barrel is empty - pump cannot be started";
    }

    my $valveLabel = Gartenbewaesserung_CircuitLabel($hash, $valveNum);

    # Mark current valve first so the delayed callbacks below can validate it
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "state", "manual");
    readingsBulkUpdate($hash, "phase", "manual watering");
    $hash->{HELPER}{valveOpenTime} = int(time());
    readingsBulkUpdate($hash, "currentValve", $valveNum);
    readingsBulkUpdate($hash, "currentValveName", Gartenbewaesserung_ValveName($hash, $valveNum));
    readingsEndUpdate($hash, 1);

    # Start pump/valve honoring pumpStartDelay (same ordering rules as OpenValve):
    # positive = pump first, then valve; negative/zero = valve first, then pump
    my $pumpDevice = AttrVal($name, "pumpDevice", "");
    my $delay = AttrVal($name, "pumpStartDelay", 3);

    if($pumpDevice ne "") {
        if($delay > 0) {
            # Positive delay: pump FIRST, valve after delay
            Gartenbewaesserung_SwitchDevice($name, $pumpDevice, "on");
            Gartenbewaesserung_StartPumpWatchdog($hash);
            InternalTimer(gettimeofday() + $delay, sub {
                return if(ReadingsVal($name, "currentValve", "none") ne $valveNum);
                Gartenbewaesserung_SwitchDevice($name, $valveDevice, "on");
                Log3 $name, 4, "$name: Manual valve $valveNum opened after pump delay";
            }, $hash);
        }
        elsif($delay < 0) {
            # Negative delay: valve FIRST, pump after |delay|
            Gartenbewaesserung_SwitchDevice($name, $valveDevice, "on");
            InternalTimer(gettimeofday() + abs($delay), sub {
                return if(ReadingsVal($name, "currentValve", "none") ne $valveNum);
                Gartenbewaesserung_SwitchDevice($name, $pumpDevice, "on");
                Gartenbewaesserung_StartPumpWatchdog($hash);
                Log3 $name, 4, "$name: Manual pump started after valve (negative delay)";
            }, $hash);
        }
        else {
            # Zero delay: valve FIRST, then pump
            Gartenbewaesserung_SwitchDevice($name, $valveDevice, "on");
            Gartenbewaesserung_SwitchDevice($name, $pumpDevice, "on");
            Gartenbewaesserung_StartPumpWatchdog($hash);
        }
    }
    else {
        Gartenbewaesserung_SwitchDevice($name, $valveDevice, "on");
    }

    Log3 $name, 3, "$name: Manual valve $valveLabel started";

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
    readingsBulkUpdate($hash, "currentValveName", "none");
    readingsEndUpdate($hash, 1);

    return undef;
}

##############################################################################
# Start IBC filling (from barrel with pump)
##############################################################################
sub Gartenbewaesserung_StartIBCFill {
    my ($hash, $manual, $fromFloat) = @_;
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

    # Start pump to move water from barrel to IBC.
    # Ordering follows pumpStartDelay: positive = pump first (build pressure),
    # negative/zero = valve first so the pump never runs against a closed valve.
    my $pumpDevice = AttrVal($name, "pumpDevice", "");

    # Mark as filling immediately so StopIBCFill can always tear both devices
    # down - even if the fill is stopped during the pump/valve delay window.
    $hash->{HELPER}{ibcFilling} = 1;

    # Ab hier taugt der Lauf nicht mehr zum Lernen einer GIESSRATE. drawTainted
    # markierte bisher nur Wasser, das DAZUKOMMT (Regen, IBC, Stadtwasser). Die
    # Pumpe ist der einzige Weg, auf dem Wasser ANDERS ABGEHT als durch ein
    # Ventil - und LearnWateringFlow rechnet blind das ganze Fassvolumen der
    # Ventilzeit zu. Am 23.08. lief Kreis 3 elf Minuten (78 l), danach hob die
    # Pumpe die restlichen 70 l in den IBC; gelernt wurden 148/11 = 13,5 l/min
    # statt der tatsaechlichen 7,1.
    # Die Foerderrate der Pumpe selbst ist davon nicht betroffen: die lernt
    # RecordIbcFillRun ueber $complete (voll -> leer, ohne Stadtwasser) und
    # sieht drawTainted gar nicht an.
    $hash->{HELPER}{drawTainted} = 1;
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "ibcFilling", "yes");
    readingsBulkUpdate($hash, "ibcFillStarted", TimeNow());
    # Auch im state sichtbar machen - die Gegenrichtung tut das laengst, die
    # Ernte fehlte. Ohne das steht das Geraet waehrend des Laufs auf 'idle'.
    readingsBulkUpdate($hash, "state", "ibc filling");
    # Consume the harvest trigger: the next automatic harvest needs new rain.
    # Without this the barrel could be refilled by gravity from the IBC during a
    # watering pause and immediately pumped back up again.
    readingsBulkUpdate($hash, "rainSinceHarvest_mm", "0");
    readingsEndUpdate($hash, 1);

    # Measurement: remember when this run began and whether it started from a full
    # barrel. Only a full->empty run moves a known volume and can teach the rate.
    #
    # Zweiter bekannter Startpunkt: die Schwimmerhoehe. Eine Stadtwasser-Runde
    # setzt genau dort an und pumpt bis zum Trockenlauf, bewegt also
    # barrelFloatLevel - eine am Wasserzaehler gemessene Menge, nicht geschaetzt.
    # Nur ein voller Lauf braucht Regen; ohne diesen zweiten Fall bliebe die
    # Pumpenrate in trockenen Wochen unbemerkt stehen, waehrend der Filter zusetzt.
    $hash->{HELPER}{ibcFillStartTime} = int(time());
    $hash->{HELPER}{ibcFillFromFull}  = (ReadingsVal($name, "barrelFull", "no") eq "yes") ? 1 : 0;
    $hash->{HELPER}{ibcFillFromFloat} = ($fromFloat && !$hash->{HELPER}{ibcFillFromFull}) ? 1 : 0;
    $hash->{HELPER}{ibcFillMainsAtStart} = Gartenbewaesserung_MainsSupplyState($hash);
    # Obergrenze fuer eine ratenbasierte Buchung: mehr als drinsteht kann die
    # Pumpe nicht herausholen.
    my $lvlAtStart = ReadingsVal($name, "barrelLevel_l", "");
    $hash->{HELPER}{ibcFillBarrelAtStart} =
        ($lvlAtStart =~ /^-?\d+(?:\.\d+)?$/ && $lvlAtStart > 0) ? $lvlAtStart : undef;
    Gartenbewaesserung_ArmIbcFullByLevel($hash);

    if($pumpDevice ne "") {
        my $delay = AttrVal($name, "pumpStartDelay", 3);
        if($delay > 0) {
            # Pump first, then valve after delay
            Gartenbewaesserung_SwitchDevice($name, $pumpDevice, "on");
            Log3 $name, 4, "$name: Pump started for IBC filling";
            InternalTimer(gettimeofday() + $delay, sub {
                return if(!$hash->{HELPER}{ibcFilling});   # stopped during delay
                Gartenbewaesserung_SwitchDevice($name, $ibcValve, "on");
                Log3 $name, 3, "$name: IBC filling started (from barrel, pump then valve)";
            }, $hash);
        }
        elsif($delay < 0) {
            # Valve first, then pump after |delay|
            Gartenbewaesserung_SwitchDevice($name, $ibcValve, "on");
            InternalTimer(gettimeofday() + abs($delay), sub {
                return if(!$hash->{HELPER}{ibcFilling});   # stopped during delay
                Gartenbewaesserung_SwitchDevice($name, $pumpDevice, "on");
                Log3 $name, 3, "$name: IBC filling started (valve first, then pump)";
            }, $hash);
        }
        else {
            # Zero: valve first, then pump (no delay)
            Gartenbewaesserung_SwitchDevice($name, $ibcValve, "on");
            Gartenbewaesserung_SwitchDevice($name, $pumpDevice, "on");
            Log3 $name, 3, "$name: IBC filling started (from barrel, valve then pump)";
        }
    }
    else {
        # No pump - just open valve (gravity feed from rain)
        Gartenbewaesserung_SwitchDevice($name, $ibcValve, "on");
        Log3 $name, 3, "$name: IBC filling started (gravity feed)";
    }

    return undef;
}

##############################################################################
# Is the mains top-up available right now?
#
# Returns "on", "off" or "" when no mainsSupplyDevice is configured. Matters for
# the statistics, not for control: while the mains float can refill the barrel,
# water pumped from the barrel into the IBC is not purely harvested rain.
##############################################################################
sub Gartenbewaesserung_MainsSupplyState {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    my $def = AttrVal($name, "mainsSupplyDevice", "");
    return "" if($def eq "");

    return Gartenbewaesserung_GetSensorValue($name, $def,
        AttrVal($name, "mainsSupplyActiveValue", ""),
        AttrVal($name, "mainsSupplyInactiveValue", "")) ? "on" : "off";
}

##############################################################################
# IBC level estimate.
#
# The IBC has no level sensor, only the two end switches. The level is therefore
# carried along: what the pump moves up is added, what runs back down by gravity
# is subtracted. That integration drifts - both flow rates are learned averages,
# and the gravity rate is not even constant, since a full IBC pushes harder than
# an almost empty one. So every anchor point available is used to reset it:
# ibcEmpty puts the level at 0, ibcFull at ibcUsableVolume, and
# "set <name> ibcLevel" takes a value read off the tank. ibcLevelAnchor records
# where the current number last came from - the older that is, the more drift
# has had a chance to accumulate.
##############################################################################
sub Gartenbewaesserung_SetIbcLevel {
    my ($hash, $liters, $reason, $anchor) = @_;
    my $name = $hash->{NAME};

    my $capacity = AttrVal($name, "ibcUsableVolume", 0);
    return if($capacity <= 0);

    $liters = 0 if($liters < 0);
    $liters = $capacity if($liters > $capacity);

    # Nachkommaanteil mitfuehren - siehe SetBarrelLevel. Hier fallen die Buchungen
    # zwar gross aus (ein Fass je Transfer), aber der Fehler waere derselbe.
    my $whole = sprintf("%.0f", $liters);
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "ibcLevel_l", $whole);
    readingsBulkUpdate($hash, ".ibcLevelFrac", sprintf("%.3f", $liters - $whole));
    readingsBulkUpdate($hash, "ibcLevel_pct", sprintf("%.0f", 100 * $liters / $capacity));
    readingsBulkUpdate($hash, "ibcLevelAnchor", TimeNow() . " " . $reason) if($anchor);
    readingsEndUpdate($hash, 1);
}

sub Gartenbewaesserung_AdjustIbcLevel {
    my ($hash, $delta, $reason) = @_;
    my $name = $hash->{NAME};

    return if(AttrVal($name, "ibcUsableVolume", 0) <= 0);
    return if(!$delta);

    # No starting point yet: wait for an anchor rather than invent one
    my $level = ReadingsVal($name, "ibcLevel_l", "");
    return if($level !~ /^-?\d+(?:\.\d+)?$/);

    my $frac = ReadingsVal($name, ".ibcLevelFrac", 0);
    $level += $frac if($frac =~ /^-?\d+(?:\.\d+)?$/);
    Gartenbewaesserung_SetIbcLevel($hash, $level + $delta, $reason, 0);
    Log3 $name, 4, sprintf("%s: IBC level %+.0f l (%s) -> %s l",
        $name, $delta, $reason, ReadingsVal($name, "ibcLevel_l", "?"));
}

##############################################################################
# Barrel level estimate.
#
# Same idea as the IBC estimate, but the barrel is better instrumented - three
# anchors instead of two. barrelFull puts the level at barrelUsableVolume,
# barrelEmpty at 0, and with the mains supply open the float valve guarantees
# barrelFloatLevel as a floor once the bottom contact has cleared.
#
# The percentage in barrelLevel used to be pure simulation: start at 100, minus
# 12 per valve. That is kept as the fallback so nothing changes where
# barrelUsableVolume is unset; where the volume is known the percentage is
# derived from the litres instead, and barrelFillThreshold keeps working
# unchanged - just on real numbers.
##############################################################################
sub Gartenbewaesserung_SetBarrelLevel {
    my ($hash, $liters, $reason, $anchor) = @_;
    my $name = $hash->{NAME};

    my $capacity = AttrVal($name, "barrelUsableVolume", 0);
    return if($capacity <= 0);

    $liters = 0 if($liters < 0);
    $liters = $capacity if($liters > $capacity);

    # Der Nachkommaanteil wird mitgefuehrt statt weggeworfen. Das Reading bleibt
    # in ganzen Litern (so liest es sich, so zeigt es die Kachel), der Rest liegt
    # versteckt daneben und geht in die naechste Buchung ein. Ohne das verliert
    # JEDE wiederholte kleine Buchung ihren Bruchteil, und zwar systematisch in
    # dieselbe Richtung: der Stadtwasser-Zulauf stieg in 4er-Schritten statt 4,4
    # (v1.0.73), und jeder 0,2-mm-Kipp der Regenwippe (7,2 l) wurde als 7 gebucht.
    my $whole = sprintf("%.0f", $liters);
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "barrelLevel_l", $whole);
    readingsBulkUpdate($hash, ".barrelLevelFrac", sprintf("%.3f", $liters - $whole));
    readingsBulkUpdate($hash, "barrelLevel", sprintf("%.0f", 100 * $liters / $capacity));
    readingsBulkUpdate($hash, "barrelLevelAnchor", TimeNow() . " " . $reason) if($anchor);
    readingsEndUpdate($hash, 1);
}

# Fuellstand einschliesslich des mitgefuehrten Bruchteils.
sub Gartenbewaesserung_BarrelLevelExact {
    my ($hash) = @_;
    my $l = ReadingsVal($hash->{NAME}, "barrelLevel_l", "");
    return undef if($l !~ /^-?\d+(?:\.\d+)?$/);
    my $f = ReadingsVal($hash->{NAME}, ".barrelLevelFrac", 0);
    $f = 0 if($f !~ /^-?\d+(?:\.\d+)?$/);
    return $l + $f;
}

# Returns 1 when the litre estimate handled it, 0 when the caller should fall
# back to the old percentage simulation.
sub Gartenbewaesserung_AdjustBarrelLevel {
    my ($hash, $delta, $reason) = @_;
    my $name = $hash->{NAME};

    return 0 if(AttrVal($name, "barrelUsableVolume", 0) <= 0);

    my $level = ReadingsVal($name, "barrelLevel_l", "");
    return 0 if($level !~ /^-?\d+(?:\.\d+)?$/);

    # Anything that puts water in makes the accumulated valve time useless for
    # learning the draw rate - the barrel no longer empties on watering alone.
    $hash->{HELPER}{drawTainted} = 1 if($delta > 0);

    return 1 if(!$delta);
    # Vom EXAKTEN Stand aus weiterrechnen, nicht vom gerundeten Reading - sonst
    # faellt der Bruchteil bei jeder Buchung wieder heraus.
    $level = Gartenbewaesserung_BarrelLevelExact($hash) // $level;
    Gartenbewaesserung_SetBarrelLevel($hash, $level + $delta, $reason, 0);
    Log3 $name, 4, sprintf("%s: barrel level %+.0f l (%s) -> %s l",
        $name, $delta, $reason, ReadingsVal($name, "barrelLevel_l", "?"));
    return 1;
}

# With the mains open and nothing drawing, the barrel cannot sit below the level
# the float valve holds it at.
# Zulauf aus der Hauswasserleitung mitrechnen.
#
# Bis v1.0.62 kannte das Modul dafuer nur ApplyBarrelFloatFloor: einen SPRUNG
# auf barrelFloatLevel. Der hatte zwei Loecher. Erstens lief er ausschliesslich
# in UpdateSensorReadings, und das wird nur beim Define, bei "set refreshSensors"
# und beim Aendern eines Sensor-Attributs aufgerufen - im laufenden Betrieb also
# nie. Zweitens war er ein Sprung: der Fuellstand stand auf 0 und waere dann
# schlagartig auf die Schwimmerhoehe gegangen, statt mitzusteigen.
#
# Mit mainsFillFlow_lpm steigt er jetzt mit der gemessenen Rate. Der Deckel ist
# barrelFloatLevel: ueber ein Schwimmerventil steigt der Pegel nur bis zur
# Schwimmerhoehe, nicht bis zum Rand - stur weiterzuzaehlen wuerde ein volles
# Fass vortaeuschen, das es nie gibt. Ohne die Rate bleibt es beim alten Sprung,
# der jetzt wenigstens regelmaessig geprueft wird.
sub Gartenbewaesserung_MainsFillTick {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    my $rate = AttrVal($name, "mainsFillFlow_lpm", 0);
    if($rate <= 0) {
        delete $hash->{HELPER}{mainsFillAnchor};
        Gartenbewaesserung_ApplyBarrelFloatFloor($hash);
        return;
    }

    my $capacity = AttrVal($name, "barrelUsableVolume", 0);
    return if($capacity <= 0);

    if(Gartenbewaesserung_MainsSupplyState($hash) ne "on") {
        delete $hash->{HELPER}{mainsFillAnchor};
        return;
    }

    # Laeuft gerade ein anderer Transport, hat der seine eigene Buchhaltung -
    # sonst zaehlte dasselbe Wasser zweimal.
    if($hash->{HELPER}{watering}   || $hash->{HELPER}{circuitMode}
    || $hash->{HELPER}{ibcFilling} || $hash->{HELPER}{ibcToBarrelActive}
    || $hash->{HELPER}{barrelFilling} || $hash->{HELPER}{pauseActive}) {
        delete $hash->{HELPER}{mainsFillAnchor};
        return;
    }

    my $float = AttrVal($name, "barrelFloatLevel", 0);
    my $cap = ($float > 0 && $float < $capacity) ? $float : $capacity;

    my $now = int(time());
    # Exakt lesen: AdjustBarrelLevel rechnet seit v1.0.75 den Bruchteil mit, ein
    # $add gegen den GERUNDETEN Stand wuerde ihn also doppelt zaehlen.
    my $level = Gartenbewaesserung_BarrelLevelExact($hash);
    return if(!defined($level));

    # Anker statt Schrittweite. Frueher wurde je Takt "rate * 60 s" addiert und
    # der Startpunkt vorgerueckt - aber SetBarrelLevel speichert ganze Liter, und
    # AdjustBarrelLevel rechnet vom GERUNDETEN Reading weiter. Bei 4,4 l/min ging
    # damit jede Minute 0,4 l verloren: der Pegel stieg sichtbar in 4er-Schritten
    # statt 4,4, und das Fass galt rund zwei Minuten zu spaet als voll.
    # Jetzt wird gegen den Anker gerechnet, der Rundungsfehler haeuft sich also
    # nicht mehr an, sondern bleibt bei hoechstens einem halben Liter.
    # Erster Durchlauf: nur den Anker setzen. Kostet die angefangene Minute, ist
    # aber ehrlicher, als eine unbekannte Vorlaufzeit gutzuschreiben - wann der
    # Hahn wirklich aufging, weiss das Modul nicht.
    my $anchor = $hash->{HELPER}{mainsFillAnchor};
    if(!defined($anchor) || ref($anchor) ne "HASH") {
        $hash->{HELPER}{mainsFillAnchor} = { t => $now, l => $level };
        return;
    }
    return if($now <= $anchor->{t} || $level >= $cap);

    my $soll = $anchor->{l} + $rate * ($now - $anchor->{t}) / 60;
    $soll = $cap if($soll > $cap);
    my $add = $soll - $level;
    return if($add <= 0);

    Gartenbewaesserung_AdjustBarrelLevel($hash, $add, "mains supply");
    # Dieses Wasser kam nicht vom Dach - eine daraus gelernte Giessrate waere falsch.
    $hash->{HELPER}{drawTainted} = 1;
}

# Foerderrate holen: gelerntes Reading zuerst, dann das gleichnamige Attribut.
#
# Gelernt wird nur aus vollstaendigen Laeufen, und Readings ueberleben einen
# harten Abschuss nicht immer - am 23.08.2026 war ibcToBarrelFlow_lpm nach zwei
# Statefile-Rueckfaellen schlicht weg. Ohne Rate rechnet das Modul die
# Fuellstaende nicht mit und die watertank-Kachel steht still, obwohl das Rohr
# leuchtet. Das Attribut ist der Boden darunter: einmal gesetzt, bleibt es.
# Dieselbe Reihenfolge wie bei wateringFlow_lpm und valve<N>Flow_lpm.
sub Gartenbewaesserung_FlowRate {
    my ($hash, $which) = @_;
    my $name = $hash->{NAME};

    foreach my $v (ReadingsVal($name, $which, 0), AttrVal($name, $which, 0)) {
        next if($v !~ /^\d+(?:\.\d+)?$/ || $v <= 0);
        return $v;
    }
    return 0;
}

sub Gartenbewaesserung_ApplyBarrelFloatFloor {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    my $float = AttrVal($name, "barrelFloatLevel", 0);
    return if($float <= 0 || AttrVal($name, "barrelUsableVolume", 0) <= 0);
    return if(Gartenbewaesserung_MainsSupplyState($hash) ne "on");
    return if(ReadingsVal($name, "barrelEmpty", "no") eq "yes");
    return if($hash->{HELPER}{watering}   || $hash->{HELPER}{circuitMode}
           || $hash->{HELPER}{ibcFilling} || $hash->{HELPER}{ibcToBarrelActive}
           || $hash->{HELPER}{barrelFilling} || $hash->{HELPER}{pauseActive});

    my $level = ReadingsVal($name, "barrelLevel_l", "");
    return if($level !~ /^-?\d+(?:\.\d+)?$/ || $level >= $float);

    Gartenbewaesserung_SetBarrelLevel($hash, $float, "float valve", 1);
    $hash->{HELPER}{drawTainted} = 1;
}

# One valve has just closed: book its draw and remember how long it was open.
sub Gartenbewaesserung_NoteValveDraw {
    my ($hash, $valveNum) = @_;
    my $name = $hash->{NAME};

    # Beim Leermelden hat NoteOpenValveDrawTime die offene Ventilzeit bereits
    # gebucht und SetBarrelLevel den Fuellstand auf 0 verankert. Hier ist dann
    # nichts mehr zu tun - sonst zaehlten dieselben Minuten doppelt.
    if(delete $hash->{HELPER}{drawBooked}) {
        delete $hash->{HELPER}{valveOpenTime};
        return;
    }

    my $opened = $hash->{HELPER}{valveOpenTime};
    delete $hash->{HELPER}{valveOpenTime};
    my $minutes = $opened ? (int(time()) - $opened) / 60 : 0;
    $minutes = 0 if($minutes < 0);
    $hash->{HELPER}{drawMinutes} = ($hash->{HELPER}{drawMinutes} || 0) + $minutes;
    # Zusaetzlich je Kreis, damit ein Lauf, an dem nur einer beteiligt war,
    # seine eigene Rate bekommen kann.
    if(defined($valveNum) && $valveNum =~ /^\d+$/ && $minutes > 0) {
        $hash->{HELPER}{drawByValve}{$valveNum} =
            ($hash->{HELPER}{drawByValve}{$valveNum} || 0) + $minutes;
    }

    my $capacity = AttrVal($name, "barrelUsableVolume", 0);
    if($capacity > 0) {
        # Vom Speziellen zum Allgemeinen: die Rate DIESES Kreises schlaegt die
        # gemeinsame, denn jeder Kreis hat andere Sprenger und nicht gleich
        # viele. Danach die gelernte Gesamtrate, dann das Attribut, zuletzt der
        # Pauschalabzug - der ignoriert die Laufzeit und liegt bei laengeren
        # Ventilen weit daneben, deshalb der Log-Hinweis.
        my $vn = (defined($valveNum) && $valveNum =~ /^\d+$/) ? $valveNum : "";
        my $rate = 0;
        foreach my $candidate (
            $vn ne "" ? ReadingsVal($name, "valve${vn}Flow_lpm", 0) : 0,
            $vn ne "" ? AttrVal($name, "valve${vn}Flow_lpm", 0) : 0,
            ReadingsVal($name, "wateringFlow_lpm", 0),
            AttrVal($name, "wateringFlow_lpm", 0),
        ) {
            next if($candidate !~ /^\d+(?:\.\d+)?$/ || $candidate <= 0);
            $rate = $candidate;
            last;
        }

        my $drawn;
        if($rate > 0 && $minutes > 0) {
            $drawn = $rate * $minutes;
        }
        else {
            $drawn = $capacity * 0.12;
            my $which = (defined($valveNum) && $valveNum =~ /^\d+$/)
                ? "valve${valveNum}Flow_lpm" : "wateringFlow_lpm";
            Log3 $name, 3, sprintf("%s: no watering flow rate known - deducting a flat %.0f l for "
                . "%.1f min of valve time. Set attr %s for a level estimate that follows the "
                . "actual run length.", $name, $drawn, $minutes, $which);
        }
        return if(Gartenbewaesserung_AdjustBarrelLevel($hash, -$drawn, "watering"));
    }

    my $current = ReadingsVal($name, "barrelLevel", 100);
    $current = 100 if($current !~ /^-?\d+(?:\.\d+)?$/);
    my $new = $current - 12;
    $new = 0 if($new < 0);
    readingsSingleUpdate($hash, "barrelLevel", $new, 1);
}

# Ein noch offenes Ventil in die Verbrauchsrechnung aufnehmen, ohne es zu
# schliessen.
sub Gartenbewaesserung_NoteOpenValveDrawTime {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    my $opened = $hash->{HELPER}{valveOpenTime};
    return if(!$opened);

    my $minutes = (int(time()) - $opened) / 60;
    return if($minutes <= 0);

    my $valveNum = ReadingsVal($name, "currentValve", "none");
    $hash->{HELPER}{drawMinutes} = ($hash->{HELPER}{drawMinutes} || 0) + $minutes;
    if($valveNum =~ /^\d+$/) {
        $hash->{HELPER}{drawByValve}{$valveNum} =
            ($hash->{HELPER}{drawByValve}{$valveNum} || 0) + $minutes;
    }
    # Die Zeit ist jetzt gebucht - NoteValveDraw darf sie beim Schliessen des
    # Ventils nicht ein zweites Mal nehmen. Blosses Zuruecksetzen von
    # valveOpenTime reicht nicht: NoteValveDraw faellt bei 0 Minuten in den
    # Pauschalabzug von 12 % samt irrefuehrender Log-Zeile.
    delete $hash->{HELPER}{valveOpenTime};
    $hash->{HELPER}{drawBooked} = 1;

    Log3 $name, 4, sprintf("%s: booked %.1f min of still-open valve %s before learning",
        $name, $minutes, $valveNum);
}

# A full barrel emptied by watering alone tells us how much a minute of valve
# time costs - the same trick that measures the pump, applied to the consumer.
sub Gartenbewaesserung_LearnWateringFlow {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    my $minutes  = $hash->{HELPER}{drawMinutes} || 0;
    my $tainted  = $hash->{HELPER}{drawTainted} || 0;
    my $capacity = AttrVal($name, "barrelUsableVolume", 0);
    my $byValve  = $hash->{HELPER}{drawByValve} || {};
    $hash->{HELPER}{drawMinutes} = 0;
    delete $hash->{HELPER}{drawByValve};

    return if($tainted || $minutes <= 0 || $capacity <= 0);
    return if(ReadingsVal($name, "barrelLevelAnchor", "") !~ /barrelFull/);

    # War nur ein einziger Kreis beteiligt, gehoert das Volumen eindeutig ihm -
    # dann lernen wir seine Rate statt einer Mischung ueber alle.
    my @valves = keys %$byValve;
    my $target = (scalar(@valves) == 1) ? "valve$valves[0]Flow_lpm" : "wateringFlow_lpm";

    my $measured = $capacity / $minutes;
    my $old = ReadingsVal($name, $target, 0);
    $old = 0 if($old !~ /^\d+(?:\.\d+)?$/);
    my $new = ($old > 0) ? ($old * 0.7 + $measured * 0.3) : $measured;
    readingsSingleUpdate($hash, $target, sprintf("%.1f", $new), 1);
    Log3 $name, 3, sprintf("%s: full barrel emptied by %.1f min of watering (%s) "
        . "= %.1f l/min (learned rate now %.1f)", $name, $minutes,
        (scalar(@valves) == 1) ? "circuit $valves[0]" : scalar(@valves) . " circuits",
        $measured, $new);
}

# Does the level estimate consider the IBC full? Only with ibcFullFromLevel set,
# and only once a level is known at all.
sub Gartenbewaesserung_IbcFullByLevelState {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    return 0 if(!AttrVal($name, "ibcFullFromLevel", 0));
    my $capacity = AttrVal($name, "ibcUsableVolume", 0);
    my $level    = ReadingsVal($name, "ibcLevel_l", "");
    return 0 if($capacity <= 0 || $level !~ /^-?\d+(?:\.\d+)?$/);
    return ($level >= $capacity) ? 1 : 0;
}

# A fill is starting: work out how long the remaining headroom lasts at the
# learned pump rate and set an alarm clock for it. Without this the estimate
# could only block the NEXT run - the current one would overflow first.
sub Gartenbewaesserung_ArmIbcFullByLevel {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    RemoveInternalTimer($hash, "Gartenbewaesserung_IbcFullByLevel");
    return if(!AttrVal($name, "ibcFullFromLevel", 0));

    my $capacity = AttrVal($name, "ibcUsableVolume", 0);
    my $level    = ReadingsVal($name, "ibcLevel_l", "");
    my $rate     = Gartenbewaesserung_FlowRate($hash, "ibcFillFlow_lpm");
    return if($capacity <= 0 || $rate <= 0 || $level !~ /^-?\d+(?:\.\d+)?$/);

    my $headroom = $capacity - $level;
    if($headroom <= 0) {
        Gartenbewaesserung_IbcFullByLevel($hash);
        return;
    }

    my $minutes = $headroom / $rate;
    Log3 $name, 3, sprintf("%s: IBC has room for %.0f l = %.1f min at %.1f l/min",
        $name, $headroom, $minutes, $rate);
    InternalTimer(gettimeofday() + $minutes * 60, "Gartenbewaesserung_IbcFullByLevel", $hash);
}

sub Gartenbewaesserung_IbcFullByLevel {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    RemoveInternalTimer($hash, "Gartenbewaesserung_IbcFullByLevel");
    return if(!AttrVal($name, "ibcFullFromLevel", 0));

    Log3 $name, 3, "$name: IBC full according to the level estimate - stopping fill";
    Gartenbewaesserung_SetIbcLevel($hash,
        AttrVal($name, "ibcUsableVolume", 0), "level estimate", 1);
    readingsSingleUpdate($hash, "ibcFull", "yes", 1);
    Gartenbewaesserung_StopIBCFill($hash, "ibcFull (level)") if($hash->{HELPER}{ibcFilling});
}

##############################################################################
# Measurement for the IBC -> barrel direction (the "out" side of the level
# estimate). A watering pause feeds the barrel from the IBC by gravity without
# ever setting ibcToBarrelActive, so these runs are invisible otherwise.
##############################################################################
sub Gartenbewaesserung_NoteIbcToBarrelStart {
    my ($hash) = @_;
    $hash->{HELPER}{ibcToBarrelStartTime} = int(time());
    $hash->{HELPER}{ibcToBarrelFromEmpty} =
        (ReadingsVal($hash->{NAME}, "barrelEmpty", "no") eq "yes") ? 1 : 0;
    # Anfangsstand fuer den Buchungsdeckel: mehr als in das Fass hineinpasst kann
    # kein Transfer bewegen. Waehrend eines Transfers giesst nichts, der Kopfraum
    # aendert sich also nicht.
    my $lvl = ReadingsVal($hash->{NAME}, "barrelLevel_l", "");
    $hash->{HELPER}{ibcToBarrelBarrelAtStart} =
        ($lvl =~ /^-?\d+(?:\.\d+)?$/) ? $lvl : undef;
    # Erster Blick schon nach 5 s: oeffnet die Strecke in ein volles Fass, sind
    # das rund 1 l statt der 200 l von frueher. Danach reichen 30 s.
    RemoveInternalTimer($hash, "Gartenbewaesserung_IbcToBarrelWatchdog");
    InternalTimer(gettimeofday() + 5, "Gartenbewaesserung_IbcToBarrelWatchdog", $hash);
}

sub Gartenbewaesserung_NoteIbcToBarrelStop {
    my ($hash, $reason) = @_;
    my $name = $hash->{NAME};

    RemoveInternalTimer($hash, "Gartenbewaesserung_IbcToBarrelWatchdog");
    my $start = $hash->{HELPER}{ibcToBarrelStartTime};
    my $fromEmpty = $hash->{HELPER}{ibcToBarrelFromEmpty};
    my $barrelAtStart = $hash->{HELPER}{ibcToBarrelBarrelAtStart};
    delete $hash->{HELPER}{ibcToBarrelStartTime};
    delete $hash->{HELPER}{ibcToBarrelFromEmpty};
    delete $hash->{HELPER}{ibcToBarrelBarrelAtStart};
    return if(!$start);

    $reason = "unknown" if(!defined($reason) || $reason eq "");
    my $minutes = (int(time()) - $start) / 60;
    return if($minutes <= 0);

    # A transfer that started with an empty barrel and ended on barrelFull moved
    # exactly barrelUsableVolume - the same trick that measures the pump, applied
    # to the gravity side.
    my $volume = AttrVal($name, "barrelUsableVolume", 0);
    my $rate   = Gartenbewaesserung_FlowRate($hash, "ibcToBarrelFlow_lpm");
    $rate = 0 if($rate !~ /^\d+(?:\.\d+)?$/);

    my $moved = 0;
    my $measured = 0;
    if($fromEmpty && $reason eq "barrelFull" && $volume > 0) {
        $moved = $volume;
        $measured = $volume / $minutes;
        $rate = ($rate > 0) ? ($rate * 0.7 + $measured * 0.3) : $measured;
    }
    elsif($rate > 0) {
        $moved = $rate * $minutes;
        # Deckel: ins Fass passt nur, was noch Platz hat. Waehrend eines Transfers
        # ist das Giessen gestoppt, der Kopfraum steht also fest. Ohne den Deckel
        # bucht eine zu hohe Rate Wasser, das nie ankam - in der Nacht zum 24.08.
        # dreimal 255 l in ein Fass, das 148 fasst, weil die Strecke leer lief und
        # der Lauf bis maxDuration offen blieb.
        if($volume > 0 && defined($barrelAtStart)) {
            my $headroom = $volume - $barrelAtStart;
            $headroom = 0 if($headroom < 0);
            if($moved > $headroom) {
                Log3 $name, 3, sprintf("%s: IBC->barrel booking capped at %.0f l "
                    . "(rate would have given %.0f l in %.1f min - dry line or stale rate?)",
                    $name, $headroom, $moved, $minutes);
                $moved = $headroom;
            }
        }
    }

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "lastIbcToBarrelDuration", sprintf("%.1f", $minutes));
    readingsBulkUpdate($hash, "lastIbcToBarrelEnd", $reason);
    readingsBulkUpdate($hash, "lastIbcToBarrelVolume_l",
        $moved > 0 ? sprintf("%.0f", $moved) : "unknown");
    readingsBulkUpdate($hash, "ibcToBarrelFlow_lpm", sprintf("%.1f", $rate)) if($measured > 0);
    readingsEndUpdate($hash, 1);

    if($measured > 0) {
        Log3 $name, 3, sprintf("%s: complete IBC->barrel run: %.0f l in %.1f min "
            . "= %.1f l/min (learned rate now %.1f)", $name, $volume, $minutes, $measured, $rate);
    }
    else {
        Log3 $name, 3, sprintf("%s: IBC->barrel run ended (%s) after %.1f min",
            $name, $reason, $minutes);
    }

    if($moved > 0) {
        Gartenbewaesserung_AdjustIbcLevel($hash, -$moved, "IBC->barrel");
        Gartenbewaesserung_AdjustBarrelLevel($hash, $moved, "IBC->barrel");
    }
}

##############################################################################
# Measurement for the barrel -> IBC runs (groundwork for a level estimate).
#
# Records how long a run took and why it ended. A run that started with a full
# barrel and ended on barrelEmpty moved a known volume - barrelUsableVolume -
# so it also yields the current pump rate. Learning the rate this way keeps it
# honest as the filter clogs, instead of trusting a fixed value in an attribute.
##############################################################################
sub Gartenbewaesserung_RecordIbcFillRun {
    my ($hash, $reason) = @_;
    my $name = $hash->{NAME};

    my $start = $hash->{HELPER}{ibcFillStartTime};
    my $fromFull = $hash->{HELPER}{ibcFillFromFull};
    my $fromFloat = $hash->{HELPER}{ibcFillFromFloat};
    my $barrelAtStart = $hash->{HELPER}{ibcFillBarrelAtStart};
    delete $hash->{HELPER}{ibcFillStartTime};
    delete $hash->{HELPER}{ibcFillFromFull};
    delete $hash->{HELPER}{ibcFillFromFloat};
    delete $hash->{HELPER}{ibcFillBarrelAtStart};
    return 0 if(!$start);

    $reason = "unknown" if(!defined($reason) || $reason eq "");
    my $minutes = (int(time()) - $start) / 60;
    return 0 if($minutes <= 0);

    # Was the mains top-up available at any point during the run? Then the barrel
    # was refilled from the tap while the pump drained it, and the volume moved
    # into the IBC is not purely harvested rain.
    my $mainsStart = $hash->{HELPER}{ibcFillMainsAtStart} || "";
    delete $hash->{HELPER}{ibcFillMainsAtStart};
    my $mainsNow = Gartenbewaesserung_MainsSupplyState($hash);
    my $source = "unknown";
    if($mainsStart ne "" || $mainsNow ne "") {
        $source = ($mainsStart eq "on" || $mainsNow eq "on") ? "mixed" : "rain";
    }
    # Vom Nutzer angesagtes Fremdwasser schlaegt die Automatik: woher es kam,
    # kann das Modul nicht sehen - nur, dass es nicht vom Dach war.
    $source = "other" if(ReadingsVal($name, "waterSource", "rain") eq "other");

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "lastIbcFillDuration", sprintf("%.1f", $minutes));
    readingsBulkUpdate($hash, "lastIbcFillEnd", $reason);
    readingsBulkUpdate($hash, "lastIbcFillSource", $source);

    my $volume = AttrVal($name, "barrelUsableVolume", 0);
    my $float  = AttrVal($name, "barrelFloatLevel", 0);
    my $rate   = Gartenbewaesserung_FlowRate($hash, "ibcFillFlow_lpm");
    $rate = 0 if($rate !~ /^\d+(?:\.\d+)?$/);

    # A run from a full barrel down to empty moved a known volume - but only
    # without a mains top-up. With the float valve feeding, the pump also moves
    # everything that flowed in meanwhile, so the run is measured by the rate.
    my $complete = ($fromFull && $reason eq "barrelEmpty" && $volume > 0) ? 1 : 0;
    # Zweiter bekannter Fall: Schwimmerhoehe bis Trockenlauf. Das ist die
    # Stadtwasser-Runde, und barrelFloatLevel ist am Wasserzaehler gemessen.
    # Der Fall ist ABSICHTLICH nicht an $source gebunden: bei einer solchen Runde
    # steht der Hahn per Definition offen ($source ist immer "mixed"), das
    # Schwimmerventil ist aber zu, solange das Fass auf Hoehe steht, und der
    # Pumpenlauf ist zu kurz, als dass nennenswert nachliefe.
    my $floatRun = (!$complete && $fromFloat && $reason eq "barrelEmpty"
                    && $float > 0) ? 1 : 0;
    my $moved = 0;
    if($complete && $source ne "mixed") {
        $moved = $volume;
    }
    elsif($floatRun) {
        $moved = $float;
    }
    elsif($rate > 0) {
        $moved = $rate * $minutes;
        # Deckel: die Pumpe kann nicht mehr herausholen, als im Fass stand -
        # plus dem, was das Schwimmerventil waehrend des Laufs nachliefern kann.
        # Ohne das schreibt eine veraltete Rate stillschweigend Wasser gut, das
        # es nie gab (Nacht zum 24.08.: 20,1 min x 12,7 = 255 l aus einem Fass,
        # das 148 fasst).
        my $ceiling = $barrelAtStart;
        if(defined($ceiling)) {
            my $inflow = AttrVal($name, "mainsFillFlow_lpm", 0);
            $ceiling += $inflow * $minutes
                if($source eq "mixed" && $inflow =~ /^\d+(?:\.\d+)?$/ && $inflow > 0);
            if($moved > $ceiling) {
                Log3 $name, 3, sprintf("%s: barrel->IBC booking capped at %.0f l "
                    . "(rate would have given %.0f l in %.1f min - stale rate?)",
                    $name, $ceiling, $moved, $minutes);
                $moved = $ceiling;
            }
        }
    }

    # Split the moved volume into harvested rain and mains water. The float valve
    # holds the barrel at barrelFloatLevel, so only what sits ABOVE that line is
    # rain; from the moment the level reaches the float, everything pumped is
    # either the stored mains water or fresh inflow. The rain share of a run that
    # started with a full barrel is therefore constant - volume minus float level -
    # no matter how long the pump keeps running afterwards.
    my $rainPart  = 0;
    my $mainsPart = 0;
    if($moved > 0) {
        if($source eq "mixed") {
            if($fromFull && $volume > 0 && $float > 0 && $float < $volume) {
                $rainPart = $volume - $float;
                $rainPart = $moved if($rainPart > $moved);
            }
            # else: started below the barrel-full mark, so there is no way to tell
            # how much of it was rain - credit none of it.
            $mainsPart = $moved - $rainPart;
        }
        elsif($source eq "rain") {
            $rainPart = $moved;
        }
        elsif($source eq "other") {
            # Kein Regen und kein Leitungswasser - eigener Topf.
            $rainPart = 0;
            $mainsPart = 0;
        }
        # source "unknown" (no mainsSupplyDevice): no split, only pumped_total_l
    }

    if($moved > 0) {
        readingsBulkUpdate($hash, "lastIbcFillRain_l",  sprintf("%.0f", $rainPart))
            if($source ne "unknown");
        readingsBulkUpdate($hash, "lastIbcFillMains_l", sprintf("%.0f", $mainsPart))
            if($source ne "unknown");

        foreach my $c (["pumped_total_l", $moved],
                       ["pumpedRain_total_l", $source eq "other" ? 0 : $rainPart],
                       ["pumpedOther_total_l", $source eq "other" ? $moved : 0],
                       ["mains_total_l", $source eq "other" ? 0 : $mainsPart]) {
            next if($c->[1] <= 0);
            my $v = ReadingsVal($name, $c->[0], 0);
            $v = 0 if($v !~ /^-?\d+(?:\.\d+)?$/);
            readingsBulkUpdate($hash, $c->[0], sprintf("%.0f", $v + $c->[1]));
        }
    }

    if($complete && $source eq "mixed" && $moved > 0) {
        Log3 $name, 3, sprintf("%s: barrel->IBC run with mains open: %.0f l in %.1f min "
            . "(%.0f l rain, %.0f l mains) - rate not learned from this run",
            $name, $moved, $minutes, $rainPart, $mainsPart);
    }

    # Beide Faelle mit bekannter Menge lernen die Pumpenrate: voll->leer ueber
    # barrelUsableVolume, Schwimmer->leer ueber barrelFloatLevel. Nur so zieht die
    # Rate den Filterverschleiss nach; ohne den zweiten Fall bleibt sie in einer
    # regenlosen Woche stehen und bucht dauerhaft zu viel.
    my $known = 0;
    $known = $volume if($complete && $source ne "mixed");
    $known = $float  if($floatRun);
    if($known > 0) {
        my $measured = $known / $minutes;
        # Ausreisser-Bremse: ein Lauf, der nicht wirklich am gedachten Startpunkt
        # begann (Fass noch nicht auf Hoehe, vorzeitig abgebrochen), liefert einen
        # wilden Wert. Die Rate darf sich daran nicht verbiegen.
        if($rate > 0 && ($measured > 2 * $rate || $measured < 0.4 * $rate)) {
            Log3 $name, 3, sprintf("%s: barrel->IBC run gives %.1f l/min against a "
                . "learned %.1f - implausible, rate left untouched", $name, $measured, $rate);
        }
        else {
            # Damped average so a single odd run does not dominate
            my $new = ($rate > 0) ? ($rate * 0.7 + $measured * 0.3) : $measured;
            readingsBulkUpdate($hash, "ibcFillFlow_lpm", sprintf("%.1f", $new));
            Log3 $name, 3, sprintf("%s: %s barrel->IBC run: %.0f l in %.1f min "
                . "= %.1f l/min (learned rate now %.1f)",
                $name, $complete ? "complete" : "float-level", $known, $minutes, $measured, $new);
        }
        readingsBulkUpdate($hash, "lastIbcFillVolume_l", sprintf("%.0f", $known));
    }
    else {
        # Partial or mains-fed run - estimate from the learned rate if we have one
        readingsBulkUpdate($hash, "lastIbcFillVolume_l",
            $moved > 0 ? sprintf("%.0f", $moved) : "unknown");
        Log3 $name, 3, sprintf("%s: barrel->IBC run ended (%s) after %.1f min",
            $name, $reason, $minutes)
            if(!$complete);
    }
    readingsEndUpdate($hash, 1);

    if($moved > 0) {
        Gartenbewaesserung_AdjustIbcLevel($hash, $moved, "barrel->IBC");
        # Everything pumped left the barrel. With the mains open it refilled at
        # the same time, which this does not model - the barrelEmpty anchor and
        # the float floor correct that within the same run.
        Gartenbewaesserung_AdjustBarrelLevel($hash, -$moved, "barrel->IBC");
    }

    # Rueckgabe statt Reading: bei einem fruehen Ausstieg oben stuende in
    # lastIbcFillVolume_l noch der Wert der VORIGEN Runde, und der Aufrufer
    # wuerde ihn ein zweites Mal buchen.
    return $moved;
}

##############################################################################
# Stop IBC filling
##############################################################################
sub Gartenbewaesserung_StopIBCFill {
    my ($hash, $reason) = @_;
    my $name = $hash->{NAME};

    RemoveInternalTimer($hash, "Gartenbewaesserung_IbcFullByLevel");

    # Nach einem Neustart oder Modul-Reload mitten im Lauf ist HELPER leer - das
    # ist reiner Arbeitsspeicher. Die Readings wissen es noch, also von dort
    # aufsetzen, sonst faellt der ganze Lauf aus der Statistik. Nur mit
    # Plausibilitaetsgrenze: ein stehengebliebenes ibcFilling wuerde sonst
    # spaeter eine absurde Laufzeit buchen.
    if(!$hash->{HELPER}{ibcFilling} && ReadingsVal($name, "ibcFilling", "no") eq "yes") {
        my $stamp = ReadingsVal($name, "ibcFillStarted", "");
        my $started = ($stamp =~ /^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d$/)
            ? time_str2num($stamp) : 0;
        my $maxAge = (AttrVal($name, "pumpMaxRuntime", 20) + 10) * 60;
        if($started && (int(time()) - $started) < $maxAge) {
            $hash->{HELPER}{ibcFilling} = 1;
            $hash->{HELPER}{ibcFillStartTime} = int($started);
            Log3 $name, 3, "$name: picking up an IBC fill that was already running before the "
                . "restart (started $stamp) - measured from the reading, not from memory";
        }
        elsif($started) {
            Log3 $name, 3, "$name: stale ibcFilling from $stamp - too old to measure, discarding";
            readingsSingleUpdate($hash, "ibcFilling", "no", 1);
        }
    }

    return if(!$hash->{HELPER}{ibcFilling});

    Gartenbewaesserung_MainsFillIbcNote($hash,
        Gartenbewaesserung_RecordIbcFillRun($hash, $reason));

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

    # Nur zuruecknehmen, was wir selbst gesetzt haben, und nur wenn nichts
    # anderes laeuft: StopIBCFill wird auch aus einer startenden Bewaesserung
    # heraus gerufen, die ihren eigenen state schon geschrieben hat.
    if(ReadingsVal($name, "state", "") eq "ibc filling"
       && !$hash->{HELPER}{watering} && !$hash->{HELPER}{circuitMode}
       && !$hash->{HELPER}{pauseActive}) {
        readingsSingleUpdate($hash, "state", "idle", 1);
    }

    Log3 $name, 3, "$name: IBC filling stopped";

    return undef;
}

##############################################################################
# IBC aus der Hauswasserleitung fuellen - "set <name> mainsFillIbc <liter>"
#
# Das Fass ist der Trichter: das Schwimmerventil laesst Leitungswasser bis zur
# Schwimmerhoehe nach, die Pumpe hebt es in den IBC, das Ventil macht wieder
# auf. Eine Runde bringt rund barrelFloatLevel Liter und dauert
# barrelFloatLevel/mainsFillFlow_lpm Minuten Nachlaufen plus gut zwei Minuten
# Pumpen - in der Anlage des Autors 81 l in etwa 21 Minuten, also ~260 l/h.
#
# Sinn der Sache ist NICHT, Leitungswasser zu giessen (das koennte die Leitung
# mit 4,4 l/min ohnehin nicht: ein Giesskreis zieht das Dreifache). Sinn ist,
# den Vorrat tagsueber aufzubauen, wenn das Schwimmerventil hoerbar sein darf,
# und ihn nachts leise zu verbrauchen.
#
# Bewusst ohne eigenes Ventil: der Hahn bleibt waehrenddessen offen, das
# Schwimmerventil regelt. Das Modul steuert nur die Pumpe. Ist der Hahn zu,
# kommt das Fass nie auf Schwimmerhoehe - dann bricht der Waechter unten ab,
# statt endlos zu warten.
##############################################################################
sub Gartenbewaesserung_MainsFillIbcActive {
    my ($hash) = @_;
    my $t = ReadingsVal($hash->{NAME}, "mainsFillIbcTarget", 0);
    return ($t =~ /^\d+(?:\.\d+)?$/ && $t > 0) ? 1 : 0;
}

sub Gartenbewaesserung_MainsFillIbcStart {
    my ($hash, $spec) = @_;
    my $name = $hash->{NAME};

    return "Usage: set $name mainsFillIbc <liter>|<prozent>%|stop"
        if(!defined($spec) || $spec !~ /^(\d+(?:\.\d+)?)\s*(%?)$/);
    my ($value, $pct) = ($1, $2);

    my $capacity = AttrVal($name, "ibcUsableVolume", 0);
    return "attr ibcUsableVolume is not set - no idea how big the IBC is" if($capacity <= 0);
    return "attr ibcFillValveDevice is not set" if(AttrVal($name, "ibcFillValveDevice", "") eq "");
    return "attr pumpDevice is not set"         if(AttrVal($name, "pumpDevice", "") eq "");

    my $target = $pct ? ($capacity * $value / 100) : $value;
    return "target must be greater than 0" if($target <= 0);

    # Nicht mehr vornehmen, als noch hineinpasst.
    my $level = ReadingsVal($name, "ibcLevel_l", "");
    my $room  = ($level =~ /^-?\d+(?:\.\d+)?$/) ? ($capacity - $level) : $capacity;
    my $capped = "";
    if($room <= 0) {
        return "IBC is already full according to the level estimate";
    }
    if($target > $room) {
        $capped = sprintf(" (capped from %.0f l - only %.0f l fit)", $target, $room);
        $target = $room;
    }

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "mainsFillIbcTarget", sprintf("%.0f", $target));
    readingsBulkUpdate($hash, "mainsFillIbcDone", "0");
    readingsBulkUpdate($hash, "mainsFillIbcState", "waiting for barrel");
    readingsEndUpdate($hash, 1);
    $hash->{HELPER}{mainsFillIbcWaitSince} = int(time());

    my $hint = "";
    if(Gartenbewaesserung_MainsSupplyState($hash) eq "off") {
        $hint = " - NOTE: mainsSupply reads 'off', open the tap or nothing will arrive";
    }
    # Ohne Schwimmerhoehe gibt es kein Startsignal fuer eine Runde ausser dem
    # Fass-voll-Kontakt - und den erreicht ein Schwimmerventil nie.
    elsif(AttrVal($name, "barrelFloatLevel", 0) <= 0) {
        $hint = " - NOTE: attr barrelFloatLevel is not set, so a round can only start on the "
              . "barrel-full contact, which a float valve never reaches";
    }
    my $rate = AttrVal($name, "mainsFillFlow_lpm", 0);
    my $eta = ($rate =~ /^\d+(?:\.\d+)?$/ && $rate > 0)
        ? sprintf(", roughly %.0f min at %s l/min", $target / $rate, $rate) : "";

    Log3 $name, 3, sprintf("%s: mains fill of the IBC started - target %.0f l%s%s",
        $name, $target, $capped, $hint);
    Gartenbewaesserung_MainsFillIbcTick($hash);
    return sprintf("filling the IBC from the mains: %.0f l%s%s%s", $target, $capped, $eta, $hint);
}

sub Gartenbewaesserung_MainsFillIbcStop {
    my ($hash, $reason) = @_;
    my $name = $hash->{NAME};

    return undef if(!Gartenbewaesserung_MainsFillIbcActive($hash));

    my $done = ReadingsVal($name, "mainsFillIbcDone", 0);
    delete $hash->{HELPER}{mainsFillIbcWaitSince};
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "mainsFillIbcTarget", "0");
    readingsBulkUpdate($hash, "mainsFillIbcState", $reason);
    readingsEndUpdate($hash, 1);

    Log3 $name, 3, "$name: mains fill of the IBC ended ($reason) after $done l";
    return undef;
}

# Eine Foerderrunde ist durch - anschreiben und schauen, ob noch eine folgt.
sub Gartenbewaesserung_MainsFillIbcNote {
    my ($hash, $volume) = @_;
    my $name = $hash->{NAME};

    return if(!Gartenbewaesserung_MainsFillIbcActive($hash));
    return if(!defined($volume) || $volume !~ /^\d+(?:\.\d+)?$/ || $volume <= 0);

    my $done = ReadingsVal($name, "mainsFillIbcDone", 0);
    $done = 0 if($done !~ /^\d+(?:\.\d+)?$/);
    $done += $volume;
    readingsSingleUpdate($hash, "mainsFillIbcDone", sprintf("%.0f", $done), 1);
    $hash->{HELPER}{mainsFillIbcWaitSince} = int(time());

    my $target = ReadingsVal($name, "mainsFillIbcTarget", 0);
    Log3 $name, 3, sprintf("%s: mains fill round done, %.0f of %s l in the IBC",
        $name, $done, $target);
    Gartenbewaesserung_MainsFillIbcStop($hash, "done") if($done >= $target);
}

sub Gartenbewaesserung_MainsFillIbcTick {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    return if(!Gartenbewaesserung_MainsFillIbcActive($hash));

    if(ReadingsVal($name, "ibcFull", "no") eq "yes") {
        Gartenbewaesserung_MainsFillIbcStop($hash, "ibcFull");
        return;
    }

    # Giessen hat Vorrang. Nicht abbrechen, nur aussetzen - danach geht es
    # weiter. Die Wartezeit-Uhr laeuft dabei nicht mit, sonst wuerde ein langer
    # Giesszyklus den Waechter ausloesen.
    if($hash->{HELPER}{watering} || $hash->{HELPER}{circuitMode}
    || $hash->{HELPER}{pauseActive} || $hash->{HELPER}{ibcToBarrelActive}
    || $hash->{HELPER}{barrelEmptyRefillPause}) {
        readingsSingleUpdate($hash, "mainsFillIbcState", "suspended - watering", 1)
            if(ReadingsVal($name, "mainsFillIbcState", "") ne "suspended - watering");
        $hash->{HELPER}{mainsFillIbcWaitSince} = int(time());
        return;
    }

    # Laeuft die Pumpe schon, ist nichts zu tun - StopIBCFill meldet sich.
    if($hash->{HELPER}{ibcFilling}) {
        readingsSingleUpdate($hash, "mainsFillIbcState", "pumping", 1)
            if(ReadingsVal($name, "mainsFillIbcState", "") ne "pumping");
        return;
    }

    # Lohnt sich eine Runde schon? Der Fass-voll-Kontakt zaehlt immer, sonst
    # der mitgerechnete Stand gegen die Schwimmerhoehe.
    my $float = AttrVal($name, "barrelFloatLevel", 0);
    my $level = ReadingsVal($name, "barrelLevel_l", "");
    my $ready = (ReadingsVal($name, "barrelFull", "no") eq "yes") ? 1 : 0;
    $ready = 1 if(!$ready && $float > 0 && $level =~ /^-?\d+(?:\.\d+)?$/ && $level >= $float - 2);

    if(!$ready) {
        readingsSingleUpdate($hash, "mainsFillIbcState", "waiting for barrel", 1)
            if(ReadingsVal($name, "mainsFillIbcState", "") ne "waiting for barrel");

        # Waechter: kommt kein Wasser, kommt das Fass nie auf Hoehe. Statt
        # endlos zu warten, nach der doppelten erwarteten Nachlaufzeit abbrechen
        # - meist ist dann schlicht der Hahn zu.
        my $since = $hash->{HELPER}{mainsFillIbcWaitSince} || int(time());
        $hash->{HELPER}{mainsFillIbcWaitSince} = $since;
        my $rate = AttrVal($name, "mainsFillFlow_lpm", 0);
        my $limit = ($rate =~ /^\d+(?:\.\d+)?$/ && $rate > 0 && $float > 0)
            ? (2 * $float / $rate + 10) : 60;
        if((int(time()) - $since) / 60 >= $limit) {
            Log3 $name, 3, sprintf("%s: barrel did not reach the float level within %.0f min - "
                . "is the mains tap open? Stopping the mains fill.", $name, $limit);
            Gartenbewaesserung_MainsFillIbcStop($hash, "no water - tap closed?");
        }
        return;
    }

    # Dritter Parameter: dieser Lauf startet auf der Schwimmerhoehe (siehe oben,
    # $ready) und bewegt damit eine bekannte Menge.
    my $err = Gartenbewaesserung_StartIBCFill($hash, 1, 1);
    if($err) {
        Log3 $name, 3, "$name: mains fill cannot pump right now ($err) - trying again next minute";
        return;
    }
    readingsSingleUpdate($hash, "mainsFillIbcState", "pumping", 1);
}

##############################################################################
# Nach Neustart oder Modul-Reload: Aktoren einsammeln, die noch laufen.
#
# $hash->{HELPER} ist reiner Arbeitsspeicher. Nach einem Neustart weiss das
# Modul von nichts mehr - Pumpe und Ventile bleiben aber physisch an, und
# damit hoert ihnen niemand mehr zu: der Pumpen-Watchdog (pumpMaxRuntime) ist
# weg, ein per defmod angelegtes Timeout-at ebenfalls.
#
# Am 23.08.2026 lief die Pumpe deshalb nach einem Update-Neustart rund zehn
# Minuten trocken weiter. Sie war um 10:07:36 fuer eine IBC-Befuellung
# gestartet, im Fass standen 80 l - nach gut zwei Minuten war es leer.
#
# Bewusst abschalten statt uebernehmen: das Modul kann nach dem Start nicht
# wissen, ob im Fass noch Wasser steht. Ein abgebrochener Lauf laesst sich
# neu starten, eine trockengelaufene Pumpe nicht reparieren. Nur die
# IBC-Befuellung geht ueber StopIBCFill, damit das bereits gefoerderte
# Volumen noch verbucht wird (die Wiederaufnahme aus den Readings gibt es
# dort seit v1.0.58) - abgeschaltet wird sie dabei genauso.
##############################################################################
sub Gartenbewaesserung_AdoptOrStopOrphans {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    # Laeuft im Modul selbst etwas, ist nichts verwaist.
    return if($hash->{HELPER}{watering}      || $hash->{HELPER}{circuitMode}
           || $hash->{HELPER}{ibcFilling}    || $hash->{HELPER}{ibcToBarrelActive}
           || $hash->{HELPER}{barrelFilling} || $hash->{HELPER}{pauseActive}
           || $hash->{HELPER}{barrelEmptyRefilling});

    # Eine unterbrochene IBC-Befuellung zuerst: die kann sich noch selbst
    # abrechnen, bevor die Armaturen zugehen.
    if(ReadingsVal($name, "ibcFilling", "no") eq "yes") {
        Log3 $name, 1, "$name: an IBC fill was still running before the restart - "
            . "booking what it moved, then shutting it down";
        Gartenbewaesserung_StopIBCFill($hash, "restart");
    }

    my @off;
    foreach my $a ("pumpDevice", "ibcFillValveDevice", "ibcToBarrelValveDevice",
                   "ibcToBarrelPumpDevice", "barrelFillValveDevice",
                   map { "valve${_}Device" } (1..8)) {
        my $def = AttrVal($name, $a, "");
        next if($def eq "" || !Gartenbewaesserung_IsDeviceOn($name, $def));
        Gartenbewaesserung_SwitchDevice($name, $def, "off");
        push @off, $a;
    }
    return if(!@off);

    Log3 $name, 1, sprintf("%s: %d actuator(s) were still switched on after the restart "
        . "with nothing left watching them - switched off: %s",
        $name, scalar(@off), join(", ", @off));
    readingsSingleUpdate($hash, "orphanShutdown", TimeNow() . " " . join(",", @off), 1);
}

##############################################################################
# Check if IBC is full
##############################################################################
sub Gartenbewaesserung_CheckIBCFull {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    if($hash->{HELPER}{ibcFilling}) {
        Log3 $name, 3, "$name: IBC full detected, stopping fill";
        Gartenbewaesserung_StopIBCFill($hash, "ibcFull");
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
    Gartenbewaesserung_StopIBCFill($hash, "ibcToBarrel");

    my $ibcToBarrelValve = AttrVal($name, "ibcToBarrelValveDevice", "");
    if($ibcToBarrelValve eq "") {
        return "No IBC to barrel valve configured (ibcToBarrelValveDevice)";
    }

    # Check if we need a pump for IBC to barrel
    my $ibcToBarrelPump = AttrVal($name, "ibcToBarrelPumpDevice", "");
    my $duration = AttrVal($name, "ibcToBarrelDuration", 15);

    if($ibcToBarrelPump ne "") {
        # Use pump for IBC to barrel transfer. Ordering follows pumpStartDelay:
        # positive = pump first (build pressure), negative/zero = valve first so
        # the pump never runs against a closed valve.
        my $delay = AttrVal($name, "pumpStartDelay", 3);

        # Mark active up front so StopIBCtoBarrel can always tear both devices down
        $hash->{HELPER}{ibcToBarrelActive} = 1;
        Gartenbewaesserung_NoteIbcToBarrelStart($hash);
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash, "ibcToBarrelActive", "yes");
        readingsBulkUpdate($hash, "state", "ibc to barrel");
        readingsBulkUpdate($hash, "phase", "transferring water from IBC (pump)");
        readingsEndUpdate($hash, 1);

        # Flow starts once both pump and valve are on -> anchor runtime/auto-stop there
        my $startFlow = sub {
            Gartenbewaesserung_SetEndTime($hash, $duration);
            Log3 $name, 3, "$name: IBC to barrel transfer started with pump for $duration minutes";
            InternalTimer(gettimeofday() + ($duration * 60), sub {
                Gartenbewaesserung_StopIBCtoBarrel($hash);
            }, $hash);
        };

        if($delay > 0) {
            # Pump first, then valve after delay
            Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelPump, "on");
            Log3 $name, 4, "$name: IBC to barrel pump started";
            InternalTimer(gettimeofday() + $delay, sub {
                return if(!$hash->{HELPER}{ibcToBarrelActive});   # stopped during delay
                Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelValve, "on");
                $startFlow->();
            }, $hash);
        }
        elsif($delay < 0) {
            # Valve first, then pump after |delay|
            Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelValve, "on");
            Log3 $name, 4, "$name: IBC to barrel valve opened (negative delay)";
            InternalTimer(gettimeofday() + abs($delay), sub {
                return if(!$hash->{HELPER}{ibcToBarrelActive});   # stopped during delay
                Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelPump, "on");
                $startFlow->();
            }, $hash);
        }
        else {
            # Zero: valve first, then pump (no delay)
            Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelValve, "on");
            Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelPump, "on");
            $startFlow->();
        }
    }
    else {
        # Gravity feed - no pump needed
        Gartenbewaesserung_SwitchDevice($name, $ibcToBarrelValve, "on");
        $hash->{HELPER}{ibcToBarrelActive} = 1;
        Gartenbewaesserung_NoteIbcToBarrelStart($hash);

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
    my ($hash, $reason) = @_;
    my $name = $hash->{NAME};

    return if(!$hash->{HELPER}{ibcToBarrelActive});

    # Zentral hier, damit JEDER Weg abgerechnet wird - auch der manuelle
    # "set startIBCtoBarrel" und der eigene Dauer-Timer. CheckBarrelFull ruft
    # vorher schon mit dem besseren Grund "barrelFull"; der zweite Aufruf faellt
    # dann durch, weil NoteIbcToBarrelStop den Startzeitpunkt geloescht hat.
    Gartenbewaesserung_NoteIbcToBarrelStop($hash, $reason || "stopped");

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
# Did it rain recently enough to treat the water in the barrel as rainwater?
#
# The classic trigger required rain to be falling at the very moment the barrel
# reports full. In practice the barrel fills late - roof and gutter keep draining
# for a while after the rain has stopped - so that window is regularly missed.
# With a rain gauge (rainAmountDevice) the attribute ibcFillRainAmount widens the
# condition to "at least X mm fell within rainAmountWindow", which still tells
# rainwater apart from a barrel topped up from the mains supply.
##############################################################################
sub Gartenbewaesserung_RainRecentEnough {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    # Classic behaviour: it is raining right now
    return 1 if(ReadingsVal($name, "raining", "no") eq "yes");

    my $minAmount = AttrVal($name, "ibcFillRainAmount", 0);
    return 0 if($minAmount <= 0);                                  # feature disabled
    return 0 if(AttrVal($name, "rainAmountDevice", "") eq "");     # no rain gauge

    # Never treat a mains-fed barrel as harvested rainwater
    return 0 if($hash->{HELPER}{barrelEmptyRefilling}
                && ($hash->{HELPER}{barrelEmptyRefillSource} || "") eq "water_supply");
    return 0 if(Gartenbewaesserung_IsDeviceOn($name, AttrVal($name, "barrelFillValveDevice", "")));

    return (ReadingsVal($name, "rainAmount_mm", 0) >= $minAmount) ? 1 : 0;
}

##############################################################################
# The barrel was filled from something other than rain - either the mains supply
# or a transfer back from the IBC. Whatever rain credit had accumulated no longer
# identifies the barrel contents as freshly harvested rainwater, so drop it: the
# next harvest must be earned by new rain.
#
# Without this the barrel would be pumped into the IBC as soon as the cycle ends
# - putting tap water into the rainwater store, or in the IBC->barrel case
# pumping the very same water straight back up (barrel<->IBC oscillation).
##############################################################################
sub Gartenbewaesserung_NoteNonRainFill {
    my ($hash, $source) = @_;
    my $name = $hash->{NAME};

    return if(ReadingsVal($name, "rainSinceHarvest_mm", 0) <= 0);

    readingsSingleUpdate($hash, "rainSinceHarvest_mm", "0", 1);
    Log3 $name, 4, "$name: barrel filled from $source - harvest trigger cleared";
}

##############################################################################
# Should a NEW harvest (barrel -> IBC) be started?
#
# Unlike RainRecentEnough this consumes its trigger: rainSinceHarvest_mm is
# reset to 0 whenever a fill actually starts, so the next harvest requires
# genuinely NEW rain. Without that the condition would still hold for the rest
# of the rain window - and a barrel refilled by gravity from the IBC during a
# watering pause would immediately be pumped back up (barrel<->IBC oscillation).
##############################################################################
sub Gartenbewaesserung_HarvestDue {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    # Fremdwasser: dann gibt es keinen Regen, auf den man warten koennte. Ein
    # volles Fass ist hier der einzige und ausreichende Grund - sonst bliebe
    # das Wasser stehen, bis es zufaellig regnet.
    return 1 if(ReadingsVal($name, "waterSource", "rain") eq "other");

    return 0 if(!Gartenbewaesserung_RainRecentEnough($hash));

    # Classic trigger: it is raining right now - no amount bookkeeping involved
    return 1 if(ReadingsVal($name, "raining", "no") eq "yes");

    my $minAmount = AttrVal($name, "ibcFillRainAmount", 0);
    return 0 if($minAmount <= 0);

    return (ReadingsVal($name, "rainSinceHarvest_mm", 0) >= $minAmount) ? 1 : 0;
}

##############################################################################
# Rain amount (mm): maintain a rolling-window sum from a weather station rain
# gauge and feed the rainwater-collection watchdog.
#
# The source reading (e.g. dailyrain_mm) is cumulative but resets periodically
# (midnight / per event). We therefore derive our own monotonic accumulator by
# adding positive deltas and treating any decrease as a reset (current value =
# new rain). A small timestamped buffer of accumulator samples lets us subtract
# the value from "window hours ago" to get the rolling sum.
##############################################################################
sub Gartenbewaesserung_UpdateRainAmount {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    my $dev = AttrVal($name, "rainAmountDevice", "");
    return if($dev eq "");

    my ($rdev, $rreading) = Gartenbewaesserung_ParseDevice($dev);
    $rreading = AttrVal($name, "rainAmountReading", "dailyrain_mm") if($rreading eq "");
    return if($rdev eq "" || !defined($defs{$rdev}));

    my $raw = ReadingsVal($rdev, $rreading, "");
    return if($raw !~ /^-?\d+(?:\.\d+)?$/);   # not a number (yet)

    # Integer seconds: some installations import Time::HiRes' time() into main::,
    # which would put a fractional part into the buffer timestamps.
    my $now = int(time());

    # Derive monotonic accumulator from the (resettable) source reading
    my $lastRaw = ReadingsVal($name, ".rainLastRaw", "");
    my $accum   = ReadingsVal($name, ".rainAccum", 0);
    $accum = 0 if($accum !~ /^-?\d+(?:\.\d+)?$/);

    my $delta = 0;
    if($lastRaw =~ /^-?\d+(?:\.\d+)?$/) {
        $delta = ($raw >= $lastRaw) ? ($raw - $lastRaw) : $raw;   # decrease = source reset
    }
    elsif($rreading =~ /daily/i) {
        # First observation with no stored baseline - a fresh device, or readings
        # that were deleted. A daily counter states the rain that already fell
        # today, so count it instead of discarding it.
        $delta = $raw;
        Log3 $name, 3, "$name: no rain baseline stored - adopting today's counter ($raw mm)";
    }
    # else: first observation on a non-daily source -> only establish the baseline
    $accum += $delta;

    # Rolling-window buffer: "epoch:accum,epoch:accum,..."
    my $windowH = AttrVal($name, "rainAmountWindow", 24);
    my $cutoff  = $now - $windowH * 3600;
    # Accept fractional timestamps too - older buffers may contain them
    my @buf = grep { /^\d+(?:\.\d+)?:/ } split(/,/, ReadingsVal($name, ".rainBuffer", ""));

    # Keep the newest sample older than the cutoff (as window baseline) plus all newer ones
    my ($baseline, @kept);
    foreach my $s (@buf) {
        my ($t) = split(/:/, $s);
        if($t < $cutoff) { $baseline = $s; }
        else             { push @kept, $s; }
    }
    unshift @kept, $baseline if(defined $baseline);

    # No usable history (fresh device, or a restart without a current statefile):
    # seed a baseline at midnight so the window immediately reflects the rain that
    # already fell today. Only valid for a daily counter, which resets at midnight.
    if(!@kept && $rreading =~ /daily/i && $raw > 0) {
        my @lt = localtime($now);
        my $midnight = $now - ($lt[2] * 3600 + $lt[1] * 60 + $lt[0]);
        $midnight = $cutoff if($midnight < $cutoff);
        push @kept, int($midnight) . ":" . ($accum - $raw);
        Log3 $name, 3, "$name: rain buffer empty - seeded window with today's rain ($raw mm)";
    }

    # Append the current sample, throttled to at most one every 10 minutes
    my $lastT = @kept ? (split(/:/, $kept[-1]))[0] : 0;
    push @kept, "$now:$accum" if(!@kept || $now - $lastT >= 600);

    # Window sum = accumulator now - accumulator at start of window
    my $a0 = @kept ? (split(/:/, $kept[0]))[1] : $accum;
    my $windowSum = $accum - $a0;
    $windowSum = 0 if($windowSum < 0);

    # Rain since the tanks last showed a fill response (collection watchdog)
    my $sinceFill = ReadingsVal($name, "rainSinceFill_mm", 0);
    $sinceFill = 0 if($sinceFill !~ /^-?\d+(?:\.\d+)?$/);
    $sinceFill += $delta;

    # Rain since the last harvest into the IBC. Consumed by StartIBCFill, so a
    # new harvest always needs new rain (see HarvestDue).
    my $sinceHarvest = ReadingsVal($name, "rainSinceHarvest_mm", 0);
    $sinceHarvest = 0 if($sinceHarvest !~ /^-?\d+(?:\.\d+)?$/);
    $sinceHarvest += $delta;

    # Harvest statistics: how much water the roof actually delivers.
    # 1 mm of rain on 1 m2 = 1 litre; the runoff coefficient accounts for wetting,
    # evaporation and first flush (DIN 1989-1: 0.8 for a tiled pitched roof).
    # Note: this is what arrives at the downpipe - overflow at a full barrel is
    # not (and cannot be) deducted here.
    my $roofArea = AttrVal($name, "roofArea", 0);
    my ($todayL, $monthL, $yearL, $totalL, $day, $month, $year);
    my $harvested = 0;
    if($roofArea > 0) {
        my $liters = $delta * $roofArea * AttrVal($name, "runoffCoefficient", 0.8);
        $harvested = $liters;

        my @lt = localtime($now);
        $day   = sprintf("%04d-%02d-%02d", $lt[5] + 1900, $lt[4] + 1, $lt[3]);
        $month = substr($day, 0, 7);
        $year  = substr($day, 0, 4);

        # Period counters restart when the calendar period rolls over
        $todayL = (ReadingsVal($name, ".harvestDay",   "") eq $day)   ? ReadingsVal($name, "harvest_today_l", 0) : 0;
        $monthL = (ReadingsVal($name, ".harvestMonth", "") eq $month) ? ReadingsVal($name, "harvest_month_l", 0) : 0;
        $yearL  = (ReadingsVal($name, ".harvestYear",  "") eq $year)  ? ReadingsVal($name, "harvest_year_l",  0) : 0;
        $totalL = ReadingsVal($name, "harvest_total_l", 0);

        foreach my $v (\$todayL, \$monthL, \$yearL, \$totalL) {
            $$v = 0 if($$v !~ /^-?\d+(?:\.\d+)?$/);
            $$v += $liters;
        }
    }

    # Only write the visible readings when the value actually changed. This runs
    # every rainCheckInterval (default 5 min), so writing unconditionally means
    # ~290 events per reading per day - all of them passing through DoTrigger,
    # every notify and DbLog, and filling the device's FileLog with noise. The
    # hidden .rain* readings are exempt: they change constantly by design and
    # dot-readings do not generate events anyway.
    my $setzeWennGeaendert = sub {
        my ($reading, $value) = @_;
        return if(ReadingsVal($name, $reading, "") eq $value);
        readingsBulkUpdate($hash, $reading, $value);
    };

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, ".rainLastRaw", $raw);
    readingsBulkUpdate($hash, ".rainAccum", sprintf("%.2f", $accum));
    readingsBulkUpdate($hash, ".rainBuffer", join(",", @kept));
    $setzeWennGeaendert->("rainAmount_mm", sprintf("%.2f", $windowSum));
    $setzeWennGeaendert->("rainSinceFill_mm", sprintf("%.2f", $sinceFill));
    $setzeWennGeaendert->("rainSinceHarvest_mm", sprintf("%.2f", $sinceHarvest));
    if($roofArea > 0) {
        readingsBulkUpdate($hash, ".harvestDay",   $day);
        readingsBulkUpdate($hash, ".harvestMonth", $month);
        readingsBulkUpdate($hash, ".harvestYear",  $year);
        $setzeWennGeaendert->("harvest_today_l", sprintf("%.1f", $todayL));
        $setzeWennGeaendert->("harvest_month_l", sprintf("%.1f", $monthL));
        $setzeWennGeaendert->("harvest_year_l",  sprintf("%.1f", $yearL));
        $setzeWennGeaendert->("harvest_total_l", sprintf("%.1f", $totalL));
    }
    readingsEndUpdate($hash, 1);

    # Rain reaching the downpipe goes into the barrel. Overflow at a full barrel
    # is handled by the clamp in SetBarrelLevel, not modelled here.
    Gartenbewaesserung_AdjustBarrelLevel($hash, $harvested, "rain") if($harvested > 0);

    Log3 $name, 5, "$name: rain amount update raw=$raw delta=$delta accum=$accum "
        . "window(${windowH}h)=$windowSum sinceFill=$sinceFill";

    # Arm the collection watchdog only when fresh rain actually fell
    Gartenbewaesserung_CheckRainCollection($hash) if($delta > 0);
}

##############################################################################
# Rainwater-collection watchdog: if enough rain falls without the barrel/IBC
# ever showing a fill response, something is wrong with the collection path
# (gutter, downpipe, diverter, filter). Arms a one-shot verification timer.
##############################################################################
sub Gartenbewaesserung_CheckRainCollection {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    my $checkAmount = AttrVal($name, "rainCollectionCheckAmount", 0);
    return if($checkAmount <= 0);                 # feature disabled
    return if($hash->{HELPER}{rainCollectionArmed});

    my $sinceFill = ReadingsVal($name, "rainSinceFill_mm", 0);
    return if($sinceFill < $checkAmount);

    # If the IBC is already full there is no headroom to catch more -> not a fault
    return if(ReadingsVal($name, "ibcFull", "no") eq "yes");

    $hash->{HELPER}{rainCollectionArmed} = 1;
    my $delay = AttrVal($name, "rainCollectionCheckDelay", 120) * 60;
    RemoveInternalTimer($hash, "Gartenbewaesserung_RainCollectionTimeout");
    InternalTimer(gettimeofday() + $delay, "Gartenbewaesserung_RainCollectionTimeout", $hash);
    Log3 $name, 4, "$name: rain collection check armed (${sinceFill} mm since last fill), "
        . "verifying in " . int($delay / 60) . " min";
}

##############################################################################
# Verification timer for the collection watchdog. A fill response would have
# reset rainSinceFill_mm to 0 in the meantime; if it did not, raise the alert.
##############################################################################
sub Gartenbewaesserung_RainCollectionTimeout {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    RemoveInternalTimer($hash, "Gartenbewaesserung_RainCollectionTimeout");
    delete $hash->{HELPER}{rainCollectionArmed};

    my $checkAmount = AttrVal($name, "rainCollectionCheckAmount", 0);
    return if($checkAmount <= 0);

    my $sinceFill = ReadingsVal($name, "rainSinceFill_mm", 0);
    if($sinceFill >= $checkAmount && ReadingsVal($name, "ibcFull", "no") ne "yes") {
        readingsSingleUpdate($hash, "rainCollectionAlert", "yes", 1);
        Log3 $name, 2, "$name: rain collection ALERT - ${sinceFill} mm rain but no barrel/IBC "
            . "fill response - check gutter/downpipe/diverter/filter";
    }
    else {
        Log3 $name, 4, "$name: rain collection check passed (sinceFill=${sinceFill} mm)";
    }
}

##############################################################################
# Called when the tanks show that water arrived (barrel/IBC fill response).
# Resets the collection accumulator and clears the alert.
##############################################################################
sub Gartenbewaesserung_RainCollectionSeenFill {
    my ($hash, $source) = @_;
    my $name = $hash->{NAME};

    return if(AttrVal($name, "rainCollectionCheckAmount", 0) <= 0);

    delete $hash->{HELPER}{rainCollectionArmed};
    RemoveInternalTimer($hash, "Gartenbewaesserung_RainCollectionTimeout");

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "rainSinceFill_mm", "0");
    readingsBulkUpdate($hash, "rainCollectionAlert", "no")
        if(ReadingsVal($name, "rainCollectionAlert", "no") ne "no");
    readingsEndUpdate($hash, 1);

    Log3 $name, 4, "$name: fill response seen ($source) - rain collection OK, rainSinceFill reset";
}

##############################################################################
# Check for rain and IBC filling opportunity
##############################################################################
sub Gartenbewaesserung_CheckRain {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    RemoveInternalTimer($hash, "Gartenbewaesserung_CheckRain");

    return if(IsDisabled($name));

    # Keep the rolling rain amount fresh even without sensor events (window slides)
    Gartenbewaesserung_UpdateRainAmount($hash);

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

                # Stop IBC fill when rain stops - unless enough rain fell recently
                # (ibcFillRainAmount), in which case the barrel still holds rainwater
                # worth harvesting. It then runs until barrelEmpty / ibcFull / watering.
                if($hash->{HELPER}{ibcFilling}) {
                    if(Gartenbewaesserung_RainRecentEnough($hash)) {
                        Log3 $name, 4, "$name: Rain stopped but recent rain amount still "
                            . "qualifies - continuing IBC fill";
                    }
                    else {
                        Gartenbewaesserung_StopIBCFill($hash, "rainStopped");
                    }
                }
            }
        }
    }

    # Harvest window after the rain has stopped: the barrel usually fills late
    # (roof and gutter keep draining), so a full barrel is picked up here too.
    if(AttrVal($name, "ibcFillRainAmount", 0) > 0
       && ReadingsVal($name, "barrelFull", "no") eq "yes"
       && ReadingsVal($name, "ibcFull", "no") ne "yes"
       && !$hash->{HELPER}{ibcFilling}
       && !$hash->{HELPER}{watering}
       && !$hash->{HELPER}{circuitMode}
       && !$hash->{HELPER}{ibcToBarrelActive}
       && Gartenbewaesserung_HarvestDue($hash)) {
        Log3 $name, 3, "$name: Barrel full and " . ReadingsVal($name, "rainSinceHarvest_mm", "?")
            . " mm rain in window, starting IBC fill";
        Gartenbewaesserung_StartIBCFill($hash, 0);
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

    # Einziger Taktgeber, der im Betrieb zuverlaessig laeuft (60 s).
    Gartenbewaesserung_MainsFillTick($hash);
    Gartenbewaesserung_MainsFillIbcTick($hash);

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
    $status .= "Current Valve Name: " . ReadingsVal($name, "currentValveName", "none") . "\n";
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
    if(AttrVal($name, "rainAmountDevice", "") ne "") {
        $status .= "Rain Amount (" . AttrVal($name, "rainAmountWindow", 24) . "h): "
                 . ReadingsVal($name, "rainAmount_mm", "0") . " mm\n";
        $status .= "Rain Since Fill: " . ReadingsVal($name, "rainSinceFill_mm", "0") . " mm\n";
        $status .= "Rain Collection Alert: " . ReadingsVal($name, "rainCollectionAlert", "no") . "\n";
    }
    if(AttrVal($name, "roofArea", 0) > 0) {
        $status .= "\n--- Regenwasser-Ertrag (" . AttrVal($name, "roofArea", 0) . " m2, Beiwert "
                 . AttrVal($name, "runoffCoefficient", 0.8) . ") ---\n";
        $status .= "Heute:  " . ReadingsVal($name, "harvest_today_l", "0") . " l\n";
        $status .= "Monat:  " . ReadingsVal($name, "harvest_month_l", "0") . " l\n";
        $status .= "Jahr:   " . ReadingsVal($name, "harvest_year_l",  "0") . " l\n";
        $status .= "Gesamt: " . ReadingsVal($name, "harvest_total_l", "0") . " l\n";
        $status .= "  davon nachweislich gefoerdert: "
                 . ReadingsVal($name, "pumpedRain_total_l", "0") . " l (nur Regen), "
                 . ReadingsVal($name, "pumped_total_l", "0") . " l gesamt\n";
        $status .= "  aus der Leitung mitgefoerdert: "
                 . ReadingsVal($name, "mains_total_l", "0") . " l\n";
        if(ReadingsVal($name, "pumpedOther_total_l", "0") ne "0") {
            $status .= "  aus anderer Quelle: "
                     . ReadingsVal($name, "pumpedOther_total_l", "0") . " l\n";
        }
        if(ReadingsVal($name, "waterSource", "rain") ne "rain") {
            $status .= "  ACHTUNG Wasserquelle steht auf '"
                     . ReadingsVal($name, "waterSource", "rain")
                     . "' - Ernte laeuft ohne Regenpruefung\n";
        }
        $status .= "\n";
    }
    if(ReadingsVal($name, "lastIbcFillDuration", "") ne "") {
        $status .= "\n--- Letzte IBC-Befuellung ---\n";
        $status .= "Dauer:     " . ReadingsVal($name, "lastIbcFillDuration", "-") . " min\n";
        $status .= "Endgrund:  " . ReadingsVal($name, "lastIbcFillEnd", "-") . "\n";
        $status .= "Volumen:   " . ReadingsVal($name, "lastIbcFillVolume_l", "-") . " l\n";
        $status .= "Quelle:    " . ReadingsVal($name, "lastIbcFillSource", "-") . "\n";
        if(ReadingsVal($name, "lastIbcFillRain_l", "") ne "") {
            $status .= "  davon Regen:   " . ReadingsVal($name, "lastIbcFillRain_l", "-") . " l\n";
            $status .= "  davon Leitung: " . ReadingsVal($name, "lastIbcFillMains_l", "-") . " l\n";
        }
        $status .= "Foerderrate (gelernt): " . ReadingsVal($name, "ibcFillFlow_lpm", "-") . " l/min\n\n";
    }
    if(ReadingsVal($name, "barrelLevel_l", "") ne "") {
        $status .= "--- Fass-Fuellstand (geschaetzt) ---\n";
        $status .= "Stand:  " . ReadingsVal($name, "barrelLevel_l", "-") . " l ("
                 . ReadingsVal($name, "barrelLevel", "-") . " %)\n";
        $status .= "Anker:  " . ReadingsVal($name, "barrelLevelAnchor", "-") . "\n";
        $status .= "Entnahme Giessen (gelernt): "
                 . ReadingsVal($name, "wateringFlow_lpm", "-") . " l/min\n\n";
    }
    if(ReadingsVal($name, "ibcLevel_l", "") ne "") {
        $status .= "--- IBC-Fuellstand (geschaetzt) ---\n";
        $status .= "Stand:  " . ReadingsVal($name, "ibcLevel_l", "-") . " l ("
                 . ReadingsVal($name, "ibcLevel_pct", "-") . " %)\n";
        $status .= "Anker:  " . ReadingsVal($name, "ibcLevelAnchor", "-") . "\n";
        $status .= "Rueckfluss (gelernt): "
                 . ReadingsVal($name, "ibcToBarrelFlow_lpm", "-") . " l/min\n\n";
    }
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
        rainAmountDevice
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
    <p>Die laufende Version steht im Internal <code>VERSION</code> und unter
    <code>get &lt;name&gt; version</code>. Sie wird seit v1.0.75 <b>aus dem obersten
    Eintrag der Änderungsliste im Dateikopf gelesen</b> und nicht mehr von Hand
    gepflegt. Vorher stand sie zweimal fest verdrahtet und war beide Male
    vergessen worden - erst hier in der Beschreibung (38 Versionen alt), dann im
    Code selbst (zwei Versionen). Eine Zahl, die nicht mitwächst, ist schlimmer
    als keine, weil man ihr glaubt.</p>

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
        <li><a id="Gartenbewaesserung-set-start"></a><b>start</b> - Startet den kompletten Bewässerungszyklus mit allen aktiven Ventilen</li>
        <li><a id="Gartenbewaesserung-set-stop"></a><b>stop</b> - Stoppt sofort alle laufenden Operationen (Bewässerung, Pumpen, Ventile)</li>
        <li><a id="Gartenbewaesserung-set-startCircuit"></a><b>startCircuit &lt;1-8&gt;</b> - Startet einen einzelnen Bewässerungskreis (mit voller Logik: Fass-Check, Pumpe, Ventil, <b>automatischen Pausen</b>). Perfekt für externe Steuerung z.B. vom Gewächshaus</li>
        <li><a id="Gartenbewaesserung-set-startIBCFill"></a><b>startIBCFill</b> - Startet manuelle IBC-Befüllung aus dem Fass (mit Pumpe)</li>
        <li><a id="Gartenbewaesserung-set-mainsFillIbc"></a><b>mainsFillIbc &lt;liter&gt;|&lt;prozent&gt;%|stop</b> - Füllt den IBC aus der
            <b>Hauswasserleitung</b>, bis die angegebene Menge drin ist.<br>
            Das Fass ist dabei der Trichter: das Schwimmerventil lässt Leitungswasser bis
            <code>barrelFloatLevel</code> nach, die Pumpe hebt es in den IBC, das Ventil macht
            wieder auf. Eine Runde bringt rund <code>barrelFloatLevel</code> Liter und dauert
            <code>barrelFloatLevel</code>/<code>mainsFillFlow_lpm</code> Minuten Nachlaufen plus
            gut zwei Minuten Pumpen.<br>
            <b>Der Wasserhahn muss offen sein</b> – das Modul steuert nur die Pumpe, geregelt
            wird über das Schwimmerventil. Kommt das Fass nicht auf Schwimmerhöhe, bricht der
            Auftrag nach der doppelten erwarteten Nachlaufzeit ab
            (<code>mainsFillIbcState: no water - tap closed?</code>).<br>
            Eine Bewässerung hat Vorrang: der Auftrag setzt so lange aus
            (<code>suspended - watering</code>) und läuft danach weiter. <code>set stop</code>
            und <code>set … mainsFillIbc stop</code> brechen ihn ab.<br>
            Gedacht ist das nicht zum Gießen mit Leitungswasser – dafür ist der Zulauf viel zu
            schwach – sondern um den Vorrat tagsüber aufzubauen, wenn das Schwimmerventil
            hörbar sein darf, und ihn nachts leise zu verbrauchen.<br>
            Beispiele: <code>set bewaesserung mainsFillIbc 600</code>,
            <code>set bewaesserung mainsFillIbc 50%</code>,
            <code>set bewaesserung mainsFillIbc stop</code></li>
        <li><a id="Gartenbewaesserung-set-stopIBCFill"></a><b>stopIBCFill</b> - Stoppt IBC-Befüllung</li>
        <li><a id="Gartenbewaesserung-set-startIBCtoBarrel"></a><b>startIBCtoBarrel</b> - Lässt Wasser vom IBC zurück ins Fass laufen (Schwerkraft oder Pumpe)</li>
        <li><a id="Gartenbewaesserung-set-stopIBCtoBarrel"></a><b>stopIBCtoBarrel</b> - Stoppt IBC zu Fass Transfer</li>
        <li><a id="Gartenbewaesserung-set-startValve"></a><b>startValve &lt;1-8&gt;</b> - Startet ein einzelnes Ventil manuell (ohne Automatik)</li>
        <li><a id="Gartenbewaesserung-set-stopValve"></a><b>stopValve</b> - Stoppt das aktuell laufende Ventil</li>
        <li><a id="Gartenbewaesserung-set-resetPumpOverrunAlert"></a><b>resetPumpOverrunAlert</b> - Setzt das Reading <code>pumpOverrunAlert</code> manuell auf <code>no</code> zurück</li>
        <li><a id="Gartenbewaesserung-set-resetHarvestStats"></a><b>resetHarvestStats</b> - Setzt die Ertrags- und Fördermengen-Summen zurück</li>
        <li><a id="Gartenbewaesserung-set-waterSource"></a><b>waterSource rain|other</b> - Sagt dem Modul, dass gerade Wasser im Fass steht, das
        <b>nicht vom Dach</b> kommt – Poolwasser abgelassen, eine andere Tonne umgefüllt, was auch
        immer. Solange <code>other</code> gilt: die Ernte startet allein bei vollem Fass (ohne auf
        Regen zu warten – sonst bliebe das Wasser stehen), das geförderte Volumen zählt in
        <code>pumpedOther_total_l</code> statt in <code>pumpedRain_total_l</code>, und ein volles
        Fass gilt <b>nicht</b> als Beleg für eine funktionierende Regensammlung. Letzteres ist der
        wichtigste Teil: sonst gäbe Fremdwasser dem Sammel-Watchdog eine falsche Entwarnung und ein
        verstopftes Fallrohr fiele nicht mehr auf.<br>
        Der Modus endet <b>von selbst</b> beim nächsten <code>barrelEmpty</code> – dann ist das
        Fremdwasser oben im IBC und der Normalfall gilt wieder. Man kann ihn also vergessen
        auszuschalten, nicht einzuschalten.<br>
        Den Füllstand zieht man bei Bedarf mit <code>set &lt;name&gt; barrelLevel</code> nach; nötig
        ist es nicht, der nächste Kontakt verankert ihn ohnehin.</li>
        <li><a id="Gartenbewaesserung-set-ibcLevel"></a><b>ibcLevel &lt;liter&gt;</b> bzw. <b>ibcLevel &lt;prozent&gt;%</b> - Verankert die Füllstandsschätzung des IBC auf einem abgelesenen Wert. Das ist der genaueste Eingriff, den es gibt: die Schätzung rechnet ab hier neu weiter und die bis dahin aufgelaufene Drift ist weg. Ohne Prozentzeichen wird die Zahl als Liter verstanden. Setzt <code>ibcUsableVolume</code> voraus.</li>
        <li><a id="Gartenbewaesserung-set-barrelLevel"></a><b>barrelLevel &lt;liter&gt;</b> bzw. <b>barrelLevel &lt;prozent&gt;%</b> - Dasselbe für das Fass. Das Fass verankert sich normalerweise mehrmals täglich von selbst an <code>barrelFull</code> oder <code>barrelEmpty</code>; dieser Befehl ist für den Anfang, solange noch kein Kontakt gemeldet hat. Setzt <code>barrelUsableVolume</code> voraus.</li>
        <li><a id="Gartenbewaesserung-set-refreshSensors"></a><b>refreshSensors</b> - Liest alle konfigurierten Sensor-Readings sofort neu ein und aktualisiert die Readings (z. B. nach Neustart oder Gerätetausch)</li>
        <li><a id="Gartenbewaesserung-set-validate"></a><b>validate</b> - Prüft die komplette Konfiguration und zeigt Fehler, Warnungen und Infos an</li>
    </ul>

    <a id="Gartenbewaesserung-get"></a>
    <h4>Get-Befehle</h4>
    <ul>
        <li><a id="Gartenbewaesserung-get-status"></a><b>status</b> - Zeigt den aktuellen Status aller Komponenten</li>
        <li><a id="Gartenbewaesserung-get-config"></a><b>config</b> - Zeigt die komplette Konfiguration übersichtlich an</li>
        <li><a id="Gartenbewaesserung-get-version"></a><b>version</b> - Zeigt die Modulversion an</li>
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
            Füllstand-Schwellwert: Fällt <code>barrelLevel</code> darunter, wird vor dem nächsten
            Ventil eine Befüllung gestartet. Ist <code>barrelUsableVolume</code> gesetzt, stammt der
            Prozentwert aus der Füllstandsschätzung (<code>barrelLevel_l</code>); ohne das Attribut
            bleibt es bei der alten Simulation (Start 100, minus 12 je Ventil).
        </li>
        <li><a id="Gartenbewaesserung-attr-ibcToBarrelDuration"></a>
            <b>ibcToBarrelDuration</b><br>
            Typ: Slider (1–60 Minuten). Standardwert: 15 Minuten.<br>
            Maximale Dauer des IBC→Fass-Transfers (wird durch Fass-voll-Sensor früh beendet).
            Gilt seit v1.0.62 als <b>harte</b> Grenze für <i>jede</i> Übertragung in diese
            Richtung, also auch für die Nachlaufphasen einer Bewässerungspause. Vorher endete
            ein solcher Nachlauf nur beim Ereignis <code>barrelFull</code> oder mit der Pause.
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
            0 = Pausen deaktiviert.<br>
            Gezählt wird <b>Gießzeit</b>: jedes Nachfüllen des Fasses – auch das nach
            <code>barrelEmpty</code> – setzt die Uhr zurück. Steht beim Fälligwerden einer
            Pause <code>barrelFull</code> auf <code>yes</code>, entfällt sie ganz und der
            Kreis läuft weiter: eine Pause ist ein Mittel zum Nachfüllen, kein Selbstzweck.<br>
            <b>Wann man das überhaupt braucht.</b> Der einzige Zweck ist, die Pumpe
            abzuschalten, <i>bevor</i> das Fass leerläuft. Schützt sich die Pumpe selbst –
            Tauchpumpe mit Schwimmerschalter, oder ein echter Leer-Kontakt als
            <code>barrelEmptySensorDevice</code> – dann gehört dieses Attribut auf
            <b>0</b>. Läuft das Fass dann mitten im Kreis leer, übernimmt
            <code>barrelEmpty</code>: nachfüllen, weitermachen. Gießzeit geht dabei nicht
            verloren, die Restminuten des Ventils werden gesichert und nach dem Nachfüllen
            fortgesetzt.<br>
            Ein fester Wert ist ohnehin grob, sobald sich die Kreise im Durchfluss
            unterscheiden: er muss auf den durstigsten passen und unterbricht alle anderen
            zu früh. In der Anlage des Autors reichen 148 l bei Kreis 1 (18,5 l/min) genau
            8 Minuten, bei Kreis 3 (7,1 l/min) dagegen 21 – eine Pause nach 8 Minuten
            unterbräche dort ein Fass, das noch zu zwei Dritteln voll ist.
        </li>
        <li><a id="Gartenbewaesserung-attr-wateringPauseDuration"></a>
            <b>wateringPauseDuration</b><br>
            Typ: Slider (0–60 Minuten). Standardwert: 20 Minuten.<br>
            Dauer der automatischen Bewässerungs-Pause zum Nachfüllen des Fasses.
            Obergrenze, kein Fixwert – meldet der Fass-voll-Sensor früher, endet die Pause
            sofort. Die Übertragung selbst begrenzt zusätzlich <code>ibcToBarrelDuration</code>.
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
        <li><a id="Gartenbewaesserung-attr-rainAmountDevice"></a>
            <b>rainAmountDevice</b><br>
            Typ: Text (<code>Device:Reading</code>). Regenmenge in mm von einer Wetterstation
            mit Regenmesser, z.&nbsp;B. <code>MQTT2_B0CBD8D5566F:dailyrain_mm</code>. Der Wert darf
            periodisch zurückgesetzt werden (Tages-/Ereigniszähler) – das Modul bildet daraus einen
            eigenen, reset-festen Summenwert. Grundlage für <code>rainSkipsWateringAmount</code> und
            die Sammel-Überwachung (<code>rainCollectionCheckAmount</code>).
        </li>
        <li><a id="Gartenbewaesserung-attr-rainAmountReading"></a>
            <b>rainAmountReading</b><br>
            Typ: Text. Reading-Name, falls in <code>rainAmountDevice</code> kein <code>:Reading</code>
            angegeben ist. Standardwert: <code>dailyrain_mm</code>.
        </li>
        <li><a id="Gartenbewaesserung-attr-rainAmountWindow"></a>
            <b>rainAmountWindow</b><br>
            Typ: Slider (1–72 Stunden). Standardwert: 24 Stunden.<br>
            Gleitendes Zeitfenster, über das die Regenmenge (<code>rainAmount_mm</code>) summiert wird.
        </li>
        <li><a id="Gartenbewaesserung-attr-rainSkipsWateringAmount"></a>
            <b>rainSkipsWateringAmount</b><br>
            Typ: Slider (0–50 mm, Schritt 0.5). Standardwert: 0 (deaktiviert).<br>
            Ist im Fenster <code>rainAmountWindow</code> mindestens so viel Regen gefallen, wird der
            geplante Bewässerungszyklus (<code>StartWatering</code>/<code>activeValves</code>)
            übersprungen (<code>state</code> = <code>skipped - enough rain</code>). Unabhängige Kreise
            über <code>startCircuit</code> (z.&nbsp;B. Gewächshaus) sind nicht betroffen.
        </li>
        <li><a id="Gartenbewaesserung-attr-rainCollectionCheckAmount"></a>
            <b>rainCollectionCheckAmount</b><br>
            Typ: Slider (0–50 mm, Schritt 0.5). Standardwert: 0 (deaktiviert).<br>
            Überwachung der Regenwasser-Sammlung: Fällt so viel Regen, ohne dass Fass oder IBC eine
            Füllstands-Reaktion zeigen (<code>barrelFull:yes</code> bei Regen, <code>ibcFull:yes</code>
            oder <code>ibcEmpty:no</code>), wird <code>rainCollectionAlert</code> auf <code>yes</code>
            gesetzt (Hinweis auf verstopften Zulauf/Dachrinne/Filter). Ist der IBC bereits voll,
            wird kein Alarm ausgelöst.
        </li>
        <li><a id="Gartenbewaesserung-attr-ibcFillRainAmount"></a>
            <b>ibcFillRainAmount</b><br>
            Typ: Slider (0–20 mm, Schritt 0.1). Standardwert: 0 (deaktiviert).<br>
            Erweitert die Bedingung für die IBC-Befüllung. Ohne dieses Attribut startet die
            Befüllung nur, wenn es <b>genau in dem Moment regnet</b>, in dem der Fass-voll-Sensor
            anschlägt. Da Dach und Dachrinne nach Regenende nachlaufen, meldet das Fass oft erst
            deutlich später „voll" – das Zeitfenster wird dann verfehlt.<br>
            Ist der Wert &gt; 0, genügt es, dass seit der letzten Befüllung mindestens so viele mm
            gefallen sind (Reading <code>rainSinceHarvest_mm</code>, setzt
            <code>rainAmountDevice</code> voraus). Ein volles Fass wird dann auch nach dem Regen
            noch in den IBC übernommen, und eine laufende Befüllung wird bei Regenende nicht mehr
            abgebrochen – sie endet regulär bei <code>barrelEmpty</code>, <code>ibcFull</code> oder
            Bewässerungsstart.<br>
            <i>Schutz gegen Leitungswasser:</i> Sobald das Modul Stadtwasser aufdreht
            (<code>barrelFillValveDevice</code>, z.&nbsp;B. in der Nachfüllpause bei leerem IBC), wird
            <code>rainSinceHarvest_mm</code> auf 0 gesetzt – ein danach volles Fass löst also keine
            Ernte aus, bis wieder Regen gefallen ist.<br>
            <i>Grenze:</i> Ein rein <b>mechanischer</b> Schwimmer in der Hauswasserleitung ist für das
            Modul unsichtbar. Hält dieser das Fass bis zum <code>barrelFullSensorDevice</code>, kann
            das Modul Regen- und Leitungswasser nicht unterscheiden – in dem Fall sollte der Schwimmer
            unterhalb des Fass-voll-Sensors abregeln.
        </li>
        <li><a id="Gartenbewaesserung-attr-mainsSupplyDevice"></a>
            <b>mainsSupplyDevice</b><br>
            Typ: Text (<code>Device:Reading</code>), z.&nbsp;B. <code>d_RegenwasserPumpe:stadtwasser</code>.
            Ohne Vorgabe deaktiviert.<br>
            Zeigt an, ob die Hauswasserzufuhr zum Fass offen ist. Steht im Fass ein Schwimmerventil,
            füllt es während einer Befüllung Fass&nbsp;&rarr;&nbsp;IBC laufend nach – das geförderte
            Wasser ist dann <b>kein reiner Regen</b>. Das Modul kennzeichnet solche Läufe als
            <code>mixed</code>. Ist zusätzlich <code>barrelFloatLevel</code> gesetzt, wird ein
            solcher Lauf aufgeteilt statt verworfen.<br>
            <i>Reine Statistik:</i> Auf die Steuerung – Ernte-Trigger, Watchdog, Pausen – hat das
            Attribut keinen Einfluss. Die Werte für „an“/„aus“ lassen sich bei Bedarf über
            <code>mainsSupplyActiveValue</code> und <code>mainsSupplyInactiveValue</code> anpassen;
            ohne Angabe gelten die üblichen (<code>on</code>/<code>off</code> usw.).
        </li>
        <li><a id="Gartenbewaesserung-attr-barrelUsableVolume"></a>
            <b>barrelUsableVolume</b><br>
            Typ: Zahl (Liter). Ohne Vorgabe deaktiviert.<br>
            Nutzbares Fassvolumen zwischen Fass-voll- und Fass-leer-Sensor. Läuft eine Befüllung
            Fass&nbsp;&rarr;&nbsp;IBC von einem vollen Fass bis <code>barrelEmpty</code> durch, ist
            das bewegte Volumen damit bekannt; das Modul leitet daraus die aktuelle Förderrate ab
            (<code>ibcFillFlow_lpm</code>). Schaltet außerdem die Füllstandsschätzung des Fasses
            frei (<code>barrelLevel_l</code>): drei Ankerpunkte – <code>barrelFull</code> setzt auf
            das volle Volumen, <code>barrelEmpty</code> auf 0, und bei offener Hauswasserzufuhr hält
            das Schwimmerventil <code>barrelFloatLevel</code> als Untergrenze, sobald der
            Leer-Kontakt frei ist und nichts entnimmt. Dazwischen wird gerechnet: Regen und Rücklauf
            aus dem IBC kommen drauf, Förderung ins IBC und Gießen gehen ab.
        </li>
        <li><a id="Gartenbewaesserung-attr-barrelFloatLevel"></a>
            <b>barrelFloatLevel</b><br>
            Typ: Zahl (Liter). Ohne Vorgabe deaktiviert.<br>
            Füllstand, auf dem das Schwimmerventil der Hauswasserleitung das Fass hält – gemessen
            ab derselben Linie wie <code>barrelUsableVolume</code>, also ab dem Fass-leer-Sensor.
            Damit lässt sich ein Lauf mit offener Hauswasserzufuhr aufteilen: Was <b>über</b> der
            Schwimmerhöhe stand, ist Regen; ab dem Moment, in dem der Pegel den Schwimmer erreicht,
            fördert die Pumpe nur noch gespeichertes und nachlaufendes Leitungswasser. Der
            Regenanteil eines solchen Laufs ist deshalb konstant
            <code>barrelUsableVolume - barrelFloatLevel</code>, unabhängig davon, wie lange die
            Pumpe danach noch läuft.<br>
            <i>Bestimmen:</i> zweimal messen, jeweils mit <b>geschlossener</b> Hauswasserzufuhr –
            einmal von vollem Fass bis <code>barrelEmpty</code> (Zeit T&#8321;), einmal von
            Schwimmerhöhe bis <code>barrelEmpty</code> (T&#8322;). Dann ist
            <code>barrelFloatLevel = barrelUsableVolume &times; T&#8322; / T&#8321;</code>. Das
            Verhältnis zweier Pumpenlaufzeiten genügt, eine Durchflussmessung ist nicht nötig.<br>
            Ohne dieses Attribut bleibt es beim bisherigen Verhalten: Läufe mit offener
            Hauswasserzufuhr zählen gar nicht in <code>pumpedRain_total_l</code>.
        </li>
        <li><a id="Gartenbewaesserung-attr-ibcUsableVolume"></a>
            <b>ibcUsableVolume</b><br>
            Typ: Zahl (Liter). Ohne Vorgabe deaktiviert.<br>
            Nutzbares Volumen des IBC zwischen Leer- und Voll-Sensor. Schaltet die
            Füllstandsschätzung frei (<code>ibcLevel_l</code>).<br>
            <i>Wie sie funktioniert:</i> Der IBC hat keinen Pegelgeber. Der Stand wird deshalb
            mitgeführt – jede Befüllung Fass&nbsp;&rarr;&nbsp;IBC kommt drauf, jeder Rücklauf per
            Schwerkraft geht ab. Das ist eine Integration und driftet: beide Raten sind gelernte
            Mittelwerte, und die Schwerkraftrate ist nicht einmal konstant, weil ein voller IBC
            stärker drückt als ein fast leerer. Deshalb wird jeder verfügbare Ankerpunkt genutzt,
            um den Wert zurückzusetzen – <code>ibcEmpty</code> setzt ihn auf 0, <code>ibcFull</code>
            auf <code>ibcUsableVolume</code>, und <code>set &lt;name&gt; ibcLevel &lt;liter&gt;</code>
            übernimmt einen abgelesenen Wert. <code>ibcLevelAnchor</code> zeigt, woher die aktuelle
            Zahl stammt; je älter der Anker, desto mehr Drift konnte sich sammeln.<br>
            Solange noch kein Anker gesetzt wurde, bleibt <code>ibcLevel_l</code> leer – das Modul
            erfindet keinen Startwert.
        </li>
        <li><a id="Gartenbewaesserung-attr-ibcFullFromLevel"></a>
            <b>ibcFullFromLevel</b><br>
            Typ: 0 oder 1. Standardwert: 0 (aus).<br>
            Erlaubt der Füllstandsschätzung, selbst <code>ibcFull</code> zu melden – sinnvoll, wenn
            es keinen Voll-Sensor gibt und der Zustand bisher von Hand gesetzt wurde. Beim Start
            einer Befüllung rechnet das Modul aus dem freien Rest und <code>ibcFillFlow_lpm</code>
            aus, wann der Behälter voll ist, und stellt einen Wecker; der Lauf endet dann von
            selbst. Fällt der Stand später wieder unter die Kapazität, geht <code>ibcFull</code>
            von allein auf <code>no</code> zurück.<br>
            <i>Damit wird die Schätzung steuernd, nicht mehr nur beschreibend.</i> Zu hoch geschätzt
            heißt verschenkter Regen, zu niedrig heißt weiterhin Überlauf. Ein vorhandener Sensor
            bzw. der Dummy hat weiterhin Vorrang und verankert den Stand – er bleibt die Korrektur
            von außen, ebenso wie <code>set &lt;name&gt; ibcLevel</code>.<br>
            Voraussetzungen: <code>ibcUsableVolume</code>, ein gesetzter Anker und eine gelernte
            Förderrate. Fehlt eines davon, passiert nichts.
        </li>
        <li><a id="Gartenbewaesserung-attr-ibcFillFlow_lpm"></a>
            <b>ibcFillFlow_lpm</b> / <b>ibcToBarrelFlow_lpm</b><br>
            Typ: Text (Liter pro Minute). Ohne Angabe: nur der gelernte Wert.<br>
            Rückfallebene für die beiden Förderraten – Pumpe Fass→IBC und Schwerkraft
            IBC→Fass. Gelesen wird zuerst das gleichnamige <b>Reading</b>, das das Modul
            aus vollständigen Läufen lernt; erst wenn das fehlt, greift dieses Attribut.<br>
            Nötig, weil nur aus Läufen mit <b>bekannter Menge</b> gelernt wird (siehe unten)
            und ein Statefile-Rückfall das Reading wieder kosten kann. Ohne
            Rate rechnet das Modul die Füllstände während eines Transports nicht mit, und
            die <code>watertank</code>-Kachel steht still, obwohl das Rohr leuchtet.<br>
            <b>Wofür die Raten taugen und wofür nicht:</b> jeder Durchfluss der Anlage ist
            veränderlich – die Schwerkraft IBC→Fass hängt am Füllstand des IBC, Pumpe und
            Gießkreise am Verschmutzungsgrad des Filters. Für die <b>Darstellung</b> reichen
            sie trotzdem, auch bei unvollständigen Läufen. Für die <b>Buchhaltung</b> zählt
            nur, was an den Fass-Kontakten gemessen wurde; eine ratenbasierte Buchung wird
            deshalb seit v1.0.74 am Fassmaß gedeckelt und kann kein Wasser mehr erfinden.
        </li>
        <li><a id="Gartenbewaesserung-attr-wateringFlow_lpm"></a>
            <b>wateringFlow_lpm</b><br>
            Typ: Zahl (Liter je Minute Ventil-Offenzeit). Ohne Vorgabe deaktiviert.<br>
            Wie viel Wasser eine Minute Gießen aus dem Fass zieht. Nur für die
            Füllstandsschätzung; die Steuerung berührt es nicht.<br>
            Das Modul lernt diesen Wert selbst, wenn ein volles Fass <b>allein durch Gießen</b> bis
            <code>barrelEmpty</code> leerläuft – das gleichnamige Reading hat dann Vorrang. Endet
            die Bewässerung aber regelmäßig vorher, etwa weil das Schwimmerventil nachspeist oder
            die Laufzeit um ist, greift die Lernbedingung <b>nie</b>, und das Attribut ist der
            einzige Weg zu einer brauchbaren Zahl.<br>
            <i>Bestimmen:</i> Fass bis <code>barrelFull</code> füllen lassen, eine Bewässerung
            laufen lassen, danach den Stand ablesen. <code>(250 - Restmenge) ÷ Ventilminuten</code>.
            Die Ventilminuten stehen im Log zwischen <code>currentValve: 8</code> und
            <code>currentValve: none</code>.<br>
            Ohne beides zieht das Modul pauschal 12&nbsp;% der nutzbaren Kapazität je Ventil ab –
            das alte Verhalten, das die Laufzeit ignoriert und im Log einen Hinweis hinterlässt.<br>
            Gilt für alle Kreise gemeinsam. Unterscheiden sie sich – andere Sprenger, unterschiedlich
            viele –, ist <code>valve&lt;N&gt;Flow_lpm</code> der genauere Weg.
        </li>
        <li><a id="Gartenbewaesserung-attr-valveNFlow_lpm"></a>
            <b>valve1Flow_lpm</b> … <b>valve8Flow_lpm</b><br>
            Typ: Zahl (Liter je Minute Offenzeit). Ohne Vorgabe deaktiviert.<br>
            Entnahmerate eines <b>einzelnen</b> Kreises. Jeder Kreis hat andere Sprenger und nicht
            gleich viele, eine gemeinsame Rate ist deshalb bestenfalls ein Mittelwert.<br>
            Reihenfolge, in der die Füllstandsschätzung sucht: gelerntes Reading
            <code>valve&lt;N&gt;Flow_lpm</code>, dann das gleichnamige Attribut, dann das gelernte
            <code>wateringFlow_lpm</code>, dann dessen Attribut, zuletzt der Pauschalabzug.<br>
            <i>Gelernt</i> wird je Kreis, wenn zwischen zwei Ankern <b>nur dieser eine</b> gelaufen
            ist und dabei ein volles Fass bis <code>barrelEmpty</code> leergezogen wurde. Kürzere
            Kreise schaffen das nicht – für die bleibt das Attribut der Weg.<br>
            <i>Bestimmen:</i> je Kreis einmal aus vollem Fass laufen lassen und die Restmenge
            ablesen – <code>(barrelUsableVolume - Restmenge) ÷ Ventilminuten</code>.
        </li>
        <li><a id="Gartenbewaesserung-attr-roofArea"></a>
            <b>roofArea</b><br>
            Typ: Zahl (Quadratmeter). Ohne Vorgabe deaktiviert.<br>
            Dachfläche, die über das Fallrohr in das Fass entwässert. Maßgeblich ist die
            <b>waagerechte Projektion</b> (Länge der Dachrinne × waagerechter Abstand Traufe→First),
            nicht die Schrägfläche – Regen fällt senkrecht, ein steileres Dach fängt daher nicht mehr
            auf. Aktiviert die Ertragsstatistik (<code>harvest_*_l</code>).
        </li>
        <li><a id="Gartenbewaesserung-attr-runoffCoefficient"></a>
            <b>runoffCoefficient</b><br>
            Typ: Zahl zwischen 0 und 1. Standardwert: 0.8.<br>
            Abflussbeiwert für die Ertragsberechnung – berücksichtigt Benetzung, Verdunstung und
            Erstspülung. DIN 1989-1 nennt 0.8 für harte Bedachung (Ziegel); für Metall- oder
            Glasdächer sind Werte bis 0.9 üblich.
        </li>
        <li><a id="Gartenbewaesserung-attr-rainCollectionCheckDelay"></a>
            <b>rainCollectionCheckDelay</b><br>
            Typ: Slider (5–720 Minuten). Standardwert: 120 Minuten.<br>
            Wartezeit nach Erreichen von <code>rainCollectionCheckAmount</code>, bevor der Alarm
            gesetzt wird – zeigt sich in dieser Zeit eine Füllstands-Reaktion, gilt die Sammlung
            als in Ordnung.
        </li>
        <li><a id="Gartenbewaesserung-attr-pumpStartDelay"></a>
            <b>pumpStartDelay</b><br>
            Typ: Slider (-30 bis +30 Sekunden). Standardwert: 3 Sekunden.<br>
            Startverzögerung zwischen Pumpe und Ventil.
            Positiv: Pumpe startet X Sekunden VOR dem Ventil (Druckaufbau).
            Negativ: Ventil öffnet X Sekunden VOR der Pumpe (Druckentlastung).
            0: Ventil öffnet unmittelbar VOR der Pumpe (kein Verzug).
            Gilt für alle Startpfade – zeitgesteuerte Bewässerung, <code>startCircuit</code>,
            <code>startValve</code> sowie die pumpengestützten Füll-/Transfer-Vorgänge
            (IBC-Befüllung, IBC→Fass, Nachfüllpause). Nur bei positivem Wert läuft die Pumpe vor dem
            Ventil an; bei 0 oder negativem Wert öffnet immer zuerst das Ventil, damit die Pumpe nie
            gegen ein geschlossenes Ventil arbeitet.
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
            Watchdog für die Fass-Befüllung. Als Erfolg zählt ausschließlich
            <code>barrelFull</code>. Das ist Absicht: Steht im Fass ein Schwimmerventil aus der
            Hauswasserleitung, wird <code>barrelEmpty</code> auch bei staubtrockenem IBC binnen
            Minuten wieder <code>no</code> – „Wasser ist da“ sagt dann nichts über die
            konfigurierte Quelle aus. Nur der Voll-Kontakt unterscheidet: Ein IBC mit Wasser hebt
            das Fass bis dorthin, ein Schwimmer allein bleibt darunter. Genau daraus lässt sich
            ein leerer IBC ableiten.<br>
            Wird das Befüllventil
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
            <code>barrelFull:yes</code> (maßgebliches Signal bei konfiguriertem
            <code>barrelFullSensorDevice</code>) oder <code>ibcEmpty:no</code> (IBC hat wieder Wasser).
            Regen allein zählt bewusst nicht — Nieselregen füllt das Fass nicht; füllt Regen es, meldet
            das ohnehin der Fass-voll-Sensor. 0 = deaktiviert (altes Verhalten, endlose Versuche).
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

        <li><a id="Gartenbewaesserung-attr-valveName"></a>
            <b>valve1Name .. valve8Name</b><br>
            Typ: textField. Optional.<br>
            Klartext-Name für den jeweiligen Kreis/das Ventil (z.B. <code>valve8Name Gewächshaus</code>).
            Der Name erscheint in den Log-Meldungen, im <code>phase</code>-Reading
            (z.B. <code>watering circuit 8 (Gewächshaus)</code>) und im Reading
            <code>currentValveName</code>. Reine Lesbarkeit, keine Auswirkung auf die Logik.
        </li>

        <li><a id="Gartenbewaesserung-attr-rainSkipsWatering"></a>
            <b>rainSkipsWatering</b><br>
            Typ: 0/1. Standardwert: 0.<br>
            1 = Regnet es zum geplanten Startzeitpunkt (<code>raining: yes</code>), wird der
            komplette Bewässerungszyklus (<code>activeValves</code>) übersprungen
            (State <code>skipped - raining</code>). Unabhängige Einzelkreise, die per
            <code>set ... startCircuit N</code> gestartet werden (z.B. ein überdachtes
            Gewächshaus, das vom Regen nichts abbekommt), sind davon NICHT betroffen.
            0 = Regen setzt die Bewässerung nicht aus (nur der Feuchte-Check greift).
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
        <li><a id="Gartenbewaesserung-attr-mainsSupplyActiveValue"></a>
            <b>mainsSupplyActiveValue</b> / <b>mainsSupplyInactiveValue</b><br>
            Typ: Text. Ohne Angabe gilt die übliche Erkennung (<code>on</code>/<code>off</code>,
            <code>1</code>/<code>0</code>, <code>true</code>/<code>false</code> …).<br>
            Werte, an denen <code>mainsSupplyDevice</code> „Zufuhr offen“ bzw. „Zufuhr zu“ erkennt.
            Nur nötig, wenn das Gerät eigene Begriffe verwendet.
        </li>
        <li><a id="Gartenbewaesserung-attr-mainsFillFlow_lpm"></a>
            <b>mainsFillFlow_lpm</b><br>
            Typ: Text (Liter pro Minute). Ohne Angabe: kein Mitrechnen.<br>
            Zulaufrate der Hauswasserleitung ins Fass. Steht <code>mainsSupply</code> auf
            <code>on</code> und läuft gerade kein anderer Transport, steigt
            <code>barrelLevel_l</code> im Minutentakt mit dieser Rate – sonst bliebe der
            Füllstand während einer Leitungswasser-Befüllung auf seinem alten Wert stehen.<br>
            Begrenzt wird auf <code>barrelFloatLevel</code>, ersatzweise auf
            <code>barrelUsableVolume</code>: über ein Schwimmerventil steigt der Pegel nur bis
            zur Schwimmerhöhe. Ohne dieses Attribut bleibt es beim bisherigen Verhalten – einem
            Sprung auf <code>barrelFloatLevel</code>.<br>
            Messen: Wasserzähler ablesen, Hahn auf, nach ein paar Minuten wieder ablesen. Der
            Wert ist deutlich kleiner als der Nenndurchfluss der Leitung – in der Anlage des
            Autors 4,4 l/min bei geschätzten 12 l/min Zuleitung.
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
        <li><b>currentValve</b> - Aktuell aktives Ventil (1–8) oder <code>none</code>.</li>
        <li><b>orphanShutdown</b> - Zeitpunkt und Liste der Aktoren, die nach einem Neustart noch eingeschaltet waren und vom Modul abgeschaltet wurden. Steht hier etwas, lief beim letzten Neustart eine Pumpe oder ein Ventil ohne Aufsicht weiter – der Eintrag bleibt stehen, bis es wieder passiert.</li>
        <li><b>phase</b> - Was das Modul gerade tut, im Klartext (<code>watering circuit 8</code>, <code>pause - refilling</code>, <code>idle</code> …). Feiner als <code>state</code> und vor allem zum Mitlesen im Log gedacht.</li>
        <li><b>barrelFull</b> / <b>barrelEmpty</b> - <code>yes</code>/<code>no</code> laut <code>barrelFullSensorDevice</code> bzw. <code>barrelEmptySensorDevice</code>, sonst <code>not configured</code>. Die beiden sind die einzigen <b>physischen</b> Aussagen über das Fass – alle Füllstandszahlen verankern sich an ihnen.</li>
        <li><b>ibcFull</b> / <b>ibcEmpty</b> - dasselbe für den IBC.</li>
        <li><b>ibcFilling</b> - <code>yes</code>, solange vom Fass in den IBC gefördert wird. <b>ibcFillStarted</b> hält den Startzeitpunkt fest; beides zusammen erlaubt es, einen Lauf nach einem Neustart wieder aufzunehmen.</li>
        <li><b>ibcToBarrelActive</b> - <code>yes</code>, solange Wasser aus dem IBC ins Fass läuft (Schwerkraft oder Pumpe).</li>
        <li><b>pauseActive</b> / <b>pauseTimeRemaining</b> - Ob gerade eine Nachfüllpause läuft und wie lange noch. Pausen entstehen aus <code>wateringPauseInterval</code> oder weil das Fass leer wurde.</li>
        <li><b>nextValve</b> / <b>cycleProgress</b> - Nächstes Ventil der Warteschlange und Fortschritt im Zyklus (<code>3/5</code>).</li>
        <li><b>remainingTime</b> - Restlaufzeit des aktuellen Ventils in Minuten.</li>
        <li><b>lastWatering</b> / <b>lastCircuitWatering</b> - Zeitpunkt der letzten kompletten Bewässerung bzw. des letzten Einzelkreises.</li>
        <li><b>raining</b> / <b>rainDetectedSince</b> - Zustand des <code>rainSensorDevice</code> und seit wann Regen gemeldet wird. <code>raining</code> allein ist träge – für Mengen ist <code>rainAmount_mm</code> die bessere Quelle.</li>
        <li><b>soilMoisture</b> - Letzter Wert des <code>soilSensorDevice</code> in Prozent.</li>
        <li><b>currentValveName</b> - Klartext-Name des aktuell aktiven Kreises (aus <code>valveNName</code>) oder <code>none</code>.</li>
        <li><b>state</b> - u.a. <code>stopped - no water</code>, wenn das Fass trotz wiederholtem Nachfüllen leer bleibt (siehe <code>barrelEmptyMaxRefillAttempts</code>); <code>skipped - raining</code> bei <code>rainSkipsWatering</code>; <code>skipped - enough rain (X mm)</code> bei <code>rainSkipsWateringAmount</code>.</li>
        <li><b>rainAmount_mm</b> - Aufsummierte Regenmenge (mm) im gleitenden Fenster <code>rainAmountWindow</code> (aus <code>rainAmountDevice</code>, reset-fest berechnet).</li>
        <li><b>rainSinceFill_mm</b> - Regenmenge (mm) seit der letzten erkannten Füllstands-Reaktion von Fass/IBC. Grundlage der Sammel-Überwachung; wird bei einer Füllstands-Reaktion auf 0 zurückgesetzt.</li>
        <li><b>rainCollectionAlert</b> - <code>yes</code>/<code>no</code>; <code>yes</code>, wenn mindestens <code>rainCollectionCheckAmount</code> mm Regen fiel, ohne dass Fass/IBC innerhalb von <code>rainCollectionCheckDelay</code> Minuten Wasser meldeten (Zulauf/Dachrinne/Filter prüfen). Reset automatisch bei der nächsten Füllstands-Reaktion.</li>
        <li><b>rainSinceHarvest_mm</b> - Regenmenge (mm) seit der letzten IBC-Befuellung. Steuert zusammen mit <code>ibcFillRainAmount</code>, wann geerntet wird, und wird beim Start einer Befuellung auf 0 gesetzt - eine neue Ernte braucht daher immer neuen Regen.</li>
        <li><b>mainsSupply</b> - <code>on</code>/<code>off</code>; Zustand der Hauswasserzufuhr laut <code>mainsSupplyDevice</code>. Mit <code>mainsFillFlow_lpm</code> lässt das Modul <code>barrelLevel_l</code> währenddessen mitsteigen.</li>
        <li><b>mainsFillIbcTarget</b> / <b>mainsFillIbcDone</b> / <b>mainsFillIbcState</b> - Auftrag, Fortschritt und Lage einer Befüllung per <code>set … mainsFillIbc</code>. <code>Target</code> auf <code>0</code> heißt: kein Auftrag aktiv, und <code>State</code> hält dann fest, warum er endete (<code>done</code>, <code>ibcFull</code>, <code>no water - tap closed?</code>, <code>stopped by hand</code>).</li>
        <li><b>lastIbcFillSource</b> - <code>rain</code> (Hauswasser war zu, reines Regenwasser), <code>mixed</code> (Hauswasser offen, Leitungswasser lief mit), <code>other</code> (angesagtes Fremdwasser, siehe <code>set &lt;name&gt; waterSource</code>) oder <code>unknown</code> (kein <code>mainsSupplyDevice</code> gesetzt).</li>
        <li><b>pumped_total_l</b> / <b>pumpedRain_total_l</b> / <b>mains_total_l</b> - Insgesamt vom Fass in den IBC gefördertes Volumen, aufgeteilt in Regen- und Leitungswasseranteil. <code>pumpedRain_total_l</code> lässt sich direkt gegen <code>harvest_total_l</code> halten: Weichen die Werte dauerhaft voneinander ab, stimmt <code>roofArea</code> nicht. Läufe mit offener Hauswasserzufuhr steuern ihren Regenanteil nur bei, wenn <code>barrelFloatLevel</code> gesetzt ist. Zurücksetzen mit <code>set &lt;name&gt; resetHarvestStats</code>.</li>
        <li><b>waterSource</b> - <code>rain</code> (Normalfall) oder <code>other</code>, siehe <code>set &lt;name&gt; waterSource</code>. Fällt beim nächsten <code>barrelEmpty</code> automatisch auf <code>rain</code> zurück.</li>
        <li><b>pumpedOther_total_l</b> - Insgesamt gefördertes Volumen aus Fremdwasser-Läufen. Bewusst getrennt von <code>pumpedRain_total_l</code>, damit der Abgleich gegen <code>harvest_total_l</code> und damit die Bestimmung von <code>roofArea</code> sauber bleibt.</li>
        <li><b>lastIbcFillRain_l</b> / <b>lastIbcFillMains_l</b> - Aufteilung des letzten Laufs. Nur gefüllt, wenn <code>mainsSupplyDevice</code> konfiguriert ist.</li>
        <li><b>barrelLevel_l</b> / <b>barrelLevel</b> / <b>barrelLevelAnchor</b> - Geschätzter Fass-Füllstand in Litern bzw. Prozent, und woher der Wert zuletzt verankert wurde (<code>barrelFull</code>, <code>barrelEmpty</code>, <code>float valve</code>) mit Zeitstempel. <code>barrelLevel_l</code> setzt <code>barrelUsableVolume</code> voraus; <code>barrelLevel</code> gibt es immer – ohne das Attribut als alte Simulation, mit ihm aus den Litern abgeleitet.</li>
        <li><b>wateringFlow_lpm</b> - Gelernte Entnahmerate beim Gießen in Litern pro Minute Ventil-Offenzeit. Gelernt wird nur, wenn ein volles Fass <b>allein durch Gießen</b> bis <code>barrelEmpty</code> leerläuft – kommt zwischendurch Wasser nach (Regen, IBC, Hauswasser), wird der Lauf verworfen. Erreicht die Bewässerung den Leer-Kontakt nie, greift stattdessen das gleichnamige <b>Attribut</b>; ohne beides bleibt es beim Pauschalabzug von 12 % je Ventil.</li>
        <li><b>ibcLevel_l</b> / <b>ibcLevel_pct</b> / <b>ibcLevelAnchor</b> - Geschätzter IBC-Füllstand in Litern bzw. Prozent, und woher der Wert zuletzt verankert wurde (<code>ibcEmpty</code>, <code>ibcFull</code>, <code>manual</code>) mit Zeitstempel. Setzt <code>ibcUsableVolume</code> voraus. <b>Eine Schätzung, keine Messung</b> – siehe dort.</li>
        <li><b>ibcToBarrelFlow_lpm</b> / <b>lastIbcToBarrelVolume_l</b> - Gelernte Rate der Schwerkraftrichtung IBC&nbsp;&rarr;&nbsp;Fass und die daraus geschätzte Menge des letzten Rücklaufs. Gelernt wird nur aus Läufen, die bei leerem Fass beginnen und mit <code>barrelFull</code> enden – die haben <code>barrelUsableVolume</code> bewegt.</li>
        <li><b>lastIbcToBarrelDuration</b> / <b>lastIbcToBarrelEnd</b> - Dauer (Minuten) und Endgrund (<code>barrelFull</code>, <code>pauseEnd</code>) des letzten Laufs IBC&nbsp;&rarr;&nbsp;Fass, einschließlich der Schwerkraft-Nachspeisung während einer Gießpause.</li>
        <li><b>lastIbcFillDuration</b> / <b>lastIbcFillEnd</b> / <b>lastIbcFillVolume_l</b> - Dauer (Minuten), Endgrund (<code>barrelEmpty</code>, <code>ibcFull</code>, <code>watering</code>, <code>rainStopped</code>, <code>ibcToBarrel</code>, <code>manual</code>) und bewegtes Volumen der letzten Befüllung Fass&nbsp;&rarr;&nbsp;IBC.</li>
        <li><b>ibcFillFlow_lpm</b> - Gelernte Förderrate in Litern pro Minute, gedämpft gemittelt, sinkt also automatisch mit, wenn der Filter zusetzt. Fortgeschrieben wird sie aus den beiden Läufen mit <b>bekannter Menge</b>: aus dem vollen Fass bis <code>barrelEmpty</code> (das sind <code>barrelUsableVolume</code>, braucht aber Regen) und – seit v1.0.74 – aus einer Stadtwasser-Runde von der Schwimmerhöhe bis <code>barrelEmpty</code> (das sind <code>barrelFloatLevel</code>). Ohne den zweiten Fall bliebe die Rate in einer regenlosen Woche stehen, während die Pumpe längst langsamer geworden ist. Ein Wert, der mehr als das Doppelte oder weniger als 40&nbsp;% des bisherigen ergäbe, wird verworfen statt gelernt.</li>
        <li><b>harvest_today_l</b> / <b>harvest_month_l</b> / <b>harvest_year_l</b> / <b>harvest_total_l</b> - Aufgefangene Regenwassermenge in Litern (heute, laufender Monat, laufendes Jahr, seit Inbetriebnahme). Berechnet als <code>Regenmenge (mm) × roofArea × runoffCoefficient</code>; nur aktiv, wenn <code>roofArea</code> gesetzt ist. Die Perioden-Zähler starten bei Tages-, Monats- bzw. Jahreswechsel automatisch neu, <code>harvest_total_l</code> läuft weiter. Zurücksetzen mit <code>set &lt;name&gt; resetHarvestStats</code>.<br>
            <i>Grenze:</i> Der Wert beziffert, was am Fallrohr ankommt. Was bei vollem Fass überläuft, kann nicht abgezogen werden – die tatsächlich gespeicherte Menge liegt also darunter.</li>
    </ul>

</ul>

=end html

=cut
