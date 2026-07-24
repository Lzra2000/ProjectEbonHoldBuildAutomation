local addonName, EbonBuilds = ...

-- EbonBuilds: modules/i18n/locales/deDE.lua
-- German translation. Game/addon terms (Echo, Build, Autopilot, and the
-- automation actions Banish/Reroll/Freeze/Select) are kept in English,
-- matching the existing README.de.md convention.

EbonBuilds.Locale.Register("deDE", {
    -- Build editor tabs
    ["Build"] = "Build",
    ["Priorities"] = "Prioritäten",
    ["Modifiers"] = "Modifikatoren",
    ["Autopilot"] = "Autopilot",
    ["Identity, class, locked Echoes, and sharing."] = "Identität, Klasse, gesperrte Echoes und Teilen.",
    ["Set rank-specific Echo values and protect must-keep Echoes."] = "Rang-spezifische Echo-Werte festlegen und unverzichtbare Echoes schützen.",
    ["Adjust rank, family, and unique-Echo strategy."] = "Rang-, Familien- und Unique-Echo-Strategie anpassen.",
    ["Choose an automation intent and tune its decisions."] = "Eine Automatisierungs-Ausrichtung wählen und ihre Entscheidungen feinjustieren.",

    -- Build editor bottom bar
    ["Save build"] = "Build speichern",
    ["Validate active fields and save build details, Echo values, bonuses, and visibility."] =
        "Aktive Felder validieren und Build-Details, Echo-Werte, Boni und Sichtbarkeit speichern.",
    ["Cancel"] = "Abbrechen",
    ["Cancel editing"] = "Bearbeitung abbrechen",
    ["Discard all unsaved build details, Echo values, modifiers, protection rules, and Autopilot tuning."] =
        "Alle ungespeicherten Build-Details, Echo-Werte, Modifikatoren, Schutzregeln und Autopilot-Einstellungen verwerfen.",
    ["Export"] = "Export",
    ["Export build"] = "Build exportieren",
    ["Create a compact string that another EbonBuilds user can import."] =
        "Erstellt eine kompakte Zeichenfolge, die ein anderer EbonBuilds-Nutzer importieren kann.",
    ["AI report"] = "KI-Bericht",
    ["AI tuning report"] = "KI-Tuning-Bericht",
    ["Create a readable report of weights, bonuses, thresholds, and tuning data for analysis. It cannot be imported back."] =
        "Erstellt einen lesbaren Bericht über Gewichte, Boni, Schwellenwerte und Tuning-Daten zur Analyse. Kann nicht wieder importiert werden.",
    ["Unsaved changes"] = "Ungespeicherte Änderungen",
    ["All changes saved"] = "Alle Änderungen gespeichert",
    [" · Autopilot uses last saved settings"] = " · Autopilot nutzt zuletzt gespeicherte Einstellungen",

    -- /ebb locale command
    ["Character"] = "Charakter",
    ["Live gear, full talent trees, and glyphs; adopt them into the build."] = "Aktuelle Ausrüstung, vollständige Talentbäume und Glyphen; per Klick in den Build übernehmen.",

    -- Auto-sell settings
    ["AUTO-SELL (VENDOR ONLY)"] = "AUTO-VERKAUF (NUR HÄNDLER)",
    ["Auto-sell junk at vendors"] = "Müll beim Händler auto-verkaufen",
    ["Sells eligible zero-copper items while a vendor is open. Does not list on the Auction House; use Auctionator for AH selling."] =
        "Verkauft berechtigte 0-Kupfer-Gegenstände bei geöffnetem Händler. Kein Auktionshaus — für AH-Verkäufe Auctionator nutzen.",
    ["Vendor-only: items are sold to the merchant NPC, never posted to the AH."] =
        "Nur Händler: Gegenstände werden an den NPC verkauft, nie ins AH gestellt.",
    ["Only sell Poor (gray) quality"] = "Nur Schlecht (grau) verkaufen",
    ["Restricts the zero-copper sweep to Poor-quality items only, instead of any quality."] =
        "Beschränkt den 0-Kupfer-Sweep auf graue Gegenstände.",
    ["Sell Common (white) zero-copper items"] = "Gewöhnlich (weiß) 0-Kupfer verkaufen",
    ["When gray-only is off, allows white-quality vendor trash. Ignored while gray-only is on."] =
        "Erlaubt weißen Müll, wenn Grau-only aus ist. Ignoriert bei Grau-only.",
    ["Sell Uncommon (green) zero-copper items"] = "Ungewöhnlich (grün) 0-Kupfer verkaufen",
    ["Allows green vendor trash with no sell value. Ignored while gray-only is on."] =
        "Erlaubt grünen Müll ohne Verkaufswert. Ignoriert bei Grau-only.",
    ["Never sell Rare or Epic quality"] = "Selten/Episch nie verkaufen",
    ["Blocks Rare and Epic items even when they show zero copper at a vendor."] =
        "Blockiert seltene/epische Gegenstände auch bei 0 Kupfer beim Händler.",
    ["Never auto-sell Trade Goods"] = "Handwerkswaren nie auto-verkaufen",
    ["Materials sometimes show as zero-copper but are still worth keeping (e.g. for professions)."] =
        "Materialien können 0 Kupfer zeigen, sind aber oft behaltenswert (Berufe).",
    ["Never auto-sell Recipes"] = "Rezepte nie auto-verkaufen",
    ["Recipes/patterns can be zero-copper at a vendor but still worth learning or trading."] =
        "Rezepte können 0 Kupfer zeigen, sind aber oft lern-/handelbar.",
    ["Never sell soulbound items"] = "Seelengebundene Gegenstände nie verkaufen",
    ["Uses tooltip bind text (ITEM_SOULBOUND) to skip bound gear and materials."] =
        "Nutzt Tooltip-Bind-Text (ITEM_SOULBOUND) zum Überspringen gebundener Items.",
    ["Never sell unbound BoE items"] = "Ungebundene BoE-Gegenstände nie verkaufen",
    ["Uses tooltip bind text (ITEM_BIND_ON_EQUIP) to keep tradeable gear."] =
        "Nutzt Tooltip-Bind-Text (ITEM_BIND_ON_EQUIP) für handelbare Ausrüstung.",
    ["Never sell soulbound Epic items"] = "Seelengebundene epische Gegenstände nie verkaufen",
    ["Extra safety for purple soulbound gear even if other quality filters change."] =
        "Zusätzlicher Schutz für lila seelengebundene Items.",
    ["Dry-run preview (count only)"] = "Trockenlauf-Vorschau (nur zählen)",
    ["On vendor open, shows how many items would sell without actually selling them."] =
        "Zeigt beim Händler, wie viele Items verkauft würden, ohne zu verkaufen.",
    ["Max item level to sell"] = "Max. Gegenstandsstufe zum Verkauf",
    ["0 = no limit. Only sells zero-copper items at or below this item level."] =
        "0 = kein Limit. Nur 0-Kupfer-Items bis zu dieser Stufe.",
    ["Minimum stack size to sell"] = "Mindest-Stackgröße zum Verkauf",
    ["Only sells stacks with at least this many items (useful for partial herb/ore stacks)."] =
        "Verkauft nur Stacks mit mindestens so vielen Items (Kräuter/Erz).",
    ["Manage Auto-Sell Keep List..."] = "Auto-Verkauf Behalte-Liste...",
    ["CONVENIENCE & DIAGNOSTICS"] = "KOMFORT & DIAGNOSE",
    ["Off"] = "Aus",
    ["Auto-Sell Keep List"] = "Auto-Verkauf Behalte-Liste",
    ["Items here are never auto-sold, even if they'd otherwise be eligible. Use exact names, #itemIDs, or * patterns."] =
        "Diese Gegenstände werden nie auto-verkauft. Exakte Namen, #itemIDs oder *-Muster.",
    ["Name, #12345, or *pattern*..."] = "Name, #12345 oder *Muster*...",
    ["No items on the keep-list yet."] = "Noch keine Einträge auf der Behalte-Liste.",
    ["Add"] = "Hinzufügen",
    ["Auto-sell preview: %d eligible item(s) (vendor only, nothing sold)."] =
        "Auto-Verkauf Vorschau: %d berechtigte Item(s) (nur Händler, nichts verkauft).",
})
