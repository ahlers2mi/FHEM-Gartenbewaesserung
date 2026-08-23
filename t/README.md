# Tests

Zwei Werkzeuge, beide ohne FHEM-Installation lauffähig. Beide sind entstanden,
nachdem eine Endlosrekursion in der Nacht zum 23.08.2026 die produktive
FHEM-Instanz für über eine Stunde blockiert hat — `perl -c` und Durchlesen
hatten sie nicht gefunden.

## `cycles.py` — Aufrufzyklen ohne Timer

```
python3 t/cycles.py FHEM/98_Gartenbewaesserung.pm
```

Baut den Aufrufgraphen der `Gartenbewaesserung_*`-Subs und sucht Zyklen, bei
denen **kein `InternalTimer`** dazwischenliegt. Ein solcher Zyklus ist eine
Rekursion, die nicht über die Ereignisschleife unterbrochen wird: sie läuft in
derselben Sekunde durch, bis der Stack voll ist.

Aufrufe innerhalb der Argumentliste von `InternalTimer(...)` werden
ausgeblendet — die sind harmlos, weil sie erst im nächsten Durchlauf greifen.

Exitcode 1, wenn etwas gefunden wurde. Der Selbstaufruf `NextValve ->
NextValve` ist bekannt und harmlos: er erhöht vorher `wateringIndex`, ist also
durch die Länge der Warteschlange begrenzt.

Gegen den Stand vom 22.08. gehalten meldet das Werkzeug:

```
NextValve -> FillBarrel -> NextValve
```

## `run.pl` — Szenario-Tests gegen eine FHEM-Attrappe

```
perl t/run.pl FHEM/98_Gartenbewaesserung.pm
```

`FhemStub.pm` baut so viel FHEM nach, wie das Modul braucht: Readings,
Attribute, Events, `Log3`, Gerätewechsel — und vor allem eine **virtuelle Uhr**.
`time()` und `gettimeofday()` liefern `$main::NOW`, `advance($sekunden)` schiebt
sie vor und feuert dabei die fälligen Timer in der richtigen Reihenfolge. Ein
20-Minuten-Ventil läuft damit in Millisekunden ab.

Rekursionen werden mit `alarm 5` abgefangen, damit ein Fehler den Testlauf nicht
selbst blockiert. Zum Ausprobieren empfiehlt sich zusätzlich `ulimit -v 800000`.

Abgedeckt:

| | |
|---|---|
| A | Endlosrekursion ohne `barrelFillValveDevice` (Regression 23.08.2026) |
| B | Vollständiger Zyklus: alle drei Kreise in der richtigen Reihenfolge |
| C | Volles Fass — Nachfüllpause entfällt (v1.0.62) |
| D | Nachlauf in ein volles Fass wird vom Wächter gestoppt (v1.0.62) |
| E | Stadtwasser hebt den Füllstand, gedeckelt auf `barrelFloatLevel` (v1.0.63) |
| F | `mainsFillIbc` dreht Runden bis zum Ziel (v1.0.64) |
| G | Offenes Ventil wird vor dem Lernen abgerechnet (v1.0.62) |
| H | Neustart mitten im Pumpen — verwaiste Aktoren werden abgeschaltet (v1.0.68) |
| I | Ohne Waisen passiert nichts (Gegenprobe zu H) |
| J | Förderrate nur als Attribut — Reading hat Vorrang, ohne beides 0 (v1.0.69) |
| K | Manuelles `startIBCtoBarrel` wird abgerechnet (v1.0.70) |
| L | Manueller Transfer in ein volles Fass — Wächter greift (v1.0.70) |
| M | Gießen, dann Rest abpumpen — keine falsche Gießrate gelernt (v1.0.71) |

### Fallstricke beim Erweitern

- Die Förderraten (`ibcFillFlow_lpm`, `ibcToBarrelFlow_lpm`) liest das Modul als
  **Reading**, nicht als Attribut — es lernt sie im Betrieb. Im Testaufbau
  müssen sie als Reading gesetzt werden, sonst rechnet das Modul mit 0.
- `mainsFillFlow_lpm` ist dagegen ein **Attribut**. Fehlt es, springt der
  Füllstand über `ApplyBarrelFloatFloor` sofort auf `barrelFloatLevel`, statt
  mit der Rate zu steigen.
- Die Attrappe wertet das Modul mit einer `use vars`-Präambel aus, statt es zu
  `require`n: das Modul läuft unter `use strict` und erwartet die FHEM-Globals
  als bereits deklariert — genau wie `fhem.pl` es beim Einlesen tut.
