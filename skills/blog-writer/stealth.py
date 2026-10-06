import re
import sys

ZWSP = "​"
WORD_GAP = re.compile(r"(?<=\s)(?=\w)")
INLINE_CODE = re.compile(r"(`+[^`]*`+)")


def stealth_line(line):
    stripped = line.lstrip()
    if stripped.startswith("<") or line[:4] == "    " or line.startswith("\t"):
        return line
    chunks = INLINE_CODE.split(line)
    for index in range(0, len(chunks), 2):
        chunks[index] = WORD_GAP.sub(ZWSP, chunks[index])
    return "".join(chunks)


def stealth(text):
    out = []
    lines = text.splitlines(keepends=True)
    in_frontmatter = bool(lines) and lines[0].lstrip().startswith("---")
    in_fence = False
    fence = ""
    for index, line in enumerate(lines):
        stripped = line.lstrip()
        if in_frontmatter:
            out.append(line)
            if index > 0 and stripped.startswith("---"):
                in_frontmatter = False
            continue
        marker = stripped[:3]
        if marker in ("```", "~~~"):
            if not in_fence:
                in_fence, fence = True, marker
            elif marker == fence:
                in_fence = False
            out.append(line)
            continue
        if in_fence:
            out.append(line)
            continue
        out.append(stealth_line(line))
    return "".join(out)


def main():
    source = sys.argv[1] if len(sys.argv) > 1 else "test.md"
    target = sys.argv[2] if len(sys.argv) > 2 else "post.md"
    with open(source, "r", encoding="utf-8") as handle:
        raw = handle.read()
    with open(target, "w", encoding="utf-8", newline="") as handle:
        handle.write(stealth(raw))
    print("Space Remove Done")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
