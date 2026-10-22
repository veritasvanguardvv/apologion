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
  ... | Faith UP | Enemy Faith Debuff | Guard UP | Enemy Guard Debuff | Wisdom UP | ...
  Columns are found by their header text. Wisdom UP becomes "wisdom" (whole %).
  A row is imported if it does damage to "All Sin" or one of the seven sins,
  heals, or (with a text) gives Wisdom.
Enemy tab columns: ENEMY SPELL ID | Enemy | Bible Index | Transl. | TEXT |
  Damage | Heal | Jesus? | Doubt | Fear | Confusion | Exhaust | Duration | Countered By
  A blank Enemy cell continues the group above it.

Blank or clearly wrong English / Spanish / Polish cells are filled from
tools/sheet_fills.json (our own brief translations; see that file).
Its "extra" list adds verses the sheet lacks (e.g. 2 Corinthians 1:20, used by
the SinDeath boss counter) and extra matching wordings ("alt").
Its "zeal" and "guard" lists mark the Zeal verses ("zeal": true; speed +
jump boost in the game) and Guard verses ("guard": true; +defense for a few
rounds) and add the ones the sheet doesn't have.
  python3 tools/verses_from_sheet.py --lists-only  # re-applies just those lists to data/verses.json
Anything still blank is reported.
"""
import json, re, sys, unicodedata, pathlib, urllib.request, io

SHEET_ID = "19NANAw7uFNsRW6ggJAmOjNMaL7mGQXm9jq0S_hSezRQ"
SINS = {"sloth": 7, "gluttony": 9, "lust": 10, "wrath": 11, "greed": 12, "envy": 13, "pride": 14}
EXTRA = {"atheist": 15, "false_teacher": 16, "demon": 17, "sindeath": 18, "idol": 19}
COL_REF, COL_TR, COL_EN, COL_PL, COL_ES, COL_ALL, COL_HEAL, COL_JESUS = 1, 2, 3, 4, 5, 6, 20, 21
COL_WISDOM = 26
# The Player tab's columns are found by their header text (so an inserted
# column doesn't shift everything); the numbers above are only the fallback.
PLAYER_HEADERS = {
    "ref": "bible index", "tr": "transl.", "en": "text", "pl": "text pl", "es": "text sp",
    "all": "damage to all sin", "heal": "heal", "jesus": "jesus", "wisdom": "wisdom up",
    "sloth": "sloth", "gluttony": "gluttony", "lust": "lust", "wrath": "wrath",
    "greed": "greed", "envy": "envy", "pride": "pride",
    "atheist": "dmg to atheists", "false_teacher": "dmg to false teachers",
    "demon": "dmg to demons", "sindeath": "dmg to sindeath", "idol": "dmg to idol",
}


def player_columns(header):
    """Column numbers of the Player tab from its header row (see PLAYER_HEADERS)."""
    global COL_REF, COL_TR, COL_EN, COL_PL, COL_ES, COL_ALL, COL_HEAL, COL_JESUS, COL_WISDOM
    names = [clean(h).lower() for h in header]
    def find(want):
        for i, n in enumerate(names):
            if n == want or (want.startswith("dmg to") and n.startswith(want)):
                return i
        return None
    found = {k: find(w) for k, w in PLAYER_HEADERS.items()}
    missing = [PLAYER_HEADERS[k] for k, i in found.items() if i is None]
    if missing:
        print("Player tab: headers not found, using the default columns for:", ", ".join(missing))
    g = lambda k, d: found[k] if found[k] is not None else d
    COL_REF, COL_TR, COL_EN, COL_PL, COL_ES = g("ref", COL_REF), g("tr", COL_TR), g("en", COL_EN), g("pl", COL_PL), g("es", COL_ES)
    COL_ALL, COL_HEAL, COL_JESUS, COL_WISDOM = g("all", COL_ALL), g("heal", COL_HEAL), g("jesus", COL_JESUS), g("wisdom", COL_WISDOM)
    for k in SINS:
        SINS[k] = g(k, SINS[k])
    for k in EXTRA:
        EXTRA[k] = g(k, EXTRA[k])

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


def _norm(t):
    return re.sub(r"[^a-z0-9]+", " ", (t or "").lower().replace("’", "'")).strip()


def apply_list(verses, entries, flag, report=None):
    """Marks the verses of a list (sheet_fills.json "zeal" / "guard") with
    v[flag] = True and adds the ones the sheet lacks. Safe to run twice."""
    for e in entries:
        refs = {e["ref"], e.get("sheet_ref", e["ref"])}
        cands = [v for v in verses if re.sub(r" \(\d+\)$", "", v["ref"]) in refs]
        v = None
        if cands:
            v = next((c for c in cands if e.get("en") and _norm(c["en"]) == _norm(e["en"])), None) \
                or next((c for c in cands if c.get("zeal")), None) or cands[0]
        if v is None:
            v = {"ref": e["ref"], "translation": "", "en": "", "es": "", "pl": "",
                 "all_damage": 0, "sins": {}, "heal": 0, "jesus": False}
            verses.append(v)
            if report is not None:
                report.setdefault(flag + "_new", []).append(e["ref"])
        if e.get("sheet_ref") and re.sub(r" \(\d+\)$", "", v["ref"]) == e["sheet_ref"]:
            v["ref"] = e["ref"]                 # relabel a wrong sheet reference
        v[flag] = True
        for k in ("translation", "en", "es", "pl"):
            if e.get(k):
                v[k] = e[k]
    return verses


def apply_extra(verses, entries, report=None):
    """sheet_fills.json "extra": verses the game needs that the sheet doesn't
    have (or has without a text). A verse missing from the sheet is added;
    a sheet verse gets only its blank texts filled and the listed fields
    ("wisdom", "heal", "alt"...) that it doesn't already have. Safe to run twice."""
    for e in entries:
        v = next((x for x in verses if x["ref"] == e["ref"]), None)
        if v is None:
            v = {"ref": e["ref"], "translation": "", "en": "", "es": "", "pl": "",
                 "all_damage": 0, "sins": {}, "heal": 0, "jesus": False}
            verses.append(v)
            if report is not None:
                report.setdefault("extra_new", []).append(e["ref"])
        for k, val in e.items():
            if k in ("ref", "_note"):
                continue
            if k in ("translation", "en", "es", "pl"):
                if not v.get(k):
                    v[k] = val
            elif not v.get(k):
                v[k] = val
    return verses


def load_workbook(arg):
    import openpyxl
    if arg:
        return openpyxl.load_workbook(arg, read_only=True, data_only=True)
    url = "https://docs.google.com/spreadsheets/d/%s/export?format=xlsx" % SHEET_ID
    data = urllib.request.urlopen(url, timeout=60).read()
    return openpyxl.load_workbook(io.BytesIO(data), read_only=True, data_only=True)


def main():
    root = pathlib.Path(__file__).resolve().parent.parent
    if "--lists-only" in sys.argv or "--zeal-only" in sys.argv:
        fills = json.loads((root / "tools/sheet_fills.json").read_text(encoding="utf-8"))
        path = root / "data/verses.json"
        verses = json.loads(path.read_text(encoding="utf-8"))["verses"]
        report = {}
        # Start again from the sheet's own verses: drop the ones the lists added
        # (the sheet only gives verses that attack or heal) and the list flags,
        # so a verse taken out of a list (or renamed / split) doesn't linger.
        # (Wisdom verses too; the "extra" verses are added back below)
        verses = [v for v in verses if v.get("sins") or v.get("all_damage", 0) > 0 or v.get("heal", 0) != 0
                  or v.get("wisdom", 0) > 0]
        for v in verses:
            v.pop("zeal", None)
            v.pop("guard", None)
        for flag in ("zeal", "guard"):
            apply_list(verses, fills.get(flag, []), flag, report)
            print("%s verses: %d (new: %s)" % (flag, sum(1 for v in verses if v.get(flag)), ", ".join(report.get(flag + "_new", []))))
        apply_extra(verses, fills.get("extra", []), report)
        print("extra verses added: %s" % ", ".join(report.get("extra_new", [])))
        path.write_text(json.dumps({"verses": verses}, ensure_ascii=False, indent=1), encoding="utf-8")
        return
    wb = load_workbook(sys.argv[1] if len(sys.argv) > 1 else None)
    fills = json.loads((root / "tools/sheet_fills.json").read_text(encoding="utf-8"))
    pfill, efill = fills.get("player", {}), fills.get("enemy", {})
    report = {"filled": [], "blank": [], "duplicates": []}

    # ---------- Player ----------
    verses, seen = [], {}
    prows = list(wb["Player"].iter_rows(values_only=True))
    player_columns(prows[0])
    for r in prows[1:]:
        r = list(r) + [None] * 40
        ref = clean_ref(r[COL_REF])
        if not ref:
            continue
        sins = {k: pct(r[c]) for k, c in SINS.items() if pct(r[c]) > 0}
        all_d, heal, wis = pct(r[COL_ALL]), pct(r[COL_HEAL]), pct(r[COL_WISDOM])
        en, es, pl = clean(r[COL_EN]), clean(r[COL_ES]), clean(r[COL_PL])
        if not sins and all_d <= 0 and heal == 0:
            # A Wisdom-only verse (e.g. Proverbs 2:6) counts too, if it has a text
            if wis <= 0 or not (en or pfill.get(ref, {}).get("en")):
                continue
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
            if wis > first.get("wisdom", 0):
                first["wisdom"] = wis
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
        if wis > 0:
            v["wisdom"] = wis      # Wisdom UP (whole percent; the game caps the stat at 100)
        verses.append(v)
    for v in verses:
        for lang in ("en", "es", "pl"):
            f = pfill.get(v["ref"], {}).get(lang)
            if f:
                v[lang] = f
                report["filled"].append("%s (%s)" % (v["ref"], lang))
            elif not v[lang]:
                report["blank"].append("player %s (%s)" % (v["ref"], lang))

    for flag in ("zeal", "guard"):
        apply_list(verses, fills.get(flag, []), flag, report)
    apply_extra(verses, fills.get("extra", []), report)

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
    for flag in ("zeal", "guard"):
        print("  %-9s %d (new, not in the sheet: %s)" % (flag, sum(1 for v in verses if v.get(flag)), ", ".join(report.get(flag + "_new", []))))
    print("  %-9s %d (Wisdom UP; from the extra list, not in the sheet: %s)" % ("wisdom", sum(1 for v in verses if v.get("wisdom")), ", ".join(report.get("extra_new", []))))
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
