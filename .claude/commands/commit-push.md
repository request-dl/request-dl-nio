---
description: Commits the current changes using Conventional Commits, with optional push
---

Analyze the current repository changes and make a commit following these steps:

1. Run `git status` and `git diff` (or `git diff --staged` if there are already staged changes).
2. Show me a summary of what will be committed and wait for my confirmation.
3. Before committing, run:
   `swift format format --in-place --recursive Sources Tests`
   and include any formatting changes in the commit.
4. Stage the relevant files with `git add` (avoid a blind `git add .` if there are unrelated files).
5. Write the commit message in Conventional Commits format, in English, for example:
   - `fix: resolve cache race condition in tests`
   - `test: extract awaited values from #expect macros`
   - `chore: apply swift format`
6. If there are changes of different natures, suggest splitting them into separate commits.
7. Do NOT run `git push` automatically. Ask me whether I want to push, and if I confirm, run `git push origin HEAD`.