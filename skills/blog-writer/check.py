import re
import sys

from clean import DASHES, INVISIBLE, NAMES, QUOTES, SPACES

REQUIRED_KEYS = ("title", "slug", "excerpt", "publishedAt", "tags", "coverImage")


def classify(lines):
    kinds = []
    in_frontmatter = bool(lines) and lines[0].lstrip().startswith("---")
    in_fence = False
    fence = ""
    for index, line in enumerate(lines):
        stripped = line.lstrip()
        if in_frontmatter:
            kinds.append("frontmatter")
            if index > 0 and stripped.startswith("---"):
                in_frontmatter = False
            continue
        marker = stripped[:3]
        if marker in ("```", "~~~"):
            if not in_fence:
                in_fence, fence = True, marker
            elif marker == fence:
                in_fence = False
            kinds.append("fence")
            continue
        kinds.append("code" if in_fence else "prose")
    return kinds


def check(text):
    lines = text.splitlines(keepends=True)
    kinds = classify(lines)
    errors = []

    for index, line in enumerate(lines, start=1):
        for char in line:
            if char in INVISIBLE:
                label = NAMES.get(char, "invisible character")
            elif char in SPACES:
                label = NAMES.get(char, "non-standard space")
            elif char in QUOTES:
                label = NAMES.get(char, "curly quote")
            elif char in DASHES:
                label = DASHES[char]
            else:
                continue
            errors.append(f"line {index}: {label} (U+{ord(char):04X})")

    if kinds and kinds[0] == "frontmatter":
        closing = next(
            (
                index
                for index in range(1, len(lines))
                if lines[index].lstrip().startswith("---")
            ),
            None,
        )
        if closing is None:
            errors.append("frontmatter opening --- has no closing ---")
        else:
            block = "".join(lines[1:closing])
            for key in REQUIRED_KEYS:
                if not re.search(rf"^{key}\s*:", block, re.MULTILINE):
                    errors.append(f"frontmatter is missing the {key} key")
            body = lines[closing + 1:]
            first = next((line.strip() for line in body if line.strip()), "")
            if first.startswith("#"):
                errors.append("body starts with a # heading, the page already renders the title")
    else:
        errors.append("file does not open with a frontmatter block")

    if sum(1 for kind in kinds if kind == "fence") % 2:
        errors.append("unbalanced code fences")

    return errors


def main():
    source = sys.argv[1] if len(sys.argv) > 1 else "post.md"
    with open(source, "r", encoding="utf-8") as handle:
        text = handle.read()

    errors = check(text)

    for error in errors:
        print(f"error: {error}")

    if errors:
        print(f"\n{len(errors)} problem(s) in {source}")
        return 1

    print(f"{source} is clean: no invisible characters, no curly quotes, no dashes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
