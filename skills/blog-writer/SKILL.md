---
id: blog-writer
name: Blog Writer
description: Personal blog post writer for the 0xArchit portfolio blog. Use when asked to draft, write, or outline a portfolio blog post, or to produce a post's cover thumbnail or diagram SVGs. Outputs one markdown file with YAML frontmatter plus themed SVG assets, ready to paste into the Sanity Studio. Body text is stripped of invisible characters, non-standard spaces, and curly quotes before handoff. Requires the humanizer plugin, and stops to ask for it when it is not installed.
category: writing
tags: [personal, blog-writer, writing, markdown]
---

# Portfolio blog post creator

Produces a finished blog post for the portfolio's Sanity-backed blog at `/blog`.
The blog is decoupled: content lives in Sanity, this skill writes the files a human
pastes into the Studio.

## Files in this skill

Everything this skill needs travels with it. Nothing here reads a file outside this
folder.

```
skill.md                        this document
clean.py                        strips invisible characters and curly quotes
check.py                        the gate, imports character tables from clean.py
measure.py                      prose statistics and tells, stdlib only
reference/cover-example.svg     the cover thumbnail house style
```

The only paths it writes to are in the target project, under `blog/posts/`.

## Preflight

This skill depends on the `humanizer:humanizer` skill. Check it is loaded before writing
anything: look for `humanizer:humanizer` in the available skills, or try to invoke it.
You can also check `~/.claude/plugins/installed_plugins.json` for a `humanizer@humanizer`
entry.

If it is missing, stop immediately and tell the user to install it. Do not write the post,
and do not try to reproduce the humanizer rules by hand as a substitute.

```
/plugin marketplace add blader/humanizer
/plugin install humanizer@humanizer
```

Source: https://github.com/blader/humanizer

## Output contract

One post = one markdown file plus optional SVG assets. Nothing else.

```
blog/posts/test.md                       the draft you write
blog/posts/post.md                       the final post, after the clean pass
blog/posts/<slug>-cover.svg              the thumbnail, always
blog/posts/<slug>-<name>.svg             figures, only if the post needs one
```

The post is written to `test.md`, run through `clean.py`, and the result becomes
`post.md`. `post.md` is the artifact you hand over. `test.md` is deleted at the end.

`blog/` is gitignored on purpose. Do not commit these files.

The frontmatter is a paste sheet for the Sanity Studio, not something the build reads.
Each key maps to a field in the Sanity post schema, listed in the table below.

## Frontmatter

```yaml
---
title: "How I wired a headless CMS into my portfolio"
slug: "headless-cms-portfolio-blog"
excerpt: "Short summary, one or two sentences. Shows on the blog card and becomes the meta description."
publishedAt: "2026-10-06T00:00:00.000Z"
tags: [nextjs, sanity, blog, headless, cms]
coverImage: "headless-cms-portfolio-blog-cover.svg"
---
```

| Key | Sanity field | Rules |
| --- | --- | --- |
| `title` | Title (string, required) | Sentence case, no clickbait, under 70 chars. No colon-stacked SEO titles. |
| `slug` | Slug (required, max 96) | Lowercase, hyphens, no stop words, no dates. Derive from the title. |
| `excerpt` | Excerpt (text) | 120 to 160 chars so it fits the meta description and the card. Plain sentence, no marketing. |
| `publishedAt` | Published at (datetime) | ISO 8601 UTC. Only set it to a date that has already happened. |
| `tags` | Tags (array of strings) | 2 to 5, lowercase, no `#` prefix. The site renders them as `#tag`. |
| `coverImage` | Cover image (image) | Filename of the local SVG. Upload it to the studio field; it needs no URL here. |

`body` has no frontmatter key. Everything below the closing `---` is the body.

## The body

Markdown, rendered by `react-markdown` with `remark-gfm` and `rehype-highlight`.
Supported: `##` and `###` headings, paragraphs, `[links](url)`, unordered and ordered
lists, task lists, `> blockquotes`, `**bold**`, `*italic*`, `~~strike~~`, `---` rules,
fenced code blocks with language tags, inline code, tables, and images.

Two hard rules:

- **Never open the body with an `#` heading.** The page already renders the title as the
  page heading. Start with a paragraph, then `##`. An `#` duplicates the title.
- **Never repeat the title as the first line.** Same reason.

Images go in as absolute URLs because the body is stored as plain text and the site
cannot resolve relative paths. Upload figures to the file host the rest of the site
already uses (`files.0xarchit.is-a.dev`) and reference the full URL. The cover is the
exception: upload that one to the studio's cover image field instead.

## Writing rules

These are not style preferences. They came out of review passes on this blog.

Read this first. AI detectors measure statistical regularity, not authorship. They score
perplexity and burstiness, which means they flag prose that is smooth, even, and
predictable. That is what a language model produces by default, so a clean polished draft
reads as machine-written no matter how good the vocabulary is. A wording pass alone does
not fix it. The rules below target the shape of the prose, not just the word choice. They
improve the odds. Nothing guarantees a score, and any tool that promises one is selling
something.

**Do not try to defeat the detector.** Invisible characters, homoglyphs, deliberate typos,
and "AI bypass" tools are evasion, not writing. Detectors treat invisible-character
manipulation as its own signal, so it makes the score worse, and it wrecks the text. Fix
the prose instead.

**Use contractions. This is the single biggest lever.**

- Write "don't", "isn't", "I'd", "can't", "it's", "won't", "that's", "there's".
- A 1500 word technical post with zero contractions is the loudest signal there is, and
  the cheapest one to fix. If you fix nothing else, fix this.
- Expand nothing. "do not", "is not", "I would", "cannot", "it is", "will not" all read as
  machine output in prose. Keep the uncontracted form only where the emphasis is the whole
  point, which is rare.
- This does not apply inside code blocks.

**One thing is not fixable.** Sections that are mostly numbers, tables, and benchmarks are
inherently predictable, so they will always score badly. That is fine. Aim at the prose and
do not distort a data-heavy post to chase a number.

**Vary the rhythm. This matters more than everything below it.**

- Sentence length has to swing hard. Write a four word sentence. Then a long one that
  keeps going, stacking clauses until the thought is actually finished. Then a twelve word
  one.
- Never three sentences in a row of similar length.
- Paragraph lengths must be uneven. One line, then eight, then two.
- Do not open every paragraph with a complete grammatical sentence.
- Do not lean on one sentence opener. If "the", "this", or "it" starts more than a handful
  of sentences, rewrite some to start on a verb, a name, or a number.
- Detectors key on exactly this regularity, so a draft with even rhythm fails regardless
  of how good the individual sentences are.

**Break the essay shape.**

- No introduction, three points, conclusion. That symmetry is a machine signature.
- Do not announce what the post will cover. Start inside the problem.
- Do not summarize at the end. Stop when you are done, or finish on what you would do
  differently.
- Not every section needs a heading. A long stretch of prose is allowed, and often better.
- A tangent that does not pay off neatly is fine, as long as it is honest.

**Be specific. This is the strongest human signal.**

- Exact error text, exact filenames, exact versions, exact numbers, the machine it ran on.
- Name what you got wrong, and how long it took you to notice.
- Include at least one detail nobody would invent.
- Replace "a popular library" with the library's name. Replace "much faster" with the
  measured number. Replace "some issues" with the error message.
- If a sentence could appear in any post on this topic, it is not carrying its weight.
  Cut it.

**Let uncertainty and opinion show.**

- "I think", "I am not sure", "this may not hold for your setup" are fine, and they are a
  strong signal, because models default to confident balance.
- Take a position someone could disagree with.
- Do not hedge everything into mush either. Commit where you have actually formed a view.

**Lexicon ban.** These words are so over-represented in model output that they read as a
tell on their own: delve, leverage, robust, seamless, crucial, realm, landscape, tapestry,
navigate, underscore, testament, pivotal, intricate, meticulous, myriad, foster, showcase,
unlock, elevate, "it's worth noting", "at its core", "when it comes to", "in today's",
"that said".

**Voice.** First person, past tense for what happened, present for what is true now.
Write as the developer who did the work. Name the real tool, the real file, the real
error. A reader should be able to tell this was written by someone who hit the problem,
not someone who read about it.

**No em dashes.** Not in the body, not in the title, not in the excerpt, not in the
SVGs. Use a comma, a period, a colon, or parentheses. Before you finish, search the
file for `—` and `–` and remove every one. A hyphen inside a compound word is fine.

**No emojis, no decorative symbols.** No arrows, no bullets made of characters, no
checkmarks, no sparkles anywhere in the prose.

**Straight quotes only.** Type `"` and `'`, never the curly variants. Check code blocks
too, since a smart-quote paste will break them.

**Ban the AI tells.** Read the `humanizer:humanizer` skill and apply it. The ones that
show up most in tech posts:

- The "not X, but Y" contrast. Also "isn't just X, it's Y".
- A punchy one-line paragraph used as a closer after every section.
- Rule-of-three lists where the third item is filler.
- Opening with "In today's fast-paced world" or any scene-setting throat clearing.
- "Let's dive in", "In conclusion", "It's worth noting that", "at the end of the day".
- Bold labels starting every bullet.
- Inflated claims: "seamlessly", "blazingly fast", "game-changing", "effortlessly".
- Em dashes. Already covered, but it is the loudest tell there is.

**No unsourced claims.** If the post states a number, a benchmark, a date, or a
comparison, it needs to be true and it needs to be checkable. Verify it against the
actual source before it goes in. If it cannot be verified, cut the sentence or hedge it
honestly. Do not round a figure up to make a point.

**No lifted phrasing.** Read sources, then close them and write from understanding. If a
sentence comes out close to the source, rewrite it. Do not paraphrase line by line.

**Length.** Roughly 900 to 1800 words. Long enough to actually explain the thing, short
enough that every paragraph earns its place. If a section only restates the previous
one, delete it.

## The clean pass

AI-generated drafts carry invisible junk: zero-width spaces, non-breaking spaces, soft
hyphens, bidi marks, and curly quotes. They survive a copy-paste, break search indexing,
confuse screen readers, and mark the text as machine-written. This pass strips them
before the post is handed over.

Two scripts do the work. Run them from the repo root.

```bash
python Agents/skills/blog-writer/clean.py blog/posts/test.md blog/posts/post.md
python Agents/skills/blog-writer/check.py blog/posts/post.md
```

`clean.py` reads the draft and writes the cleaned post. It removes:

- Zero-width and invisible characters: soft hyphen, zero-width space, zero-width
  non-joiner and joiner, word joiner, byte order mark, and the bidi marks, embeddings,
  overrides, and isolates.
- Non-standard spaces: no-break space, thin space, hair space, ideographic space, and the
  rest of the Unicode space family. Each one becomes a normal space.
- Curly quotes and primes. Each one becomes a straight quote.

It prints what it removed, counted per character.

It leaves en and em dashes alone on purpose, because turning `word — word` into
`word, word` is a writing decision and not a mechanical one. It lists them by line number
instead, and you rewrite them by hand, per the dashes rule above.

`check.py` is the gate. It fails on any invisible character, non-standard space, curly
quote, or dash still in the file, on a frontmatter block that is missing a key or has no
closing delimiter, on a body that opens with `#`, and on unbalanced code fences. Fix only
what it reports, then run it again.

Never hand over a `post.md` that `check.py` has not passed.

## SVG assets

The portfolio is a fixed dark theme. The SVG must match it exactly. Do not invent
colors, do not add a light variant, do not use a gradient that is not listed.

**Palette. Nothing outside this list.**

| Role | Hex |
| --- | --- |
| Deepest background | `#020C1B` |
| Base background | `#0A192F` |
| Surface / panels | `#112240` |
| Borders and rules | `#233554` |
| Accent, used sparingly | `#64FFDA` |
| Heading text | `#CCD6F6` |
| Muted text | `#8892B0` |
| Body text | `#E6F1FF` |

**Typography.** A standalone SVG cannot load the site's webfonts, so use neutral
fallbacks and set them per text element.

- Headings and labels: `font-family="Segoe UI, Helvetica, Arial, sans-serif"`.
- Mono text, kickers, and code: `font-family="Menlo, Consolas, monospace"`.

Do not link a webfont, do not use `@import`, do not reference Manrope or Inter.

**Open `reference/cover-example.svg` before drawing.** It ships inside this skill folder
and is the house style. Copy its construction rather than inventing a new one.

**Rules for every SVG.**

- Pure inline SVG. No `<script>`, no external `<image>`, no remote `href`, no embedded
  base64 raster.
- Root element carries `role="img"` and a real `aria-label` sentence describing the
  picture.
- Background is the site gradient: `#0A192F` to `#112240` to `#0A192F`, running
  top-left to bottom-right at roughly 135 degrees.
- Panels are `#112240` with a `#233554` stroke, `rx` around 16.
- The outer frame is a `#233554` stroke at `stroke-width="2"` with `rx="18"`.
- Accent `#64FFDA` is a highlight, never a large fill. Where it needs to cover area, drop
  its `opacity` to about 0.5 to 0.7.
- Soft depth comes from a blurred `#64FFDA` circle at about `opacity="0.06"` behind the
  content, using a `feGaussianBlur` filter. Nothing brighter.
- Text has real `<text>` elements, never paths, so it stays selectable and sharp.

**The cover thumbnail.** Always produced, even for a short post.

- `1200x675` with `viewBox="0 0 1200 675"`, which is the 16:9 box the card renders it in.
  Any other ratio gets cropped.
- A mono kicker in `#64FFDA`, roughly 22px with `letter-spacing` around 6, sitting above
  the title. Two or three words, the post's topic or primary tag.
- The title in `#CCD6F6` at about 46px weight 700, broken across at most two or three
  lines by hand, not by wrapping. Accent one phrase inside it with a `<tspan>` in
  `#64FFDA`.
- Optionally one simple diagram under the title, built from rounded rects and a dashed
  connector. Keep it to a few shapes.
- Caption lines in `#8892B0` at the bottom, in mono around 15px.
- It has to stay legible as a small card on the blog list. No dense diagrams, no
  paragraphs of text.

**Inline figures.** Only draw one when the post describes something that is genuinely
harder to explain in prose: a request flow, a data shape, a before-and-after. Skip them
otherwise. Same palette, `viewBox` sized to the content rather than a fixed ratio, and
referenced from the markdown by its absolute URL.

## Measure before you hand over

Rhythm and contractions are the only parts of this you can check with a number, so check
them instead of guessing.

```bash
python Agents/skills/blog-writer/measure.py blog/posts/test.md
python Agents/skills/blog-writer/measure.py --selftest
```

The splitter only ends a sentence when punctuation is followed by whitespace and the next
sentence opens with a capital, a digit, or a bracket. That is what keeps `4.68`, `0.042`,
`measure.py`, and `0xarchit.is-a.dev` in one piece. Run `--selftest` if you ever suspect
the script, it checks those cases and exits non-zero on a failure. Every number below is
only worth reading if that passes.

It reports sentence count and mean length, burstiness as a coefficient of variation, the
length distribution, paragraph variance, type-token ratio, hapax ratio, common-word rate,
repeated 4-grams, repeated content words, adverb density, nominalization density,
contraction rate, hedge and transition density, banned-lexicon hits, and the most repeated
sentence openers. Then it prints a verdict for each line.

How to read it:

- **Burstiness above 0.65**, and **under 30% of sentences in the 11 to 20 word band**.
  Below that the prose is too even, which is exactly what gets flagged.
- **One contraction every 40 to 60 words.** If `uncontracted` outnumbers `contractions`,
  you left the biggest lever on the floor.
- **No repeated 4-grams, and no content word past six uses.** A word used nineteen times in
  a 1700 word post is what a reader notices, and repetition is a cheap signal to catch.
- **Adverb `-ly` under 3%, nominalization under 6%.** Both are formal-writing habits that
  models lean on. Prefer a plain verb to a noun built out of one.
- **No banned-lexicon hits**, and no single opener past six sentences.

True perplexity needs a language model, so the vocabulary block is a proxy and only
directional. The rhythm and contraction numbers are exact.

### The terms file

The tell lists are deliberately fixed, because a measurement that writes its own yardstick
measures nothing. Repetition is different. In a post about decision models, the word
"model" appearing nineteen times is the subject, not a tell, and a fixed list cannot know
that.

So you may drop a sidecar next to the draft. The script picks it up automatically at
`blog/posts/<name>.terms.json`, or you can pass a path as the second argument.

```json
{
  "topic_terms": ["model", "calibration", "classifier"],
  "watchlist": ["in practice", "near random"]
}
```

- **`topic_terms`** are excused from the repeated-word count and from the nominalization
  density. They are still reported, under `topic terms, expected`, so the count stays
  visible and nothing is hidden.
- **`watchlist`** is extra terms to count. Use it for phrasing you know this draft leans
  on. It can only add scrutiny, never remove it.

Write the terms file before you run the measurement, and delete it with `test.md` when you
are done. Without it the script says so and measures against the fixed lists alone.

The guard, and it is enforced in code: `topic_terms` cannot silence a fixed list. Banned
lexicon, hedges, and transitions are counted whatever the sidecar says, so an allowlist can
excuse a repeated topic noun and nothing else. Putting a tell in `topic_terms` does not
work.

This is not a gate. A code-heavy or benchmark-heavy stretch will legitimately read even,
and the script does not exit non-zero.

## Workflow

1. Run the preflight check. If `humanizer:humanizer` is not loaded, stop and hand the
   user the install commands. Nothing else happens until it is installed.
2. Understand the subject first. Read the real sources, the real code, the real error.
3. Write the draft to `blog/posts/test.md`, frontmatter first.
4. Run the `humanizer:humanizer` pass over the body. This step is mandatory, not optional.
5. Write `blog/posts/test.terms.json` naming this article's topic terms, then run
   `measure.py` on the draft and fix what it flags. Repeat until the contraction rate,
   burstiness, and sentence distribution are in range. Do this before the clean pass, since
   every edit after it means running the other scripts again.
6. Draw `blog/posts/<slug>-cover.svg`, plus any figure SVGs. Match
   `reference/cover-example.svg` from this skill folder.
7. Run `clean.py` to produce `blog/posts/post.md` from the draft.
8. Run `check.py` on `post.md`. Fix only what it reports, then run it again until clean.
   Run the check before deleting `test.md` so a mismatch is still debuggable.
9. Delete `blog/posts/test.md` and `blog/posts/test.terms.json`.
10. Hand over `post.md` and report its frontmatter values, so they can be pasted into the
    studio.

Before handing over, confirm by hand. The character checks are `check.py`'s job, these
are the ones it cannot do:

- Every number and claim is verified.
- Excerpt is 120 to 160 chars.
- Every color in every SVG is in the palette table.
- The dashes `clean.py` listed have all been rewritten.
