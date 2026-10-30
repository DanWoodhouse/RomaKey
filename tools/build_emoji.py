"""Builds the keyboard's emoji list from emojibase-data (MIT, https://emojibase.dev).

    npm install emojibase-data
    python3 tools/build_emoji.py node_modules/emojibase-data Packages/KeyboardCore/Sources/KeyboardCore/Resources

Writes emoji.tsv, one emoji per line, in Unicode's order:

    emoji  group  version  skin-tones  english-name  english-keywords  japanese-name  japanese-keywords

Skin tones and keywords are space-separated. Names are used to rank suggestions: an emoji whose
name contains the word (🐕 "dog") beats one that's only tagged with it (🦴 "bone"). Japanese keywords include hiragana readings of the kanji and
katakana tags (猫 → ねこ, ネコ → ねこ), taken from the keyboard's JMdict dictionary, so typing
ねこ in Japanese suggests 🐱.
"""
import json
import os
import re
import sys


def hiragana(text):
    return "".join(chr(ord(c) - 0x60) if 0x30A1 <= ord(c) <= 0x30F6 else c for c in text)


def main(emojibase, resources):
    en = json.load(open(os.path.join(emojibase, "en/data.json"), encoding="utf-8"))
    ja = {e["hexcode"]: e for e in json.load(open(os.path.join(emojibase, "ja/data.json"), encoding="utf-8"))}

    # Kanji word → readings, from the dictionary we already ship.
    readings = {}
    for line in open(os.path.join(resources, "dictionary.tsv"), encoding="utf-8"):
        kanji, reading = line.split("\t")[:2]
        if kanji:
            readings.setdefault(kanji, []).append(hiragana(reading))

    rows = []
    for e in sorted(en, key=lambda e: e.get("order", 1e9)):
        group = e.get("group")
        if group is None or group == 2:  # skip components (skin tones, hair) and regional indicators
            continue
        english = [e["label"]] + e.get("tags", [])
        english_words = []
        for phrase in english:
            for word in phrase.lower().replace(":", " ").replace(",", " ").split():
                if word not in english_words:
                    english_words.append(word)
        japanese_words = []
        j = ja.get(e["hexcode"], {})
        tags = [part for tag in [j.get("label", "")] + j.get("tags", []) for part in re.split(r"[:：\s,、・]+", tag)]
        for tag in tags:
            for word in [tag, hiragana(tag)] + readings.get(tag, []):
                if word and " " not in word and word not in japanese_words:
                    japanese_words.append(word)
        # Single skin-tone variants only (multi-person emoji have a tone per person).
        skins = " ".join(s["emoji"] for s in e.get("skins", []) if isinstance(s.get("tone"), int))
        fields = [e["emoji"], str(group), str(e.get("version", 0)), skins,
                  e["label"].lower(), " ".join(english_words), j.get("label", ""), " ".join(japanese_words)]
        if any("\t" in f or "\n" in f for f in fields):
            continue
        rows.append("\t".join(fields))

    with open(os.path.join(resources, "emoji.tsv"), "w", encoding="utf-8") as f:
        f.write("\n".join(rows) + "\n")
    print(f"{len(rows)} emoji", file=sys.stderr)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
