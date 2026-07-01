#!/usr/bin/env python3
"""
Naive full-text search over the knowledge base wiki.

Dependency-free (stdlib only) so it runs anywhere python3 runs. Scores files by
term frequency, with boosts for matches in the filename or first heading. This
is the "small naive search engine" from the Karpathy LLM-knowledge-base workflow —
meant to be called by an LLM agent (or by hand) instead of grepping the whole
tree for every query.

Usage:
    python3 tools/kb_search.py <query terms...> [--path 01-concept] [--limit 10] [--all]
"""
import argparse
import os

EXCLUDE_DIRS = {".git", ".obsidian", "raw", "tools", "Images", "health-reports", "outputs"}


def iter_md_files(root, include_raw=False, path_filter=None):
    exclude = set(EXCLUDE_DIRS)
    if include_raw:
        exclude.discard("raw")
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in exclude and not d.startswith(".")]
        if path_filter:
            rel_dir = os.path.relpath(dirpath, root)
            if not (rel_dir == path_filter or rel_dir.startswith(path_filter + os.sep)):
                continue
        for f in filenames:
            if f.lower().endswith(".md"):
                yield os.path.join(dirpath, f)


def score_file(path, root, terms):
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as fh:
            lines = fh.readlines()
    except OSError:
        return None

    text = "".join(lines).lower()
    rel = os.path.relpath(path, root)
    filename = os.path.basename(path).lower()
    heading = ""
    for line in lines:
        if line.strip().startswith("#"):
            heading = line.strip().lstrip("#").strip().lower()
            break

    score = 0
    for term in terms:
        t = term.lower()
        if t in filename:
            score += 10
        if t in heading:
            score += 5
        score += text.count(t)

    if score <= 0:
        return None

    snippets = []
    for i, line in enumerate(lines, 1):
        low = line.lower()
        if any(term.lower() in low for term in terms):
            snippets.append((i, line.strip()))
        if len(snippets) >= 3:
            break

    return {"path": rel, "score": score, "snippets": snippets}


def main():
    ap = argparse.ArgumentParser(description="Naive term-frequency search over the knowledge base wiki")
    ap.add_argument("query", nargs="+", help="search terms — each term's occurrences add to a file's score")
    ap.add_argument("--path", default=None, help="scope search to a subfolder, e.g. 01-concept")
    ap.add_argument("--limit", type=int, default=10, help="max results to show (default 10)")
    ap.add_argument("--all", action="store_true", help="show all matches, ignoring --limit")
    ap.add_argument("--include-raw", action="store_true", help="also search raw/ (excluded by default)")
    ap.add_argument(
        "--root",
        default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        help="knowledge base root (default: repo root this script lives in)",
    )
    args = ap.parse_args()

    results = []
    for path in iter_md_files(args.root, include_raw=args.include_raw, path_filter=args.path):
        r = score_file(path, args.root, args.query)
        if r:
            results.append(r)

    results.sort(key=lambda r: r["score"], reverse=True)
    if not args.all:
        results = results[: args.limit]

    if not results:
        print(f"No matches for: {' '.join(args.query)}")
        return

    for r in results:
        print(f"\n{r['path']}  (score {r['score']})")
        for lineno, snippet in r["snippets"]:
            print(f"  {lineno}: {snippet[:160]}")


if __name__ == "__main__":
    main()
