#!/usr/bin/env python3
"""Add missing L[] keys to all six locale files via Google Translate."""
from __future__ import annotations

import json
import re
import subprocess
import time
from pathlib import Path

from deep_translator import GoogleTranslator

ROOT = Path(__file__).resolve().parents[1]
LANGS = {"deDE": "de", "esES": "es", "frFR": "fr", "plPL": "pl", "ptBR": "pt", "ruRU": "ru"}
KEEP_EN = [
    "EbonBuilds", "Echo", "Echoes", "Build", "Builds", "Autopilot",
    "Banish", "Reroll", "Freeze", "Select", "EWL", "Logbook", "Details!",
    "ProjectEbonhold", "Tome Atlas", "Manual Training", "Tuning Advisor",
    "Public Builds", "Logbook",
]


def lua_unescape(raw: str) -> str:
    out: list[str] = []
    i = 0
    while i < len(raw):
        if raw[i] == "\\" and i + 1 < len(raw):
            nxt = raw[i + 1]
            mapping = {"n": "\n", "t": "\t", '"': '"', "\\": "\\"}
            if nxt in mapping:
                out.append(mapping[nxt])
                i += 2
                continue
            if nxt.isdigit():
                j = i + 1
                while j < len(raw) and j < i + 4 and raw[j].isdigit():
                    j += 1
                out.append(chr(int(raw[i + 1 : j])))
                i = j
                continue
            out.append(nxt)
            i += 2
        else:
            out.append(raw[i])
            i += 1
    return "".join(out)


def lua_escape(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t")


def collect_used() -> set[str]:
    used: set[str] = set()
    listing = subprocess.check_output(
        ["git", "ls-files", "core/*.lua", "modules/*.lua", "modules/**/*.lua"],
        cwd=ROOT,
        text=True,
    )
    for line in listing.splitlines():
        line = line.replace("\\", "/")
        if line.startswith("modules/i18n/locales/"):
            continue
        src = (ROOT / line).read_text(encoding="utf-8")

        def record(key: str) -> None:
            used.add(lua_unescape(key))

        for key in re.findall(r'EbonBuilds\.L\["((?:[^"\\]|\\.)*)"\]', src):
            record(key)
        for alias in re.findall(r"local\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*EbonBuilds\.L\b", src):
            pat = re.escape(alias) + r'\["((?:[^"\\]|\\.)*)"\]'
            for key in re.findall(pat, src):
                record(key)
    return used


def load_locale(code: str) -> dict[str, str]:
    path = ROOT / "modules" / "i18n" / "locales" / f"{code}.lua"
    src = path.read_text(encoding="utf-8")
    out: dict[str, str] = {}
    pat = re.compile(
        r'\["((?:[^"\\]|\\[0-9]{1,3}|\\[nt"\\])*)"\]\s*=\s*"((?:[^"\\]|\\[0-9]{1,3}|\\[nt"\\])*)"'
    )
    for m in pat.finditer(src):
        out[lua_unescape(m.group(1))] = lua_unescape(m.group(2))
    return out


def protect(text: str) -> tuple[str, list[str]]:
    slots: list[str] = []

    def stash(m: re.Match) -> str:
        slots.append(m.group(0))
        return f"⟦{len(slots) - 1}⟧"

    text = re.sub(r"\|c[0-9a-fA-F]{6,8}", stash, text)
    text = re.sub(r"\|r", stash, text)
    text = re.sub(r"%[%-%+0-9\.]*[sdifoxX]", stash, text)
    for term in sorted(set(KEEP_EN), key=len, reverse=True):
        text = re.sub(re.escape(term), stash, text)
    return text, slots


def restore(text: str, slots: list[str]) -> str:
    def unstash(m: re.Match) -> str:
        idx = int(m.group(1))
        return slots[idx] if 0 <= idx < len(slots) else m.group(0)

    return re.sub(r"⟦(\d+)⟧", unstash, text)


def translate(text: str, target: str) -> str:
    if not re.search(r"[A-Za-z]", text):
        return text
    protected, slots = protect(text)
    for attempt in range(3):
        try:
            raw = GoogleTranslator(source="en", target=target).translate(protected)
            return restore(raw or protected, slots)
        except Exception:
            time.sleep(1.0 + attempt)
    return text


def patch_locale(code: str, target: str, used: set[str]) -> None:
    table = load_locale(code)
    missing = sorted(k for k in used if k not in table)
    if not missing:
        print(f"{code}: complete")
        return
    print(f"{code}: translating {len(missing)} missing keys")
    path = ROOT / "modules" / "i18n" / "locales" / f"{code}.lua"
    src = path.read_text(encoding="utf-8")
    additions = []
    for key in missing:
        val = translate(key, target)
        table[key] = val
        additions.append(f'    ["{lua_escape(key)}"] = "{lua_escape(val)}",')
    marker = "\n})\n"
    if marker not in src:
        raise SystemExit(f"{code}: could not find locale table closing marker")
    src = src.replace(marker, "\n" + "\n".join(additions) + marker, 1)
    path.write_text(src, encoding="utf-8", newline="\n")
    print(f"{code}: appended {len(missing)} entries ({len(table)} total)")


def main() -> None:
    used = collect_used()
    print(f"used keys: {len(used)}")
    for code, target in LANGS.items():
        patch_locale(code, target, used)


if __name__ == "__main__":
    main()
