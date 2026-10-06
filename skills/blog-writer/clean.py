import sys

INVISIBLE = (
    "­"  # soft hyphen
    "᠎"  # mongolian vowel separator
    "​"  # zero width space
    "‌"  # zero width non-joiner
    "‍"  # zero width joiner
    "‎"  # left-to-right mark
    "‏"  # right-to-left mark
    "‪‫‬‭‮"  # bidi embedding and override
    "⁠"  # word joiner
    "⁡⁢⁣⁤"  # invisible operators
    "⁦⁧⁨⁩"  # bidi isolates
    "﻿"  # BOM, also zero width no-break space
)

SPACES = (
    "             "
    "  　"
)

QUOTES = {
    "‘": "'",
    "’": "'",
    "‚": "'",
    "‛": "'",
    "“": '"',
    "”": '"',
    "„": '"',
    "′": "'",
    "″": '"',
}

DASHES = {
    "‒": "figure dash",
    "–": "en dash",
    "—": "em dash",
    "―": "horizontal bar",
    "−": "minus sign",
}

NAMES = {
    "­": "soft hyphen",
    "᠎": "mongolian vowel separator",
    "​": "zero width space",
    "‌": "zero width non-joiner",
    "‍": "zero width joiner",
    "‎": "left-to-right mark",
    "‏": "right-to-left mark",
    "‪": "left-to-right embedding",
    "‫": "right-to-left embedding",
    "‬": "pop directional formatting",
    "‭": "left-to-right override",
    "‮": "right-to-left override",
    "⁠": "word joiner",
    "⁡": "function application",
    "⁢": "invisible times",
    "⁣": "invisible separator",
    "⁤": "invisible plus",
    "⁦": "left-to-right isolate",
    "⁧": "right-to-left isolate",
    "⁨": "first strong isolate",
    "⁩": "pop directional isolate",
    "﻿": "byte order mark",
    " ": "no-break space",
    " ": "ogham space mark",
    " ": "en quad",
    " ": "em quad",
    " ": "en space",
    " ": "em space",
    " ": "three-per-em space",
    " ": "four-per-em space",
    " ": "six-per-em space",
    " ": "figure space",
    " ": "punctuation space",
    " ": "thin space",
    " ": "hair space",
    " ": "narrow no-break space",
    " ": "medium mathematical space",
    "　": "ideographic space",
    "‘": "left single quote",
    "’": "right single quote",
    "‚": "single low quote",
    "‛": "single high-reversed quote",
    "“": "left double quote",
    "”": "right double quote",
    "„": "double low quote",
    "′": "prime",
    "″": "double prime",
}


def clean(text):
    counts = {}
    out = []
    for char in text:
        if char in INVISIBLE:
            counts[char] = counts.get(char, 0) + 1
            continue
        if char in SPACES:
            counts[char] = counts.get(char, 0) + 1
            out.append(" ")
            continue
        if char in QUOTES:
            counts[char] = counts.get(char, 0) + 1
            out.append(QUOTES[char])
            continue
        out.append(char)
    return "".join(out), counts


def find_dashes(text):
    hits = []
    for number, line in enumerate(text.splitlines(), start=1):
        for char, name in DASHES.items():
            if char in line:
                hits.append((number, name))
    return hits


def main():
    source = sys.argv[1] if len(sys.argv) > 1 else "test.md"
    target = sys.argv[2] if len(sys.argv) > 2 else "post.md"

    with open(source, "r", encoding="utf-8") as handle:
        raw = handle.read()

    cleaned, counts = clean(raw)

    with open(target, "w", encoding="utf-8", newline="") as handle:
        handle.write(cleaned)

    total = sum(counts.values())
    if total:
        print(f"removed {total} character(s) from {source}")
        for char, count in sorted(counts.items(), key=lambda item: -item[1]):
            print(f"  {count:4d}  U+{ord(char):04X}  {NAMES.get(char, 'unnamed')}")
    else:
        print(f"{source} had nothing to remove")

    hits = find_dashes(cleaned)
    if hits:
        print("\ndash characters left for you to rewrite by hand:")
        for number, name in hits:
            print(f"  line {number}: {name}")
    else:
        print("no en or em dashes")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
