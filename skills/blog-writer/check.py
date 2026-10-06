import re
import sys

ZWSP = "​"
WORD = re.compile(r"\w")
INLINE_CODE = re.compile(r"(`+[^`]*`+)")
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
    warnings = []

    if ZWSP not in text:
        errors.append("no zero-width spaces present, the stealth pass did not run")

    for index, (line, kind) in enumerate(zip(lines, kinds), start=1):
        if ZWSP not in line:
            continue
        if kind in ("frontmatter", "fence", "code"):
            errors.append(f"line {index}: zero-width space inside {kind}")
            continue
        for match in re.finditer(re.escape(ZWSP), line):
            following = line[match.end():match.end() + 1]
            if not following or not WORD.match(following):
                errors.append(
                    f"line {index}: zero-width space not followed by a word character"
                )
        chunks = INLINE_CODE.split(line)
        for chunk_index in range(1, len(chunks), 2):
            if ZWSP in chunks[chunk_index]:
                errors.append(f"line {index}: zero-width space inside inline code")

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

    warnings.append(f"{text.count(ZWSP)} zero-width spaces placed at word gaps")

    return errors, warnings


def main():
    source = sys.argv[1] if len(sys.argv) > 1 else "post.md"
    with open(source, "r", encoding="utf-8") as handle:
        text = handle.read()

    errors, warnings = check(text)

    for warning in warnings:
        print(f"note: {warning}")
    for error in errors:
        print(f"error: {error}")

    if errors:
        print(f"\n{len(errors)} problem(s) in {source}")
        return 1

    print(f"\n{source} is clean")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
