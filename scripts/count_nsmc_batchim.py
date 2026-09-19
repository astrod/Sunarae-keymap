#!/usr/bin/env python3
"""Count written compound finals in NSMC ratings.txt; never reads user input.

Download the pinned public file separately, then pass its local path.
Only aggregates reach stdout. This script is not part of the input method.
"""
import csv
import hashlib
import json
from pathlib import Path
import sys
import unicodedata
from collections import Counter

COMMIT = "cc0670e872d4ac27bfe36c87456783004b39ef6c"
SOURCE = f"https://raw.githubusercontent.com/e9t/nsmc/{COMMIT}/ratings.txt"
COMPOUNDS = {
    3: "ㄳ", 5: "ㄵ", 6: "ㄶ", 9: "ㄺ", 10: "ㄻ", 11: "ㄼ",
    12: "ㄽ", 13: "ㄾ", 14: "ㄿ", 15: "ㅀ", 18: "ㅄ",
}


def count(path):
    finals = Counter()
    reviews = empty_reviews = hangul_syllables = 0
    with path.open(encoding="utf-8", newline="") as stream:
        reader = csv.reader(stream, delimiter="\t", quoting=csv.QUOTE_NONE)
        if next(reader) != ["id", "document", "label"]:
            raise ValueError("Unexpected NSMC header")
        for line, row in enumerate(reader, 2):
            if len(row) != 3 or row[2] not in ("0", "1"):
                raise ValueError(f"Invalid NSMC row at line {line}")
            reviews += 1
            document = unicodedata.normalize("NFC", row[1])
            empty_reviews += not document
            for char in document:
                code = ord(char)
                if 0xAC00 <= code <= 0xD7A3:
                    hangul_syllables += 1
                    finals[(code - 0xAC00) % 28] += 1
    if reviews != 200_000:
        raise ValueError(f"Expected full 200,000-review corpus; got {reviews}")
    total = sum(finals[index] for index in COMPOUNDS)
    return {
        "source": SOURCE,
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "method": "NFC-normalized document column only; written syllable occurrences; no spelling correction or deduplication",
        "reviews": reviews,
        "empty_reviews": empty_reviews,
        "hangul_syllables": hangul_syllables,
        "compound_final_occurrences": total,
        "compound_finals": [
            {"final": COMPOUNDS[index], "count": finals[index],
             "percent_of_compound_finals": round(100 * finals[index] / total, 4)}
            for index in sorted(COMPOUNDS, key=lambda index: (-finals[index], index))
        ],
        "separate_double_consonant_finals": {"ㄲ": finals[2], "ㅆ": finals[20]},
    }


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: count_nsmc_batchim.py PATH_TO_RATINGS_TXT")
    print(json.dumps(count(Path(sys.argv[1])), ensure_ascii=False, indent=2))
