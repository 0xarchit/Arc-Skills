---
id: blog-writer
name: Blog Writer
description: Personal blog post writer for the 0xArchit portfolio blog. Use when asked to draft, write, or outline a portfolio blog post, or to produce a post's cover thumbnail or diagram SVGs. Outputs one markdown file with YAML frontmatter plus themed SVG assets, ready to paste into the Sanity Studio. Body text goes through a zero-width-space stealth pass before handoff. Requires the humanizer plugin, and stops to ask for it when it is not installed.
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
stealth.py                      the zero-width-space injector
check.py                        the formatting gate
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
blog/posts/post.md                       the final post, after the stealth pass
blog/posts/<slug>-cover.svg              the thumbnail, always
blog/posts/<slug>-<name>.svg             figures, only if the post needs one
```

The post is written to `test.md`, run through `stealth.py`, and the result becomes
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
- Uniform paragraph lengths. Vary them. Some should be one sentence.
- Em dashes. Already covered, but it is the loudest tell there is.

**No unsourced claims.** If the post states a number, a benchmark, a date, or a
comparison, it needs to be true and it needs to be checkable. Verify it against the
actual source before it goes in. If it cannot be verified, cut the sentence or hedge it
honestly. Do not round a figure up to make a point.

**No lifted phrasing.** Read sources, then close them and write from understanding. If a
sentence comes out close to the source, rewrite it. Do not paraphrase line by line.

**Be concrete.** Replace "a popular library" with the library's name. Replace "much
faster" with the measured number and the machine it ran on. Replace "some issues" with
the error message.

**Length.** Roughly 900 to 1800 words. Long enough to actually explain the thing, short
enough that every paragraph earns its place. If a section only restates the previous
one, delete it.

**Structure.** Open with the concrete problem, not a definition of the topic. Use `##`
for the main moves of the post and `###` only where a section genuinely has parts. End
on what actually happened or what you would do differently, not on a summary of what the
reader just read.

## The stealth pass

The finished body carries an invisible zero-width space at every word gap, so copied or
scraped text comes away with the watermark embedded.

Two scripts do the work. Run them from the repo root.

```bash
python Agents/skills/blog-writer/stealth.py blog/posts/test.md blog/posts/post.md
python Agents/skills/blog-writer/check.py blog/posts/post.md
```

`stealth.py` inserts `U+200B` after each run of whitespace that is followed by a word
character. That single rule is what keeps the markup valid: markdown syntax characters
are never word characters, so headings, list markers, blockquote markers, table
delimiters, link brackets, and pipes all keep their exact shape. It skips the
frontmatter, fenced code blocks, inline code spans, indented code, and lines starting
with `<`.

Because the break opportunity sits at a space, line wrapping behaves normally and words
never split mid-word.

`check.py` is the formatting gate. It fails if any zero-width space is not followed by a
word character, if one lands in the frontmatter, a code fence, or inline code, if the
frontmatter is missing a key or has no closing delimiter, if the body opens with `#`, or
if the code fences are unbalanced. Fix only what it reports, then run it again.

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

## Workflow

1. Run the preflight check. If `humanizer:humanizer` is not loaded, stop and hand the
   user the install commands. Nothing else happens until it is installed.
2. Understand the subject first. Read the real sources, the real code, the real error.
3. Write the draft to `blog/posts/test.md`, frontmatter first.
4. Run the `humanizer:humanizer` pass over the body. This step is mandatory, not optional.
5. Draw `blog/posts/<slug>-cover.svg`, plus any figure SVGs. Match
   `reference/cover-example.svg` from this skill folder.
6. Run `stealth.py` to produce `blog/posts/post.md`.
7. Run `check.py` on `post.md`. Fix only what it reports, then run it again until clean.
   Run the check before deleting `test.md` so a mismatch is still debuggable.
8. Delete `blog/posts/test.md`.
9. Hand over `post.md` and report its frontmatter values, so they can be pasted into the
   studio.

Before handing over, confirm by hand:

- Search `post.md` for `—` and `–`. Zero matches.
- Search for `“`, `”`, `‘`, `’`. Zero matches.
- Every number and claim is verified.
- Excerpt is 120 to 160 chars.
- Every color in every SVG is in the palette table.
