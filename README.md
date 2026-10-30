# diskspeed

Kurzer Speicher-Benchmark für Ubuntu/Debian und Fedora mit farbiger Ausgabe.
Fehlende Komponenten werden automatisch über `apt-get` bzw. `dnf` installiert
(als root oder mit `sudo`).

## Herunterladen und starten

```bash
curl -fL https://raw.githubusercontent.com/kramervanessa/diskspeed/main/diskspeed.sh -o diskspeed.sh
bash diskspeed.sh
```

Ein anderes Laufwerk testen:

```bash
bash diskspeed.sh /mnt/data
```

## Messungen

- 8 GiB vollständig beschriebene Testdatei; mindestens 9 GiB freier Platz.
- Sechs Tests mit jeweils 30 Sekunden Messung und 3 Sekunden Aufwärmen.
- Sequenzielles Lesen/Schreiben (1 MiB, QD16).
- Zufälliges Lesen/Schreiben (4 KiB, QD1 und QD32).
- Zusätzlich 20 Sekunden sequenzielles 4-KiB-Schreiben mit `fsync` nach jedem Zugriff.
- Durchsatz, IOPS, durchschnittliche Latenz und P99.
- Stabilität anhand von Sekundenabschnitten (Streuung und Minimum).

Dauer ungefähr 4 Minuten, abhängig von der Vorbereitung auch länger.
Möglichst ohne andere Last und mit gleichen Einstellungen vergleichen.

```bash
SECONDS_PER_TEST=60 bash diskspeed.sh
```

Die Option verändert die sechs Basistests; der fsync-Test bleibt bei 20 Sekunden.
Farben erscheinen im Terminal; `NO_COLOR=1` deaktiviert sie.

## Bewertung und Grenzen

Die Farbschwellen sind grobe Richtwerte und werden in der Ausgabe erklärt.
Es gibt keine pauschale Gesamtnote. Anbieter-Caches und kurzfristige
Leistungsreserven können das Ergebnis beeinflussen. Der fsync-Test vergleicht
synchrones Schreiben, nicht die gesamte Datenbankleistung; er prüft nicht,
ob Hardware Bestätigungen bei einem echten Stromausfall einhält.
Die fsync-Latenzen beziehen sich nur auf den Sync-Aufruf, die Rate auf bestätigte
Write+fsync-Zyklen.

Das Skript verwendet ausschließlich eine eigene temporäre Testdatei im gewählten
Zielordner. Testdatei und Ergebnisse werden bei Abschluss, Fehlern und üblichen
Abbruchsignalen entfernt. Bei Stromausfall oder `kill -9` ist keine automatische
Bereinigung möglich; dann kann ein `.diskspeed.*`-Ordner zurückbleiben.

## Prüfung

Die Basistests wurden auf Ubuntu ausgeführt. Die fsync-Auswertung wurde mit einem
kurzen lokalen fio-Lauf auf macOS geprüft. Syntax und ShellCheck sind geprüft;
die Installationspfade für apt-get und dnf wurden simuliert getestet.
Ein vollständiger Fedora-Lauf steht noch aus.
