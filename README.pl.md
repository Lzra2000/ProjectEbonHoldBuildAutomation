# EbonBuilds

[English](README.md) | [Deutsch](README.de.md) | [Русский](README.ru.md) | [Português (Brasil)](README.pt-BR.md) | [Español](README.es.md) | [Français](README.fr.md) | **[Polski](README.pl.md)**

Addon do World of Warcraft (3.3.5a) dla **ProjectEbonhold**, który automatyzuje wybory echa (Banish / Reroll / Freeze / Select) na podstawie zdefiniowanego przez ciebie builda i z czasem sam się dostraja na podstawie prawdziwych danych z gry.

Wymaga **ProjectEbonhold** lub **ProjectEbonhold Enhanced**. Niektóre funkcje dodatkowo korzystają z **[Details!](https://www.curseforge.com/wow/addons/details)**, jeśli jest zainstalowany.

## Co robi

- **Definiowanie builda**: wagi dla każdego echa, bonusy jakości/rodziny/nowości, zablokowane sloty, zbanowane echa.
- **Automatyzacja**: ocenia każdy ekran wyboru echa względem twojego builda i działa (banish/reroll/freeze/select) za ciebie.
- **Tuning Advisor**: porównuje twoje progi Banish/Reroll/Freeze z tym, co twój build faktycznie dostaje w ofercie (nie z modelem teoretycznym), sugeruje lepsze wartości i może je stopniowo dostrajać automatycznie z czasem.
- **Rozkładanie budżetu na cały run**: progi automatycznie stają się bardziej rygorystyczne, gdy ładunki Banish/Reroll/Freeze się kończą, żebyś nie wydał ostatnich ładunków na wątpliwe oferty.
- **Śledzenie DPS i częstotliwości pojawiania się**: przy zainstalowanym Details! śledzi prawdziwy DPS dla każdego aktywnego echa; zawsze śledzi, jak często dane echo faktycznie pojawia się na ekranie wyboru. Oba te dane można opcjonalnie synchronizować z innymi graczami tej samej klasy.
- **Manual Training Mode**: zawieś automatyzację dla builda, wybieraj ręcznie, a EbonBuilds uczy się na podstawie twoich wyborów, generując sugestie wag na podstawie tego, co faktycznie preferowałeś.
- **Sugestie wag i bonusów**: dane DPS i ręczne wybory razem zasilają sugestie wag dla poszczególnych ech, a także (eksperymentalnie) sugestie bonusów jakości/rodziny.
- **Export (AI)**: pełny zrzut tekstowy ustawień builda, wszystkich ech dostępnych dla twojej klasy z prawdziwymi opisami efektów oraz wszystkich danych dostrajania — pomyślany do wklejenia w czacie z AI do analizy.
- **Tome Atlas**: lokalizacje dropów tomów echa, zebrane przez społeczność.
- **Public Builds**: przeglądaj i importuj buildy udostępnione przez innych graczy.

Szczegółowe wyjaśnienia każdej funkcji i pełną historię wersji znajdziesz w [`FAQ.md`](FAQ.md).

## Instalacja

Katalog główny tego repozytorium *jest* folderem addonu (`EbonBuilds.toc`, `core/`, `modules/` znajdują się na najwyższym poziomie, nie w podfolderze).

**Przez Git:**
```
cd "World of Warcraft/Interface/AddOns"
git clone <this-repo-url> EbonBuilds
```

**Przez pobranie ZIP:** przycisk „Download ZIP” na GitHubie nazywa wypakowany folder zgodnie z nazwą gałęzi (np. `EbonBuilds-main`) — przed umieszczeniem go w `Interface/AddOns/` zmień nazwę dokładnie na `EbonBuilds`, żeby nazwa folderu pasowała do `EbonBuilds.toc`.

Następnie zrestartuj grę lub wykonaj `/reload`.

## Komendy

Każda komenda zaczyna się od `/ebb`. Pełne odniesienie jest też dostępne w grze przez `/ebb showcase`.

| Komenda | Opis |
|---|---|
| `/ebb` | Otwórz lub zamknij główne okno |
| `/ebb faq` (lub `/ebb help`) | Pełny przewodnik w grze |
| `/ebb showcase` (lub `/ebb commands`) | Ta lista komend, w grze |
| `/ebb tuning` (lub `/ebb advisor`) | Tuning Advisor: progi, auto-tune, udostępnianie DPS/częstotliwości pojawiania się |
| `/ebb cleartraining` | Wyczyść dane Manual Training aktywnego builda |
| `/ebb atlas` (lub `/ebb tomes`) | Tome Atlas |
| `/ebb affix` | Baza afiksów |
| `/ebb autosell` | Przełącz automatyczną sprzedaż śmieci za 0 miedzi u handlarzy |
| `/ebb bagdots` | Przełącz kolorowe kropki na przedmiotach w plecaku bez afiksu |
| `/ebb debug` | Przełącz szczegółowe logowanie decyzji automatyzacji |
| `/ebb debuglog` (lub `/ebb log`) | Zobacz zarejestrowany log debugowania |
| `/ebb errors` | Zobacz przechwycone błędy, do zgłoszeń błędów |
| `/ebb clicktrace` | Loguj każde kliknięcie przycisku interfejsu, do zgłoszeń „nic się nie stało” |

## Zgłaszanie błędów

Dołącz do zgłoszenia wynik `/ebb errors` lub log `/ebb debug` — to najszybszy sposób, żeby coś naprawdę naprawić, zamiast zgadywać.

## Rozwój

- Czysty Lua, API WotLK 3.3.5a (Interface 30300).
- `luac5.1 -p` sprawdza składnię każdego pliku przed każdym wydaniem; zobacz `.github/workflows/lua-syntax.yml` dla tej samej kontroli działającej w CI.
- Brak etapu budowania — katalog główny repozytorium *jest* strukturą folderu addonu oczekiwaną przez `Interface/AddOns/`.
