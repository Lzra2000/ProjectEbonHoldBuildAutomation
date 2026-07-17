# EbonBuilds

[English](README.md) | **[Deutsch](README.de.md)** | [Русский](README.ru.md) | [Português (Brasil)](README.pt-BR.md) | [Español](README.es.md) | [Français](README.fr.md) | [Polski](README.pl.md)

Ein World-of-Warcraft-Addon (3.3.5a) für **ProjectEbonhold**, das Echo-Auswahlen (Banish / Reroll / Freeze / Select) anhand eines von dir definierten Builds automatisiert und sich über die Zeit anhand echter Spieldaten selbst nachjustiert.

Benötigt **ProjectEbonhold** oder **ProjectEbonhold Enhanced**. Manche Funktionen nutzen zusätzlich **[Details!](https://www.curseforge.com/wow/addons/details)**, falls installiert.

## Was es macht

- **Build definieren**: Gewichte pro Echo, Quality-/Family-/Novelty-Boni, gesperrte Slots, gebannte Echoes.
- **Automation**: bewertet jeden Echo-Auswahlbildschirm gegen deinen Build und handelt (banish/reroll/freeze/select), damit du es nicht musst.
- **Tuning Advisor**: vergleicht deine Banish/Reroll/Freeze-Schwellenwerte mit dem, was dein Build tatsächlich angeboten bekommt (kein theoretisches Modell), schlägt bessere Werte vor und kann sie über Zeit schrittweise automatisch anpassen.
- **Budget-Pacing über den ganzen Run**: Schwellenwerte werden automatisch strenger, je weniger Banish-/Reroll-/Freeze-Charges übrig sind, damit du die letzten Charges nicht auf Grenzfälle verschwendest.
- **DPS- und Erscheinungswahrscheinlichkeits-Tracking**: mit installiertem Details! wird echter DPS pro aktivem Echo getrackt; wie oft ein Echo überhaupt angeboten wird, wird immer getrackt. Beides kann optional mit anderen Spielern derselben Klasse synchronisiert werden.
- **Manual Training Mode**: Automation für einen Build pausieren, manuell wählen — EbonBuilds lernt aus deinen Entscheidungen und leitet Gewichts-Vorschläge daraus ab, was du tatsächlich bevorzugt hast.
- **Gewichts- und Bonus-Vorschläge**: DPS-Daten und manuelle Picks fließen beide in Gewichts-Vorschläge pro Echo ein, sowie (experimentell) in Quality-/Family-Bonus-Vorschläge.
- **Export (AI)**: ein vollständiger Klartext-Dump der Build-Einstellungen, aller für deine Klasse verfügbaren Echoes mit echten Effektbeschreibungen, plus aller Tuning-Daten — gedacht zum Einfügen in einen KI-Chat zur Analyse.
- **Tome Atlas**: community-basierte Drop-Locations für Echo-Tomes.
- **Public Builds**: Builds anderer Spieler durchsuchen und importieren.

Ausführliche Erklärungen zu jedem Feature und die vollständige Versionshistorie stehen in [`FAQ.md`](FAQ.md).

## Installation

Das Wurzelverzeichnis dieses Repos *ist* der Addon-Ordner (`EbonBuilds.toc`, `core/`, `modules/` liegen direkt oben, nicht in einem Unterordner).

**Über Git:**
```
cd "World of Warcraft/Interface/AddOns"
git clone <this-repo-url> EbonBuilds
```

**Über ZIP-Download:** GitHubs "Download ZIP" benennt den entpackten Ordner nach dem Branch (z.B. `EbonBuilds-main`) — vor dem Verschieben nach `Interface/AddOns/` exakt in `EbonBuilds` umbenennen, damit der Ordnername zur `EbonBuilds.toc` passt.

Danach Spiel neu starten oder `/reload`.

## Befehle

Jeder Befehl beginnt mit `/ebb`. Eine vollständige Referenz gibt's auch im Spiel über `/ebb showcase`.

| Befehl | Beschreibung |
|---|---|
| `/ebb` | Hauptfenster öffnen/schließen |
| `/ebb faq` (oder `/ebb help`) | Vollständiger In-Game-Guide |
| `/ebb showcase` (oder `/ebb commands`) | Diese Befehlsliste, im Spiel |
| `/ebb tuning` (oder `/ebb advisor`) | Tuning Advisor: Schwellenwerte, Auto-Tune, DPS-/Erscheinungswahrscheinlichkeits-Sharing |
| `/ebb cleartraining` | Manual-Training-Daten des aktiven Builds löschen |
| `/ebb atlas` (oder `/ebb tomes`) | Tome Atlas |
| `/ebb affix` | Affix-Referenz |
| `/ebb autosell` | Automatisches Verkaufen von 0-Kupfer-Items umschalten |
| `/ebb bagdots` | Farbige Punkte auf Taschen-Items ohne Affix umschalten |
| `/ebb debug` | Detailliertes Automation-Entscheidungs-Logging umschalten |
| `/ebb debuglog` (oder `/ebb log`) | Aufgezeichnetes Debug-Log ansehen |
| `/ebb errors` | Abgefangene Fehler ansehen, für Bug-Reports |
| `/ebb clicktrace` | Jeden UI-Button-Klick loggen, für "nichts passiert"-Reports |

## Bugs melden

`/ebb errors`-Output oder ein `/ebb debug`-Log an den Report anhängen — der schnellste Weg, dass etwas wirklich gefixt statt nur geraten wird.

## Entwicklung

- Reines Lua, WotLK-3.3.5a-API (Interface 30300).
- `luac5.1 -p` prüft vor jedem Release jede Datei auf Syntaxfehler; siehe `.github/workflows/lua-syntax.yml` für denselben Check in CI.
- Kein Build-Schritt — das Repo-Wurzelverzeichnis *ist* die Addon-Ordnerstruktur, die `Interface/AddOns/` erwartet.
