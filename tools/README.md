# tools/

Small, dependency-free scripts (stdlib-only Python 3) that an LLM agent — or you
— can call directly instead of grepping the whole vault by hand. This is the
"extra tools" piece of the Karpathy LLM-knowledge-base workflow: a naive search
engine over the wiki, used both directly and as a CLI tool handed to an agent.

## kb_search.py

Term-frequency search over every `.md` file in the wiki (excludes `raw/`,
`Images/`, `.obsidian/`, `health-reports/`, `outputs/` by default).

```bash
python3 tools/kb_search.py rds slow queries
python3 tools/kb_search.py "crashloop" --path 02-playbooks
python3 tools/kb_search.py cloudfront --all
```

## kb_lint.py

Wiki health check — broken `[[wikilinks]]`, broken relative links/image embeds,
placeholder/stub files, and notes with zero wikilink connections.

```bash
python3 tools/kb_lint.py
python3 tools/kb_lint.py --out 00-index/wiki-health/2026-07-01-wiki-health.md
```

See `AI/commands/kb-search.md` and `AI/commands/kb-lint.md` for the agent-facing
workflow built on top of these two scripts.
