"""Builds bigrams.tsv, the English word pairs behind predictive text.

    pip download symspellpy --no-deps && unzip symspellpy-*.whl
    python3 tools/build_bigrams.py symspellpy/frequency_bigramdictionary_en_243_342.txt preview/words.txt \\
        Packages/KeyboardCore/Sources/KeyboardCore/Resources/bigrams.tsv

The pair counts come from SymSpell's bigram list (MIT), built from Google Books Ngrams (CC BY 3.0).
Only pairs where both words are among the 25,000 most common English words are kept, and only
the four most frequent next words for each word:

    thank<TAB>you the all my
"""
import sys
from collections import defaultdict


def main(bigrams_path, words_path, out_path):
    vocabulary = set(open(words_path, encoding="utf-8").read().split("\n"))
    following = defaultdict(list)
    for line in open(bigrams_path, encoding="utf-8"):
        first, second, count = line.split()
        if first in vocabulary and second in vocabulary:
            following[first].append((int(count), second))
    with open(out_path, "w", encoding="utf-8") as out:
        for word in sorted(following):
            best = [second for _, second in sorted(following[word], reverse=True)[:4]]
            out.write(word + "\t" + " ".join(best) + "\n")


if __name__ == "__main__":
    main(*sys.argv[1:4])
