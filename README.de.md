<p align="center">
  <img src="assets/banner.svg" alt="EbonBuilds" width="100%">
</p>

<p align="center">
  <a href="https://github.com/Lzra2000/-ProjectEbonHoldBuildAutomation/actions/workflows/lua-syntax.yml"><img src="https://github.com/Lzra2000/-ProjectEbonHoldBuildAutomation/actions/workflows/lua-syntax.yml/badge.svg" alt="Checks"></a>
  <a href="https://github.com/Lzra2000/-ProjectEbonHoldBuildAutomation/releases/latest"><img src="https://img.shields.io/github/v/release/Lzra2000/-ProjectEbonHoldBuildAutomation?label=release&color=2a6e5a" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/WoW-3.3.5a%20(12340)-4a7ab5" alt="WoW 3.3.5a">
  <img src="https://img.shields.io/badge/Lua-5.1-8a5fc9" alt="Lua 5.1">
</p>

<p align="center">
  <a href="README.md">English</a> | <b>Deutsch</b> | <a href="README.ru.md">Русский</a> | <a href="README.pt-BR.md">Português (Brasil)</a> | <a href="README.es.md">Español</a> | <a href="README.fr.md">Français</a> | <a href="README.pl.md">Polski</a>
</p>

Ein World-of-Warcraft-Addon (3.3.5a) für **ProjectEbonhold**, das Echo-Auswahlen (Banish / Reroll / Freeze / Select) anhand eines von dir definierten Builds automatisiert und sich über die Zeit anhand echter Spieldaten selbst nachjustiert.

Benötigt **ProjectEbonhold** oder **ProjectEbonhold Enhanced**. Manche Funktionen nutzen zusätzlich **[Details!](https://www.curseforge.com/wow/addons/details)**, falls installiert.


<p align="center">
  <img src="assets/how-it-works.svg" alt="How it works" width="100%">
</p>

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

Nur `/ebb` (oder `/ebonbuilds`) — öffnet oder schließt das Hauptfenster. Alles, was früher ein eigener Slash-Befehl war, findet sich jetzt hinter dem Zahnrad-Symbol (Einstellungen) in der Kopfzeile des Fensters, alles an einem Ort statt auswendig zu lernender Unterbefehle: Sprache, Auto-Verkauf, Taschen-Affix-Punkte, Debug-Logging, Click Trace, die Debug-/Fehler-/Click-Trace-Logs, Tuning Advisor, Tome Atlas, Affix-Referenz, die Befehlsübersicht sowie EWL-Export und Manual-Training-Reset des aktiven Builds.

## Bugs melden

Häng die Ausgabe des Fehler-Logs oder Debug-Logs (Einstellungen — Zahnrad-Symbol im Hauptfenster — Windows & Tools) an deinen Report an — das ist der mit Abstand schnellste Weg, dass etwas gefixt statt geraten wird.

## Entwicklung

- Reines Lua, WotLK-3.3.5a-API (Interface 30300).
- `luac5.1 -p` prüft vor jedem Release jede Datei auf Syntaxfehler; siehe `.github/workflows/lua-syntax.yml` für denselben Check in CI.
- Kein Build-Schritt — das Repo-Wurzelverzeichnis *ist* die Addon-Ordnerstruktur, die `Interface/AddOns/` erwartet.
