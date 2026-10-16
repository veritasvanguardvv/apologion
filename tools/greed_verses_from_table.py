#!/usr/bin/env python3
"""Turns the Greed verse table (Markdown, pasted from the design doc) into
res://data/greed_verses.json, which character_body_2d.gd loads at startup.

Usage (from the project folder):
    python3 tools/greed_verses_from_table.py tools/greed_table.md

Columns: Bible Index | Transl. | TEXT | TEXT PL | TEXT SP | Damage to All Sin | Greed | Heal | Jesus
 - Invisible Unicode direction marks are removed from the index
   ("Psalm\u202c \u202d39\u202c:..." -> "Psalm 39:6b"), and a trailing "alt"
   is dropped ("1 Corinthians 5:11alt" -> "1 Corinthians 5:11").
 - Blank Polish cells are filled from PL_FILL below (our own translations),
   blank Spanish cells from ES_FILL. Anything still blank is reported.
 - Percent cells: "100%" -> 100, "-10%" -> -10, blank -> 0.
"""
import json, re, sys, unicodedata, pathlib

# Our Polish translations for rows whose TEXT PL cell is blank in the table.
PL_FILL = {
    "Psalm 73:12": "Niegodziwi są zawsze beztroscy, pomnażają swoje bogactwa.",
    "Luke 12:29a": "Nie zabiegajcie o to, co będziecie jeść i pić.",
    "2 Corinthians 6:10b": "Żyjemy jako nic nie mający, a jednak wszystko posiadający.",
    "Isaiah 58:7b": "Wprowadź do swego domu biednych bez dachu nad głową.",
    "Habakkuk 2:5a": "Bogactwo jest zdrajcą, a człowiek pyszny nigdy nie zazna spokoju.",
    "Habakkuk 2:5b": "Jego chciwość jest szeroka jak Szeol; jak śmierć nigdy nie ma dość.",
    "Proverbs 27:20": "Jak Śmierć i Zagłada nigdy nie są syte, tak i pożądanie nigdy nie jest nasycone.",
}
ES_FILL = {
    "Isaiah 58:7b": "Trae a tu casa a los pobres sin hogar.",
}


def clean_ref(s):
    s = "".join(c for c in s if unicodedata.category(c) != "Cf")   # direction marks etc.
    s = re.sub(r"\s+", " ", s).strip()
    s = re.sub(r"\s*:\s*", ":", s)
    s = re.sub(r"alt$", "", s).strip()
    return s


def clean_text(s):
    s = "".join(c for c in s if unicodedata.category(c) != "Cf")
    s = re.sub(r"([?.!,;:])(?=[^\s\d\"'”»)\]])", r"\1 ", s)   # "niebie?Gdy" -> "niebie? Gdy"
    return re.sub(r"\s+", " ", s).strip()


def pct(s):
    s = s.strip().replace("%", "").replace("\u2212", "-")
    if s == "":
        return 0
    v = float(s)
    return int(v) if v == int(v) else v


def parse(md):
    rows = []
    for line in md.splitlines():
        line = line.strip()
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        if len(cells) < 9 or cells[0].lower().startswith("bible index") or set(cells[0]) <= set("-: "):
            continue
        rows.append(cells[:9])
    return rows


def main():
    src = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "tools/greed_table.md")
    out = pathlib.Path(sys.argv[2] if len(sys.argv) > 2 else "data/greed_verses.json")
    verses, seen, report = [], {}, {"pl_filled": [], "es_filled": [], "still_blank": [], "duplicates": []}
    for c in parse(src.read_text(encoding="utf-8")):
        ref = clean_ref(c[0])
        v = {
            "ref": ref,
            "translation": c[1],
            "en": clean_text(c[2]),
            "pl": clean_text(c[3]),
            "es": clean_text(c[4]),
            "all_damage": pct(c[5]),
            "greed_damage": pct(c[6]),
            "heal": pct(c[7]),
            "jesus": c[8].strip().lower() == "x",
        }
        if v["pl"] == "":
            if ref in PL_FILL:
                v["pl"] = PL_FILL[ref]; report["pl_filled"].append(ref)
            else:
                report["still_blank"].append(ref + " (pl)")
        if v["es"] == "":
            if ref in ES_FILL:
                v["es"] = ES_FILL[ref]; report["es_filled"].append(ref)
            else:
                report["still_blank"].append(ref + " (es)")
        if ref in seen:   # same index twice: keep both, the second gets a marker
            report["duplicates"].append(ref)
            seen[ref] += 1
            v["ref"] = "%s (%d)" % (ref, seen[ref])
        else:
            seen[ref] = 1
        verses.append(v)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps({"verses": verses}, ensure_ascii=False, indent=1), encoding="utf-8")
    print("Wrote %d verses to %s" % (len(verses), out))
    for k, v in report.items():
        if v:
            print(k + ":", ", ".join(v))


if __name__ == "__main__":
    main()
