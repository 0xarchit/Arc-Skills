import json
import re
import statistics
import sys

CONTRACTION = re.compile(r"\b\w+'(?:s|t|re|ve|ll|d|m)\b", re.IGNORECASE)
# A sentence ends at . ! or ? only when whitespace follows AND the next sentence starts
# with a capital, a digit, or an opening quote or bracket. A dot inside 4.68, measure.py,
# or 0xarchit.is-a.dev has no whitespace after it, so it is never a boundary. The second
# lookbehind catches a closing quote between the punctuation and the space, as in
# `He said "stop." Then we left.`, which re cannot express as one variable-width pattern.
SENTENCE_END = re.compile(
    r"(?:(?<=[.!?])|(?<=[.!?][\"')\]’”]))\s+(?=[A-Z0-9\"'(\[‘“])"
)
WORD = re.compile(r"[A-Za-z0-9']+")
SKIP = ("#", "|", "---", "```", "~~~", ">", "![")

UNCONTRACTED = (
    "do not", "does not", "did not", "is not", "are not", "was not", "were not",
    "cannot", "can not", "will not", "would not", "should not", "could not",
    "have not", "has not", "had not", "it is", "that is", "there is", "there are",
    "I am", "I will", "I would", "you are", "we are", "they are", "let us",
)

HEDGES = (
    "may", "might", "could", "generally", "typically", "often", "usually", "tends to",
    "tend to", "in general", "for the most part", "it depends", "arguably", "somewhat",
    "relatively", "fairly", "quite", "rather", "overall", "essentially", "effectively",
)

TRANSITIONS = (
    "however", "moreover", "furthermore", "additionally", "therefore", "thus",
    "consequently", "nevertheless", "nonetheless", "in addition", "as a result",
    "on the other hand", "in contrast", "similarly", "meanwhile", "ultimately",
    "in conclusion", "to summarize", "that said", "at the same time",
)

NAMED = (
    "delve", "leverage", "robust", "seamless", "crucial", "realm", "landscape",
    "tapestry", "navigate", "underscore", "testament", "pivotal", "intricate",
    "meticulous", "myriad", "foster", "showcase", "unlock", "elevate", "vital",
    "paramount", "holistic", "streamline", "harness", "embark", "profound",
)

COMMON_WORDS = frozenset("""
the be and of a in to have it i that for you he with on do say this they at but we
his from not by she or as what go their can who get if would her all my make about
know will up one time there year so think when which them some me people take out
into just see him your come could now than like other how then its our two more
these want way look first also new because day use no man find here thing give many
well only those tell very even back any good woman through us life child work down
may after should call world over school still try last ask need too feel three state
never become between high really something most another much family own leave put
old while mean keep student great same big group begin seem country help talk where
turn problem every start hand might show part against place such again few case week
company system each right program hear question during play government run small
number off always move night live point believe hold today bring happen next without
before large million must home under water room write provide mother area national
money story young fact month different lot book eye job word though business issue
side kind four head far black long both little house yes since service around friend
important father sit away until power hour game often yet line end among ever stand
bad lose member pay law meet car city almost include continue set later community
name five once white least learn real change team minute best several idea body
information nothing ago lead social understand whether watch together follow parent
stop face anything create public already speak others read level allow add office
spend door health person art sure war history party within grow result open morning
walk reason low win research girl guy early food moment air teacher force offer
""".split())

FUNCTION_WORDS = frozenset("""
the a an and or but if while of to in on at by for with from into over under
is are was were be been being am do does did doing have has had having
i you he she it we they me him her us them my your his its our their
this that these those there here who whom which what when where why how
not no nor so as than then too very can could will would shall should may might must
just also only even still yet again more most much many some any all both each few
""".split())

LY_EXCEPTIONS = frozenset("""
only family apply reply supply early holy ugly fly rely july italy assembly anomaly
multiply imply comply ally belly jelly rally tally bully
""".split())

NOMINAL_SUFFIXES = ("tion", "sion", "ment", "ness", "ity", "ance", "ence")


def prose_blocks(text):
    lines = text.splitlines()
    blocks = []
    current = []
    in_frontmatter = bool(lines) and lines[0].lstrip().startswith("---")
    in_fence = False
    fence = ""
    for index, line in enumerate(lines):
        stripped = line.strip()
        if in_frontmatter:
            if index > 0 and stripped.startswith("---"):
                in_frontmatter = False
            continue
        marker = stripped[:3]
        if marker in ("```", "~~~"):
            if not in_fence:
                in_fence, fence = True, marker
            elif marker == fence:
                in_fence = False
            continue
        if in_fence:
            continue
        if not stripped:
            if current:
                blocks.append(" ".join(current))
                current = []
            continue
        if any(stripped.startswith(prefix) for prefix in SKIP):
            continue
        current.append(stripped)
    if current:
        blocks.append(" ".join(current))
    return blocks


def split_sentences(text):
    if not text:
        return []
    return [chunk for chunk in SENTENCE_END.split(text) if WORD.search(chunk)]


SELFTEST_CASES = (
    ("It runs 4.68 ms on Windows.", 1),
    ("SQLite takes 60.6 ms. Turso is faster.", 2),
    ("Read measure.py next.", 1),
    ("Go to 0xarchit.is-a.dev now.", 1),
    ("Query cost 0.042 per million tokens.", 1),
    ("Version 1.2.3 shipped. It works.", 2),
    ("Wait. 4.68 ms is fast.", 2),
    ("It failed. Then I retried.", 2),
    ("e.g. this should not split.", 1),
    ('He said "stop." Then we left.', 2),
)


def selftest():
    failures = 0
    for text, expected in SELFTEST_CASES:
        got = len(split_sentences(text))
        if got != expected:
            failures += 1
            print(f"FAIL  {text!r} expected {expected} sentence(s), got {got}")
            print(f"      {split_sentences(text)}")
    print(f"selftest: {len(SELFTEST_CASES) - failures}/{len(SELFTEST_CASES)} passed")
    return 1 if failures else 0


def ratio(part, whole):
    return part / whole if whole else 0.0


def rhythm(lines, sentences):
    lengths = [len(WORD.findall(chunk)) for chunk in sentences]
    mean = statistics.mean(lengths)
    stdev = statistics.pstdev(lengths)
    buckets = {"1-10": 0, "11-20": 0, "21-35": 0, "36+": 0}
    for n in lengths:
        if n <= 10:
            buckets["1-10"] += 1
        elif n <= 20:
            buckets["11-20"] += 1
        elif n <= 35:
            buckets["21-35"] += 1
        else:
            buckets["36+"] += 1

    longest_run = 1
    run = 1
    for before, after in zip(lengths, lengths[1:]):
        run = run + 1 if abs(before - after) <= 3 else 1
        longest_run = max(longest_run, run)

    para_words = [len(WORD.findall(block)) for block in lines]
    para_cv = (
        statistics.pstdev(para_words) / statistics.mean(para_words)
        if len(para_words) > 1 and statistics.mean(para_words)
        else 0.0
    )

    print("RHYTHM")
    print(f"  sentences        : {len(lengths)}")
    print(f"  mean words       : {mean:.1f}")
    print(f"  stdev            : {stdev:.1f}")
    print(f"  burstiness (CV)  : {stdev / mean:.2f}   higher is better, aim above 0.65")
    for name, count in buckets.items():
        print(f"  {name:>10} words : {count:3d}  {ratio(count, len(lengths)) * 100:5.1f}%")
    print(f"  longest even run : {longest_run} sentences within 3 words of each other")
    print(f"  paragraphs       : {len(para_words)}, mean {statistics.mean(para_words):.1f} words, CV {para_cv:.2f}")

    return stdev / mean, ratio(buckets["11-20"], len(lengths)), longest_run


def vocabulary(words, body):
    lowered = [word.lower() for word in words]
    unique = set(lowered)
    once = sum(1 for word in unique if lowered.count(word) == 1)
    common = sum(1 for word in lowered if word in COMMON_WORDS)

    grams = {}
    for index in range(len(lowered) - 3):
        gram = " ".join(lowered[index:index + 4])
        grams[gram] = grams.get(gram, 0) + 1
    repeated = sorted(
        ((gram, count) for gram, count in grams.items() if count > 1),
        key=lambda item: -item[1],
    )

    print("\nVOCABULARY, perplexity proxies")
    print("  true perplexity needs a language model, read these as directional")
    print(f"  words            : {len(lowered)}")
    print(f"  type-token ratio : {ratio(len(unique), len(lowered)):.2f}")
    print(f"  hapax ratio     : {ratio(once, len(unique)):.2f}   words used exactly once")
    print(f"  common-word rate : {ratio(common, len(lowered)):.2f}   lower is less predictable")
    if repeated:
        print("  repeated 4-grams :")
        for gram, count in repeated[:5]:
            print(f"      x{count}  {gram}")
    else:
        print("  repeated 4-grams : none, good")

    return ratio(common, len(lowered)), len(repeated)


def load_terms(path):
    """topic_terms only ever excuse a word from the repetition and nominalization
    counts. They can never silence the fixed tell lists below, so an allowlist cannot
    be used to hide a real hit. watchlist only ever adds scrutiny."""
    try:
        with open(path, "r", encoding="utf-8") as handle:
            data = json.load(handle)
    except FileNotFoundError:
        return set(), set(), None
    except (OSError, ValueError) as error:
        return set(), set(), f"could not read {path}: {error}"

    topic = {str(term).lower() for term in data.get("topic_terms", [])}
    watch = {str(term).lower() for term in data.get("watchlist", [])}
    return topic, watch, None


def habits(words, body, topic_terms, watchlist):
    lowered = [word.lower() for word in words]
    total = len(lowered)

    content = {}
    for word in lowered:
        if word in FUNCTION_WORDS or len(word) < 4 or word in topic_terms:
            continue
        content[word] = content.get(word, 0) + 1
    repeated = sorted(
        ((word, count) for word, count in content.items() if count >= 3),
        key=lambda item: -item[1],
    )

    topic_counts = {}
    for word in lowered:
        if word in topic_terms:
            topic_counts[word] = topic_counts.get(word, 0) + 1
    topical = sorted(topic_counts.items(), key=lambda item: -item[1])

    adverbs = [
        word for word in lowered
        if word.endswith("ly") and len(word) > 4 and word not in LY_EXCEPTIONS
    ]
    nominals = [
        word for word in lowered
        if len(word) > 5 and word.endswith(NOMINAL_SUFFIXES) and word not in topic_terms
    ]
    top_nominals = sorted(
        ((word, nominals.count(word)) for word in set(nominals)),
        key=lambda item: -item[1],
    )[:5]

    plain = body.lower()
    watch_hits = []
    for term in sorted(watchlist):
        count = plain.count(term) if " " in term else lowered.count(term)
        if count:
            watch_hits.append((term, count))
    watch_hits.sort(key=lambda item: -item[1])

    print("\nHABITS   thresholds here are rough guides, not detector cutoffs")
    if repeated:
        print("  repeated content words:")
        for word, count in repeated[:8]:
            print(f"      x{count:<4} {word}")
    else:
        print("  repeated content words: none, good")
    if topical:
        print("  topic terms, expected, excluded from the count above:")
        print("      " + ", ".join(f"{word} x{count}" for word, count in topical[:8]))
    if watch_hits:
        print("  watchlist:")
        for term, count in watch_hits[:8]:
            print(f"      x{count:<4} {term}")
    print(f"  adverb -ly       : {ratio(len(adverbs), total) * 100:.1f}% of words   keep under 3%")
    print(f"  nominalization   : {ratio(len(nominals), total) * 100:.1f}% of words   keep under 6%, topic terms out")
    if top_nominals:
        print("      " + ", ".join(f"{word} x{count}" for word, count in top_nominals))

    return {
        "repeated": repeated[0][1] if repeated else 0,
        "adverbs": ratio(len(adverbs), total),
        "nominals": ratio(len(nominals), total),
        "watch": watch_hits[0][1] if watch_hits else 0,
    }


def tell_counts(body):
    lowered = body.lower()
    words = WORD.findall(body)
    total = len(words)

    contractions = len(CONTRACTION.findall(body))
    uncontracted = sum(lowered.count(phrase.lower()) for phrase in UNCONTRACTED)
    hedges = sum(lowered.count(phrase.lower()) for phrase in HEDGES)
    transitions = sum(lowered.count(phrase.lower()) for phrase in TRANSITIONS)
    named = sum(lowered.count(phrase.lower()) for phrase in NAMED)

    openers = {}
    for chunk in split_sentences(body):
        found = WORD.findall(chunk)
        if found:
            key = found[0].lower()
            openers[key] = openers.get(key, 0) + 1
    top = sorted(openers.items(), key=lambda item: -item[1])[:5]

    print("\nTELLS")
    print(f"  contractions     : {contractions}   one every {total // max(contractions, 1)} words, aim 40 to 60")
    print(f"  uncontracted     : {uncontracted}   these should be contractions instead")
    print(f"  hedges           : {hedges}   {ratio(hedges, total) * 100:.1f}% of words")
    print(f"  transitions      : {transitions}   {ratio(transitions, total) * 100:.1f}% of words")
    print(f"  llm lexicon      : {named}   words from the banned list")
    print("  top openers      : " + ", ".join(f"{word} x{count}" for word, count in top))

    return {
        "contractions": contractions,
        "uncontracted": uncontracted,
        "hedges": ratio(hedges, total),
        "transitions": ratio(transitions, total),
        "named": named,
        "top_opener": top[0][1] if top else 0,
    }


def verdict(cv, mid, tells, habit_stats):
    notes = []
    contractions = tells["contractions"]

    if contractions == 0:
        notes.append("FAIL  zero contractions, the single biggest tell")
    elif contractions and tells["uncontracted"] > contractions:
        notes.append("WEAK  more uncontracted forms than contractions, expand fewer")
    else:
        notes.append("ok    contractions present")

    if cv >= 0.65:
        notes.append("ok    burstiness is high")
    elif cv >= 0.50:
        notes.append("WEAK  burstiness is middling, mix in very short and very long sentences")
    else:
        notes.append("FAIL  burstiness is low, sentence lengths are too even")

    if mid <= 0.30:
        notes.append("ok    sentence lengths are spread out")
    elif mid <= 0.40:
        notes.append("WEAK  too many sentences land in the 11 to 20 word band")
    else:
        notes.append("FAIL  most sentences are the same length")

    if tells["hedges"] > 0.015:
        notes.append("WEAK  heavy hedging, commit to a view somewhere")
    if tells["transitions"] > 0.012:
        notes.append("WEAK  formal transition words are piling up")
    if tells["named"] > 0:
        notes.append(f"FAIL  {tells['named']} word(s) from the banned LLM lexicon")
    if tells["top_opener"] > 6:
        notes.append("WEAK  one sentence opener is doing too much work")

    if habit_stats["repeated"] >= 6:
        notes.append("WEAK  one content word repeats a lot, vary the wording")
    if habit_stats["adverbs"] > 0.03:
        notes.append("WEAK  too many -ly adverbs")
    if habit_stats["nominals"] > 0.06:
        notes.append("WEAK  heavy nominalization, prefer plain verbs")

    if habit_stats["watch"] >= 3:
        notes.append("WEAK  a watchlisted term keeps coming back")

    print()
    for note in notes:
        print(note)


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--selftest":
        return selftest()

    source = sys.argv[1] if len(sys.argv) > 1 else "post.md"
    default_terms = re.sub(r"\.md$", "", source) + ".terms.json"
    terms_path = sys.argv[2] if len(sys.argv) > 2 else default_terms
    topic_terms, watchlist, terms_error = load_terms(terms_path)

    with open(source, "r", encoding="utf-8") as handle:
        text = handle.read()

    blocks = prose_blocks(text)
    body = " ".join(blocks)
    words = WORD.findall(body)
    sentences = split_sentences(body)

    if not sentences:
        print(f"{source} has no prose to measure")
        return 0

    print(f"{source}")
    if terms_error:
        print(f"terms file       : {terms_error}")
    elif topic_terms or watchlist:
        print(f"terms file       : {terms_path}, {len(topic_terms)} topic, {len(watchlist)} watch")
    else:
        print(f"terms file       : none at {terms_path}, fixed lists only")
    print()

    cv, mid, _ = rhythm(blocks, sentences)
    vocabulary(words, body)
    tells = tell_counts(body)
    habit_stats = habits(words, body, topic_terms, watchlist)
    verdict(cv, mid, tells, habit_stats)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
