"""Builds the keyboard's dictionary from JMdict (via the jamdict-data SQLite file).

Keeps the entries JMdict marks as common (news1, ichi1, spec1, spec2, gai1), plus the ones with
only a newspaper-frequency tag (nf01-nf48) that are common in everyday text or are prefixes and
suffixes (済み, which joins nouns: 確認済み). Ordered by frequency, one tab-separated line per
entry and reading:

    kanji  reading  usually-kana(0/1)  part-of-speech  senses  conjugation

Senses are separated by " | ", glosses within a sense by "; ". The conjugation class is how
the word inflects, for kanji conversion of forms like 食べた (see Conjugation.swift): v1
(ichidan), v5u … v5r (godan, by ending), v5k-s (行く), v5r-i (ある), v5aru (いらっしゃる), vk
(来る), vs (a noun that takes する), vs-i (ends in する), adj-i, adj-ix (いい/良い), or empty.

A word's other readings get lines of their own when JMdict marks them common, or when the word is
a prefix or suffix, whose reading often changes after another word (済み: すみ, ずみ).

With a fourth argument, also writes the extended lexicon: every other JMdict word with a kanji
spelling (背徳, 背徳感), for kanji conversion only. The keyboard memory-maps it rather than loading
it (see ExtendedLexicon.swift). Layout, little-endian: "RKLX", version, line count, the longest
reading in characters (UInt32 each), then one UInt32 offset per line into the text that follows.
Each line is a reading in hiragana, then for each word a tab and word␟band␟part of speech␟meaning,
most common first. Lines are sorted by the reading's UTF-8 bytes, for binary search. The band
(0-8) is how common the word is in everyday text: 0 is the most common.
"""
import gzip
import sqlite3
import struct
import sys
from collections import defaultdict

COMMON = {"news1", "ichi1", "spec1", "spec2", "gai1"}
# Words with only a newspaper-frequency tag are kept if wordfreq sees them at least this often.
EVERYDAY = 1e-6
AFFIXES = ("suffix", "prefix", "noun, used as a suffix", "noun, used as a prefix")
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


def hiragana(text):
    return "".join(chr(ord(ch) - 0x60) if 0x30A1 <= ord(ch) <= 0x30F6 else ch for ch in text)


def band(word_frequency, tagged):
    """0 (common in everyday text) to 8 (unknown to wordfreq and to JMdict's frequency tags)."""
    for number, threshold in enumerate([1e-6, 5e-7, 2e-7, 1e-7, 5e-8, 2e-8]):
        if word_frequency >= threshold:
            return number
    return 6 if word_frequency > 0 else 7 if tagged else 8


def write_lexicon(path, lines):
    """lines: reading → [(band, word, part of speech, meaning)]."""
    order = sorted(lines, key=lambda reading: reading.encode("utf-8"))
    text = bytearray()
    offsets = []
    for reading in order:
        offsets.append(len(text))
        words = sorted(set(lines[reading]))
        parts = [reading] + ["\x1f".join([word, str(number), part, meaning]) for number, word, part, meaning in words]
        text += ("\t".join(parts) + "\n").encode("utf-8")
    longest = max(len(reading) for reading in order)
    with open(path, "wb") as f:
        f.write(b"RKLX" + struct.pack("<III", 1, len(order), longest))
        f.write(struct.pack(f"<{len(offsets)}I", *offsets))
        f.write(text)
    words = sum(len(set(v)) for v in lines.values())
    print(f"lexicon: {words} words, {len(order)} readings, {(16 + 4 * len(offsets) + len(text)) / 1e6:.1f} MB", file=sys.stderr)


def main(db_path, out_path, wordfreq_path=None, lexicon_path=None):
    freq = load_wordfreq(wordfreq_path) if wordfreq_path else {}
    c = sqlite3.connect(db_path)
    tags = defaultdict(set)
    for idseq, tag in c.execute("SELECT k.idseq, p.text FROM Kanji k JOIN KJP p ON p.kid = k.ID"):
        tags[idseq].add(tag)
    reading_tags = defaultdict(set)
    for idseq, text, tag in c.execute("SELECT k.idseq, k.text, p.text FROM Kana k JOIN KNP p ON p.kid = k.ID"):
        tags[idseq].add(tag)
        reading_tags[(idseq, text)].add(tag)

    kanji = defaultdict(list)
    for idseq, text in c.execute("SELECT idseq, text FROM Kanji ORDER BY ID"):
        kanji[idseq].append(text)
    kana = defaultdict(list)
    # Readings that don't go with the first kanji spelling: nokanji, restricted to another
    # spelling, or marked irregular or obsolete.
    restricted = defaultdict(set)
    for kid, text in c.execute("SELECT kid, text FROM KNR"):
        restricted[kid].add(text)
    odd = {kid for (kid,) in c.execute("SELECT DISTINCT kid FROM KNI")}
    other_readings = defaultdict(list)
    for kid, idseq, text, nokanji in c.execute("SELECT ID, idseq, text, nokanji FROM Kana ORDER BY ID"):
        kana[idseq].append(text)
        if len(kana[idseq]) > 1 and not nokanji and kid not in odd:
            other_readings[idseq].append((text, restricted[kid]))
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

    def is_affix(idseq):
        return any(p.startswith(AFFIXES) for s in senses[idseq] for p in pos[s])

    def tagged(tag_set):
        return bool(tag_set & COMMON) or "news2" in tag_set or any(t.startswith("nf") for t in tag_set)

    def everyday(idseq):
        forms = kanji[idseq][:1] or kana[idseq][:1]
        return any(freq.get(form, 0) >= EVERYDAY for form in forms)

    common = [i for i, t in tags.items()
              if t & COMMON or (any(x.startswith("nf") for x in t) and (is_affix(i) or everyday(i)))]

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
        rows.append((-common_use, rank(tags[idseq]), idseq, 0, "\t".join(fields)))
        # Other readings of the same spelling, just after the main one.
        if fields[0]:
            affix = is_affix(idseq)
            for number, (reading, only) in enumerate(other_readings[idseq], start=1):
                if only and fields[0] not in only:
                    continue
                if affix or tagged(reading_tags[(idseq, reading)]):
                    rows.append((-common_use, rank(tags[idseq]), idseq, number, "\t".join([fields[0], reading] + fields[2:])))

    rows.sort()
    with open(out_path, "w", encoding="utf-8") as f:
        for *_, line in rows:
            f.write(line + "\n")
    print(f"{len(rows)} entries", file=sys.stderr)

    if not lexicon_path:
        return
    # Everything else with a kanji spelling, for conversion: the first spelling with each of its
    # readings (as hiragana, two kana or more), unless the word is usually written in kana, is
    # archaic or obsolete, is a set phrase the converter builds from its words anyway (良い天気
    # would beat いい天気), or the main dictionary has that spelling already: it has the readings
    # that are common (良い is よい; いい stays in kana).
    in_main = {line.split("\t")[0] for *_, line in rows}
    lines = defaultdict(list)
    for idseq, spellings in list(kanji.items()):
        sense_ids = [s for s in senses[idseq] if glosses[s]]
        if not spellings or not sense_ids or not kana[idseq]:
            continue
        first = sense_ids[0]
        if any("usually written using kana" in m or m.startswith(("archaism", "obsolete")) for m in misc[first]):
            continue
        word = spellings[0]
        readings = [kana[idseq][0]] + [r for r, only in other_readings[idseq] if not only or word in only]
        meaning = "; ".join(glosses[first][:2])[:60]
        part = short_pos(pos[first])
        if part == "expression" or any(ch in word + meaning + part for ch in "\t\n\x1f"):
            continue
        number = band(freq.get(word, 0), bool(tags[idseq]))
        for reading in dict.fromkeys(hiragana(r) for r in readings):
            if len(reading) >= 2 and word not in in_main:
                lines[reading].append((number, word, part, meaning))
    write_lexicon(lexicon_path, lines)


if __name__ == "__main__":
    # python3 tools/build_dictionary.py jamdict.db dictionary.tsv [large_ja.msgpack.gz [lexicon.bin]]
    main(*sys.argv[1:5])
