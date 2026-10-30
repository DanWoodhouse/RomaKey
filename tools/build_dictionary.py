"""Builds the keyboard's dictionary from JMdict (via the jamdict-data SQLite file).

Keeps the entries JMdict marks as common (news1, ichi1, spec1, spec2, gai1), ordered by
frequency, and writes one tab-separated line per entry:

    kanji  reading  usually-kana(0/1)  part-of-speech  senses

Senses are separated by " | ", glosses within a sense by "; ".
"""
import sqlite3
import sys
from collections import defaultdict

COMMON = {"news1", "ichi1", "spec1", "spec2", "gai1"}
MAX_SENSES = 3
MAX_GLOSSES = 4

# Matched against the start of JMdict's part-of-speech names, in this order.
POS = [
    ("noun or participle which takes the aux. verb suru", "noun, suru verb"),
    ("Ichidan verb", "verb"), ("Godan verb", "verb"), ("suru verb", "verb"), ("Kuru verb", "verb"),
    ("Nidan verb", "verb"), ("Yodan verb", "verb"), ("irregular", "verb"),
    ("adjective (keiyoushi)", "i-adjective"), ("adjectival nouns", "na-adjective"),
    ("adverb", "adverb"), ("pronoun", "pronoun"), ("interjection", "interjection"),
    ("conjunction", "conjunction"), ("particle", "particle"), ("counter", "counter"),
    ("numeric", "number"), ("expressions", "expression"), ("prefix", "prefix"),
    ("suffix", "suffix"), ("noun", "noun"),
]


def short_pos(names):
    for name in names:
        for prefix, label in POS:
            if name.startswith(prefix):
                return label
    return ""


def rank(tags):
    """Lower is more frequent. nfXX gives a 1-48 rank; other common tags rank after them."""
    best = 99
    for tag in tags:
        if tag.startswith("nf"):
            best = min(best, int(tag[2:]))
        elif tag in ("news1", "ichi1", "spec1", "gai1"):
            best = min(best, 49)
        elif tag in ("news2", "spec2"):
            best = min(best, 60)
    return best


def main(db_path, out_path):
    c = sqlite3.connect(db_path)
    tags = defaultdict(set)
    for idseq, tag in c.execute("SELECT k.idseq, p.text FROM Kanji k JOIN KJP p ON p.kid = k.ID"):
        tags[idseq].add(tag)
    for idseq, tag in c.execute("SELECT k.idseq, p.text FROM Kana k JOIN KNP p ON p.kid = k.ID"):
        tags[idseq].add(tag)
    common = [i for i, t in tags.items() if t & COMMON]

    kanji = defaultdict(list)
    for idseq, text in c.execute("SELECT idseq, text FROM Kanji ORDER BY ID"):
        kanji[idseq].append(text)
    kana = defaultdict(list)
    for idseq, text in c.execute("SELECT idseq, text FROM Kana ORDER BY ID"):
        kana[idseq].append(text)
    senses = defaultdict(list)
    for sid, idseq in c.execute("SELECT ID, idseq FROM Sense ORDER BY ID"):
        senses[idseq].append(sid)
    glosses = defaultdict(list)
    for sid, text in c.execute("SELECT sid, text FROM SenseGloss WHERE lang = 'eng' OR lang IS NULL"):
        glosses[sid].append(text)
    pos = defaultdict(list)
    for sid, text in c.execute("SELECT sid, text FROM pos"):
        pos[sid].append(text)
    misc = defaultdict(list)
    for sid, text in c.execute("SELECT sid, text FROM misc"):
        misc[sid].append(text)

    rows = []
    for idseq in common:
        if not kana[idseq]:
            continue
        sense_ids = [s for s in senses[idseq] if glosses[s]][:MAX_SENSES]
        if not sense_ids:
            continue
        first = sense_ids[0]
        usually_kana = any("usually written using kana" in m for m in misc[first])
        text = " | ".join("; ".join(glosses[s][:MAX_GLOSSES]) for s in sense_ids)
        fields = [
            kanji[idseq][0] if kanji[idseq] else "",
            kana[idseq][0],
            "1" if usually_kana or not kanji[idseq] else "0",
            short_pos(pos[first]),
            text,
        ]
        if any("\t" in f or "\n" in f for f in fields):
            continue
        rows.append((rank(tags[idseq]), idseq, "\t".join(fields)))

    rows.sort()
    with open(out_path, "w", encoding="utf-8") as f:
        for _, _, line in rows:
            f.write(line + "\n")
    print(f"{len(rows)} entries", file=sys.stderr)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
