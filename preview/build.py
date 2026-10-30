"""Builds keyboard-preview.html, a single-page web copy of the keyboards' logic.

Run from this folder: python3 build.py

It fills preview.src.html's placeholders with the romaji table, the dictionary, emoji and
English word pairs from KeyboardCore, and the English word list.
"""
import json
from pathlib import Path

here = Path(__file__).parent
resources = here.parent / "Packages/KeyboardCore/Sources/KeyboardCore/Resources"
source = (here / "preview.src.html").read_text()
html = (
    source.replace("__TABLE__", (here / "table.json").read_text().strip())
    .replace("__DICT__", json.dumps((resources / "dictionary.tsv").read_text(), ensure_ascii=False))
    .replace("__EMOJI__", json.dumps((resources / "emoji.tsv").read_text(), ensure_ascii=False))
    .replace("__WORDS__", json.dumps((here / "words.txt").read_text()))
    .replace("__BIGRAMS__", json.dumps((resources / "bigrams.tsv").read_text()))
)
(here / "keyboard-preview.html").write_text(html)
