#!/usr/bin/env python3
"""Turns the verse design sheet (Google Sheets, "Player" and "Enemy" tabs) into
the game's data files:

    data/verses.json       every player verse that attacks a sin and/or heals
    data/enemy_lines.json  every enemy line, grouped by who says it

Usage (from the project folder):
    python3 tools/verses_from_sheet.py                 # downloads the sheet (xlsx export)
    python3 tools/verses_from_sheet.py sheet.xlsx      # or reads a saved export

Player tab columns: Bible Index | Transl. | TEXT | TEXT PL | TEXT SP |
  Damage to All Sin | Sloth | Light | Gluttony | Lust | Wrath | Greed | Envy |
  Pride | Dmg to Atheists | Dmg to False Teachers | Dmg to Demons |
  Dmg to SinDeath boss | Dmg to Idol | Heal | Jesus | ...
  Percent cells are fractions (0.5 = 50%) and become whole percents (50).
  A row is imported if it does damage to "All Sin" or one of the seven sins, or heals.
Enemy tab columns: ENEMY SPELL ID | Enemy | Bible Index | Transl. | TEXT |
  Damage | Heal | Jesus? | Doubt | Fear | Confusion | Exhaust | Duration | Countered By
  A blank Enemy cell continues the group above it.

Blank or clearly wrong English / Spanish / Polish cells are filled from
tools/sheet_fills.json (our own brief translations; see that file).
Anything still blank is reported.
"""
import json, re, sys, unicodedata, pathlib, urllib.request, io

SHEET_ID = "19NANAw7uFNsRW6ggJAmOjNMaL7mGQXm9jq0S_hSezRQ"
SINS = {"sloth": 7, "gluttony": 9, "lust": 10, "wrath": 11, "greed": 12, "envy": 13, "pride": 14}
EXTRA = {"atheist": 15, "false_teacher": 16, "demon": 17, "sindeath": 18, "idol": 19}
COL_REF, COL_TR, COL_EN, COL_PL, COL_ES, COL_ALL, COL_HEAL, COL_JESUS = 1, 2, 3, 4, 5, 6, 20, 21

# Enemy tab group names -> line set ids (enemy.gd "line_sets")
GROUPS = {
    "sloth type": "sloth", "sloth": "sloth", "greed-type": "greed", "gluttony": "gluttony",
    "lust": "lust", "wrath": "wrath", "envy": "envy", "pride": "pride",
    "silver wolf": "silver_wolf", "bronze wolf": "bronze_wolf", "atheist goat": "atheist_goat",
    "general": "general", "umbrid": "umbrid", "penumbrid (mid demon)": "penumbrid",
    "antumbrid": "antumbrid", "sindeath": "sindeath", "law-dozer": "law_dozer",
}
# The sin an enemy becomes after saying a line of this set ("" = no change)
GROUP_TYPE = {"sloth": "sloth", "greed": "greed", "gluttony": "gluttony", "lust": "lust",
              "wrath": "wrath", "envy": "envy", "pride": "pride",
              "silver_wolf": "greed", "bronze_wolf": "greed"}


def clean(s):
    if s is None:
        return ""
    s = str(s)
    s = "".join(c for c in s if unicodedata.category(c) != "Cf")   # direction marks etc.
    s = re.sub(r"([?.!,;:])(?=[^\s\d\"'”’»)\]….!?])", r"\1 ", s)
    return re.sub(r"\s+", " ", s).strip()


def clean_ref(s):
    s = clean(s)
    s = re.sub(r"\s*:\s*", ":", s)
    s = re.sub(r"alt$", "", s).strip()
    s = s.replace("–", "-")
    return s


def pct(v):
    if v is None or str(v).strip() == "":
        return 0
    s = str(v).strip().replace("%", "").replace("\u2212", "-")
    try:
        f = float(s)
    except ValueError:
        return 0
    if "%" not in str(v):
        f *= 100
    f = round(f, 1)
    return int(f) if f == int(f) else f


def group_name(cell):
    s = clean(cell)
    m = re.findall(r'"([^"]+)"\)?$', s)     # =IFERROR(__xludf.DUMMYFUNCTION("AI(""Greed-type"")"),"Greed-type")
    if s.startswith("="):
        m = re.findall(r'"([^"()]+)"', s)
        s = m[-1] if m else s
    return GROUPS.get(s.lower(), re.sub(r"\W+", "_", s.lower()).strip("_"))


def looks_like_ref(s):
    return bool(re.search(r"\d", s)) or s in ("Genesis 3", "John 2")


def load_workbook(arg):
    import openpyxl
    if arg:
        return openpyxl.load_workbook(arg, read_only=True, data_only=True)
    url = "https://docs.google.com/spreadsheets/d/%s/export?format=xlsx" % SHEET_ID
    data = urllib.request.urlopen(url, timeout=60).read()
    return openpyxl.load_workbook(io.BytesIO(data), read_only=True, data_only=True)


def main():
    root = pathlib.Path(__file__).resolve().parent.parent
    wb = load_workbook(sys.argv[1] if len(sys.argv) > 1 else None)
    fills = json.loads((root / "tools/sheet_fills.json").read_text(encoding="utf-8"))
    pfill, efill = fills.get("player", {}), fills.get("enemy", {})
    report = {"filled": [], "blank": [], "duplicates": []}

    # ---------- Player ----------
    verses, seen = [], {}
    for r in list(wb["Player"].iter_rows(values_only=True))[1:]:
        r = list(r) + [None] * 40
        ref = clean_ref(r[COL_REF])
        if not ref:
            continue
        sins = {k: pct(r[c]) for k, c in SINS.items() if pct(r[c]) > 0}
        all_d, heal = pct(r[COL_ALL]), pct(r[COL_HEAL])
        if not sins and all_d <= 0 and heal == 0:
            continue
        en, es, pl = clean(r[COL_EN]), clean(r[COL_ES]), clean(r[COL_PL])
        # The same verse listed again (e.g. under another sin) with the same
        # text: merge it into the first row (highest value of each column wins)
        first = next((x for x in verses if x["ref"] == ref and (not en or not x["en"] or x["en"] == en)), None)
        if first:
            for k, d in sins.items():
                first["sins"][k] = max(first["sins"].get(k, 0), d)
            first["all_damage"] = max(first["all_damage"], all_d)
            if abs(heal) > abs(first["heal"]):
                first["heal"] = heal
            first["jesus"] = first["jesus"] or clean(r[COL_JESUS]).lower() == "x"
            for lang, t in (("en", en), ("es", es), ("pl", pl)):
                if not first[lang] and t:
                    first[lang] = t
            report["merged"] = report.get("merged", []) + [ref]
            continue
        key = ref
        if ref in seen:
            seen[ref] += 1
            key = "%s (%d)" % (ref, seen[ref])
            report["duplicates"].append(key)
        else:
            seen[ref] = 1
        v = {"ref": key, "translation": clean(r[COL_TR]),
             "en": en, "es": es, "pl": pl,
             "all_damage": all_d, "sins": sins, "heal": heal,
             "jesus": clean(r[COL_JESUS]).lower() == "x"}
        extra = {k: pct(r[c]) for k, c in EXTRA.items() if pct(r[c]) > 0}
        if extra:
            v["vs"] = extra
        verses.append(v)
    for v in verses:
        for lang in ("en", "es", "pl"):
            f = pfill.get(v["ref"], {}).get(lang)
            if f:
                v[lang] = f
                report["filled"].append("%s (%s)" % (v["ref"], lang))
            elif not v[lang]:
                report["blank"].append("player %s (%s)" % (v["ref"], lang))

    # ---------- Enemy ----------
    lines, group, n = [], "", {}
    for r in list(wb["Enemy"].iter_rows(values_only=True))[1:]:
        r = list(r) + [None] * 20
        if r[1]:
            group = group_name(r[1])
        idx, en = clean(r[2]), clean(r[4])
        if not en and not idx:
            continue
        fkey = en if en else "%s|%s" % (group, clean_ref(idx) if looks_like_ref(idx) else idx)
        f = efill.get(fkey, {})
        n[group] = n.get(group, 0) + 1
        line = {"id": clean(r[0]) or "%s_%d" % (group, n[group]), "set": group,
                "title": clean_ref(idx) if looks_like_ref(idx) else "",
                "kind": "" if looks_like_ref(idx) else idx,
                "type": GROUP_TYPE.get(group, ""),
                "en": f.get("en", en), "es": f.get("es", ""), "pl": f.get("pl", ""),
                "damage_pct": pct(r[5]), "heal_pct": pct(r[6]),
                "jesus": clean(r[7]).lower() == "x",
                "counters": [clean_ref(x) for x in re.split(r",\s*", clean(r[13])) if x.strip()]}
        for lang in ("en", "es", "pl"):
            if f.get(lang) and (lang != "en" or not en):
                report["filled"].append("enemy %s (%s)" % (fkey[:50], lang))
            if not line[lang]:
                report["blank"].append("enemy %s (%s)" % (fkey[:60], lang))
        lines.append(line)

    (root / "data").mkdir(exist_ok=True)
    (root / "data/verses.json").write_text(json.dumps({"verses": verses}, ensure_ascii=False, indent=1), encoding="utf-8")
    (root / "data/enemy_lines.json").write_text(json.dumps({"lines": lines}, ensure_ascii=False, indent=1), encoding="utf-8")
    print("Wrote %d player verses, %d enemy lines" % (len(verses), len(lines)))
    for s in SINS:
        print("  %-9s %d" % (s, sum(1 for v in verses if s in v["sins"])))
    print("  all-sin   %d\n  heal      %d" % (sum(1 for v in verses if v["all_damage"] > 0), sum(1 for v in verses if v["heal"] != 0)))
    sets = {}
    for l in lines:
        sets[l["set"]] = sets.get(l["set"], 0) + 1
    print("  enemy line sets:", sets)
    print("filled %d cells, %d still blank; merged repeated rows: %s; kept apart (different text): %s" % (len(report["filled"]), len(report["blank"]), ", ".join(report.get("merged", [])), ", ".join(report["duplicates"])))
    if "-v" in sys.argv:
        print("\n".join(report["blank"]))


if __name__ == "__main__":
    main()
