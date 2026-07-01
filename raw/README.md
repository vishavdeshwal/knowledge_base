# raw/

Staging area for source material that hasn't been synthesized into the wiki yet.
This is the "ingest" half of the workflow described in Andrej Karpathy's
[LLM Knowledge Bases](https://karpathy.bearblog.dev/) note: `raw/` holds untouched
sources, the numbered folders (`01-concept/` … `06-incidents/`) hold the compiled,
categorized, linked wiki.

## What goes here

- Web clips (Obsidian Web Clipper output — keep the clip and its downloaded images together)
- Papers / PDFs / docs pulled from vendor sites
- Exported logs, config dumps, terminal transcripts from a session worth preserving
- Anything you'd otherwise paste into a chat once and lose

## Structure

No fixed taxonomy — organize by source, not by destination:

```
raw/
  <topic-or-client>/
    <source-name>/
      article.md          # the clip/export itself, mostly as-downloaded
      images/              # any images the source references
```

Don't pre-categorize into 01-06 style folders here — that decision happens during
compile, once the content is actually read.

## Lifecycle

1. Drop the source here (manually, or via Obsidian Web Clipper)
2. Run `/kb-compile` (see `AI/commands/kb-compile.md`) to have it read, categorized,
   and written into the wiki with a `source:` backlink to the original file here
3. The raw file **stays** — it's the citation trail, not a temp file. Treat this
   directory as read-only once something lands in it; edit the compiled article
   in the wiki instead, not the source.

## Rules

- Never edit files in here to "clean them up" — if a source is noisy, that's a
  compile-time filtering decision, not a raw-file edit
- Large binaries (video, big datasets) are fine here but consider `.gitignore`-ing
  them if they'd bloat the repo — the compiled *summary* in the wiki is what
  actually needs to survive
