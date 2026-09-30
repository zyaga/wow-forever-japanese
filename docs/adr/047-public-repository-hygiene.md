# ADR-047: Public repository hygiene: what stays private, and the checks that keep it so

- **Status:** Accepted
- **Date:** 2026-09-29

## Context

The repository is public, starting from a single commit of the tree: nothing from the working history before it
reaches the public record. Some of the material around it is not written for a contributor: planning notes, the
working files of the translation batches, drafts for the listing. Comments, docs and data notes are also easier
to keep current when they describe the code as it is, not how it came about.

A one-time clean-up does not stay clean. The rules need a check that runs on every pull request.

## Decision

1. **Private material lives outside the repository.** It is kept in a private folder and linked into a checkout.
   A checkout that holds such links lists them in the git folder's `info/exclude`, the ignore list git never
   publishes, in one block headed "Private project internals". `wfj public-check paths` reads that block and
   fails if any tracked file sits under one of its entries, including a force-added one. An entry holds no glob
   character, because entries are compared literally. No tracked file is a symlink, because a link would publish
   the path it points to. A clone without the block has nothing to compare and checks symlinks only.
2. **`wfj public-check content`** scans every tracked file for paths on the author's machine (home folders,
   external drives) and for ids of the project's own issue tracker (an issue here is `#N`). Its other rules are
   private: patterns, words, names and addresses that must not be
   published are read from a rules file outside the repository (`$WFJ_PRIVATE_RULES`, or
   `info/public-check-private.json` in the git folder, which every worktree shares). The repository holds the
   mechanism and never the list, in any form: a list of hashes of short words can be reversed by guessing. A
   checkout without a rules file checks the public rules and says so. A checkout that lists private paths must
   have the rules file; `paths` fails without it. A rules file that cannot be read stops the run.
3. **Comments explain, they do not record history.** `wfj public-check comments` fails on a comment or docstring
   that holds a person, a date, an approval, a label from an earlier review (a numbered finding, a severity
   code) or a ruling label, and on whatever the private rules name for comments. It reads Lua and Python comments
   and docstrings, `#` comments in YAML, TOML, shell, the `Makefile`, `.pkgmeta`, `.gitignore` and the pipeline's
   `.txt` / `.tsv` lists, and `--` comments in `.luacheckrc`, `.luacov` and the TOC. The reasons behind the
   rules the addon keeps are stated once, in [principles](../architecture/principles.md).
4. **Links resolve and images are fit to publish.** `wfj public-check links` fails on a relative Markdown link,
   image or reference-style link definition to a file that is not in the repository (fenced code is skipped);
   `wfj public-check images` requires alt text and a 300 KB limit on the images of the README and the CurseForge
   description, and fails on an image under `docs/images/` that carries a metadata block able to hold text
   (camera, software, dates, locations).
5. **Data notes follow the same rules.** A provenance note records what was decided about a line and why ("the
   maintainer ruled the hand-written line `reject`"). Batch names in provenance `source` fields name the batch's
   topic. A model identifier in `data/` provenance is a fact about that line and stays.
6. **Every pull request is checked.** `make lint` runs all of the above; CI also runs `wfj public-check pr` over the
   pull request's title, body, branch name and commit messages. It reads the title and body from the Actions
   event file and the branch from `GITHUB_HEAD_REF`, so no pull request text passes through the workflow's
   script text, and it requires a GitHub noreply address on every commit's author and committer. It runs as a
   job of its own, on every edit of the text too; the code checks skip the edit event. CI has no rules file, so
   it runs the public rules; the private rules run where the rules file is, through `make lint`, before a push.

## Consequences

- Contributors see material written for them.
- A pull request that brings back a private link, a path on someone's machine or a history comment fails CI with
  the file and line.
- The repository cannot be searched for what the private rules look for.
- A change pushed from a checkout without the rules file is checked against the public rules only. The rules
  file therefore travels with the private folder, and a checkout that links the private folder fails `paths`
  until the file is in place.
- The translation batch tooling still works locally: it reads and writes the linked private folder.
