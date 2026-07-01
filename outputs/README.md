# outputs/

Landing zone for generated visual artifacts from Q&A / analysis sessions — the
"Output" step of the Karpathy LLM-knowledge-base workflow. Terminal text answers
don't go here; things meant to be *viewed* do.

## Structure

```
outputs/
  slides/   # Marp markdown decks (--- marp: true --- front matter)
  charts/   # matplotlib-generated PNGs / SVGs
```

## Conventions

- Name files after the question/topic they answer, not a timestamp:
  `ecs-cost-breakdown.png`, not `chart1.png`
- If an output is worth keeping, file a link/embed to it from the relevant wiki
  article (01-06) — an output sitting alone in this folder with nothing pointing
  to it is exactly what `/kb-lint` flags as isolated
- Viewing Marp decks: either `npx @marp-team/marp-cli slides/<file>.md -o out.pdf`,
  or install the Marp community plugin in Obsidian (Settings → Community plugins
  → Marp) — not installed by default since this vault runs in restricted mode
- One-off exploratory charts that didn't lead anywhere are fine to delete; don't
  let this folder become a dumping ground with no wiki backlinks
