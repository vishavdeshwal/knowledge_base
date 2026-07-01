#!/usr/bin/env python3
"""
Wiki health check for the knowledge base.

Scans every .md file (outside raw/) and reports:
  - broken [[wikilinks]]              (target note doesn't exist)
  - broken relative links/images      ([text](path) / ![alt](path) that don't resolve)
  - placeholder / stub files          (test.txt, near-empty .md files)
  - isolated notes                    (zero wikilinks in or out — informational, not an error)

Dependency-free (stdlib only). This is the "linting" step of the Karpathy
LLM-knowledge-base workflow: find inconsistent/missing data so an LLM agent
can fix what's safe and flag what needs a human decision.

Usage:
    python3 tools/kb_lint.py [--out 00-index/wiki-health/2026-07-01-wiki-health.md]
"""
import argparse
import os
import re

EXCLUDE_DIRS = {".git", ".obsidian", "raw", "tools", "health-reports"}
WIKILINK_RE = re.compile(r"\[\[([^\]|#]+)(?:[|#][^\]]*)?\]\]")
MDLINK_RE = re.compile(r"!?\[[^\]]*\]\(([^)\s]+)\)")
PLACEHOLDER_NAMES = {"test.txt"}
PLACEHOLDER_MAX_BYTES = 20
SKIP_ISOLATION_NAMES = {"readme.md", "syntax.md"}


def iter_files(root, exts=None):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in EXCLUDE_DIRS and not d.startswith(".")]
        for f in filenames:
            if exts is None or f.lower().endswith(exts):
                yield os.path.join(dirpath, f)


def build_title_index(md_files, root):
    index = {}
    for path in md_files:
        stem = os.path.splitext(os.path.basename(path))[0]
        index.setdefault(stem.lower(), []).append(os.path.relpath(path, root))
    return index


def find_link_issues(md_files, root, title_index):
    broken_wikilinks = []
    broken_asset_links = []
    outbound = {}
    inbound = {}

    for path in md_files:
        rel = os.path.relpath(path, root)
        outbound.setdefault(rel, set())
        try:
            with open(path, "r", encoding="utf-8", errors="ignore") as fh:
                lines = fh.readlines()
        except OSError:
            continue

        in_code_fence = False
        for lineno, line in enumerate(lines, 1):
            if line.lstrip().startswith("```"):
                in_code_fence = not in_code_fence
                continue
            if in_code_fence:
                continue

            for m in WIKILINK_RE.finditer(line):
                target = m.group(1).strip()
                key = os.path.basename(target).lower()
                if key not in title_index:
                    broken_wikilinks.append((rel, lineno, target))
                else:
                    outbound[rel].add(target)
                    for t in title_index[key]:
                        inbound.setdefault(t, set()).add(rel)

            for m in MDLINK_RE.finditer(line):
                target = m.group(1).strip()
                if target.startswith(("http://", "https://", "mailto:")) or target.startswith("#"):
                    continue
                target_clean = target.split("#")[0]
                if not target_clean:
                    continue
                candidates = [
                    os.path.normpath(os.path.join(os.path.dirname(path), target_clean)),
                    os.path.normpath(os.path.join(root, target_clean)),
                ]
                if not any(os.path.isfile(c) for c in candidates):
                    broken_asset_links.append((rel, lineno, target))

    return broken_wikilinks, broken_asset_links, outbound, inbound


def find_placeholders(root):
    placeholders = []
    for path in iter_files(root):
        name = os.path.basename(path)
        rel = os.path.relpath(path, root)
        if name in PLACEHOLDER_NAMES:
            placeholders.append(rel)
        elif name.lower().endswith(".md") and os.path.getsize(path) <= PLACEHOLDER_MAX_BYTES:
            placeholders.append(rel)
    return placeholders


def find_isolated_notes(md_files, root, outbound, inbound):
    isolated = []
    for path in md_files:
        rel = os.path.relpath(path, root)
        if os.path.basename(rel).lower() in SKIP_ISOLATION_NAMES:
            continue
        if not outbound.get(rel) and not inbound.get(rel):
            isolated.append(rel)
    return isolated


def render_report(md_files, broken_wikilinks, broken_asset_links, placeholders, isolated):
    out = []
    out.append("# Wiki Health Report\n\n")
    out.append(f"Scanned {len(md_files)} markdown files.\n")

    out.append("\n## Broken wikilinks\n\n")
    if broken_wikilinks:
        for rel, lineno, target in broken_wikilinks:
            out.append(f"- `{rel}:{lineno}` -> `[[{target}]]` has no matching note\n")
    else:
        out.append("None found.\n")

    out.append("\n## Broken links / image embeds\n\n")
    if broken_asset_links:
        for rel, lineno, target in broken_asset_links:
            out.append(f"- `{rel}:{lineno}` -> `{target}` does not resolve\n")
    else:
        out.append("None found.\n")

    out.append("\n## Placeholder / stub files\n\n")
    if placeholders:
        for rel in placeholders:
            out.append(f"- `{rel}`\n")
    else:
        out.append("None found.\n")

    out.append("\n## Isolated notes (no wikilinks in or out)\n\n")
    if isolated:
        out.append(
            f"{len(isolated)} notes have zero `[[wikilink]]` connections. Informational only — "
            "most existing notes predate the wikilink convention, this is not a defect by itself.\n\n"
        )
        for rel in isolated[:50]:
            out.append(f"- `{rel}`\n")
        if len(isolated) > 50:
            out.append(f"- ...and {len(isolated) - 50} more\n")
    else:
        out.append("None found.\n")

    return "".join(out)


def main():
    ap = argparse.ArgumentParser(description="Knowledge base wiki health check")
    ap.add_argument(
        "--root",
        default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        help="knowledge base root (default: repo root this script lives in)",
    )
    ap.add_argument("--out", default=None, help="write report to this file instead of stdout")
    args = ap.parse_args()

    root = args.root
    md_files = list(iter_files(root, (".md",)))
    title_index = build_title_index(md_files, root)

    broken_wikilinks, broken_asset_links, outbound, inbound = find_link_issues(md_files, root, title_index)
    placeholders = find_placeholders(root)
    isolated = find_isolated_notes(md_files, root, outbound, inbound)

    report = render_report(md_files, broken_wikilinks, broken_asset_links, placeholders, isolated)

    if args.out:
        out_dir = os.path.dirname(args.out)
        if out_dir:
            os.makedirs(out_dir, exist_ok=True)
        with open(args.out, "w", encoding="utf-8") as fh:
            fh.write(report)
        print(f"Report written to {args.out}")
    else:
        print(report)


if __name__ == "__main__":
    main()
