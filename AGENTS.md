# Agent guidelines

Instructions for any AI coding agent working in this repository. `CLAUDE.md` is a symlink to this file.

## No agent attribution

Do not attribute work to an AI agent anywhere in this repository or its history. Specifically:

- Never add `Co-Authored-By`, `Claude-Session`, "Generated with", or similar trailers or footers to commit messages.
- Never mention an agent, model, or AI tool in commit messages, pull request titles or descriptions, release notes, code comments, or documentation.
- Commits are authored solely by the configured Git user.

## Working in this repository

- Read `DEVELOPMENT.md` before building or releasing. Releases are cut only through `./publish-release.sh`.
- Never commit signing material or credentials. See the secrets table in `DEVELOPMENT.md`.
- Keep the release launcher tests in `Tests/ReleaseTests.py` version-agnostic; they run against the current bundle version.
