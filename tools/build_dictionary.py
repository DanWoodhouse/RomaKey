"""Builds the keyboard's dictionary from JMdict (via the jamdict-data SQLite file).

Keeps the entries JMdict marks as common (news1, ichi1, spec1, spec2, gai1), ordered by
frequency, and writes one tab-separated line per entry:

    kanji  reading  usually-kana(0/1)  part-of-speech  senses  conjugation

Senses are separated by " | ", glosses within a sense by "; ". The conjugation class is how
the word inflects, for kanji conversion of forms like 食べた (see Conjugation.swift): v1
(ichidan), v5u … v5r (godan, by ending), v5k-s (行く), v5r-i (ある), v5aru (いらっしゃる), vk
(来る), vs (a noun that takes する), vs-i (ends in する), adj-i, adj-ix (いい/良い), or empty.
"""
import gzip
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


# JMdict part-of-speech names → conjugation class, most specific first.
CONJUGATION = [
    ("Ichidan verb - zuru", ""), ("Ichidan verb", "v1"),
    ("Godan verb - Iku/Yuku", "v5k-s"), ("Godan verb - -aru", "v5aru"),
    ("Godan verb with 'ru' ending (irregular", "v5r-i"),
    ("Godan verb with 'u' ending", "v5u"), ("Godan verb with 'ku' ending", "v5k"),
    ("Godan verb with 'gu' ending", "v5g"), ("Godan verb with 'su' ending", "v5s"),
    ("Godan verb with 'tsu' ending", "v5t"), ("Godan verb with 'nu' ending", "v5n"),
    ("Godan verb with 'bu' ending", "v5b"), ("Godan verb with 'mu' ending", "v5m"),
    ("Godan verb with 'ru' ending", "v5r"), ("Kuru verb", "vk"),
    ("suru verb - included", "vs-i"), ("suru verb - special", "vs-i"),
    ("adjective (keiyoushi) - yoi/ii", "adj-ix"), ("adjective (keiyoushi)", "adj-i"),
    ("noun or participle which takes the aux. verb suru", "vs"),
]


def conjugation(names):
    for prefix, code in CONJUGATION:
        if any(name.startswith(prefix) for name in names):
            return code
    return ""


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


# For verbs, how often the stems appear too: Japanese text is split into tokens like 行き|ます
# and 行っ|た, so the dictionary form alone undercounts them.
STEMS = {"v5u": "いっ", "v5k": "きい", "v5k-s": "きっ", "v5g": "ぎい", "v5s": "し", "v5t": "ちっ",
         "v5n": "にん", "v5b": "びん", "v5m": "みん", "v5r": "りっ", "v5r-i": "りっ", "v5aru": "いっ"}


def load_wordfreq(path):
    """wordfreq's cBpack: a header, then lists of words, each a centibel lower in frequency."""
    import msgpack
    with gzip.open(path, "rb") as f:
        data = msgpack.load(f, raw=False)
    freq = {}
    for index, words in enumerate(data[1:]):
        for word in words:
            freq.setdefault(word, 10 ** (-index / 100))
    return freq


def frequency(freq, kanji, reading, usually_kana, code):
    """How often the word is written in everyday text (wordfreq), as it's usually written."""
    forms = [reading] if usually_kana or not kanji else [kanji]
    base = forms[0]
    if code == "v1":
        forms.append(base[:-1])
    elif code in STEMS:
        forms += [base[:-1] + ending for ending in STEMS[code]]
    elif code == "adj-i":
        forms += [base[:-1] + "く", base[:-1] + "かっ"]
    return max(freq.get(form, 0) for form in forms)


def main(db_path, out_path, wordfreq_path=None):
    freq = load_wordfreq(wordfreq_path) if wordfreq_path else {}
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
            conjugation([p for s in senses[idseq] for p in pos[s]]),
        ]
        if any("\t" in f or "\n" in f for f in fields):
            continue
        # Most frequent in everyday text first (wordfreq); JMdict's rank breaks ties and orders
        # the words wordfreq doesn't know.
        common_use = frequency(freq, fields[0], fields[1], fields[2] == "1", fields[5])
        rows.append((-common_use, rank(tags[idseq]), idseq, "\t".join(fields)))

    rows.sort()
    with open(out_path, "w", encoding="utf-8") as f:
        for *_, line in rows:
            f.write(line + "\n")
    print(f"{len(rows)} entries", file=sys.stderr)


if __name__ == "__main__":
    # python3 tools/build_dictionary.py jamdict.db dictionary.tsv [wordfreq/data/large_ja.msgpack.gz]
    main(*sys.argv[1:4])
