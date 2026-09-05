# Security policy

Roman War is a single-player, offline desktop game. It has no server, no
accounts, no network calls at runtime, and it stores nothing but local save
files. The realistic security surface is therefore small — but it is not empty,
and reports are welcome.

## What is worth reporting

- Anything that lets a **crafted save file or data table** run code, escape the
  save directory, or overwrite files outside the game's own storage.
- A **secret, credential or personal datum** that has been committed to this
  repository or is exposed in its history.
- A weakness in the **GitHub Actions workflows** — for example a way for a pull
  request from a fork to obtain write access, exfiltrate a token, or poison a
  build cache.
- Anything in the **build and export pipeline** that could cause a published
  build to ship something it should not.

Ordinary game bugs, crashes and balance complaints are not security issues.
Please open a normal issue for those.

## How to report

**Do not open a public issue for a security report.**

Use GitHub's private reporting: go to the repository's **Security** tab →
**Report a vulnerability**. That opens a private advisory visible only to the
maintainer. If private reporting is unavailable, contact @zhynek through their
GitHub profile and ask for a private channel before sharing details.

Please include what you found, how to reproduce it, and what an attacker could
actually do with it. A proof of concept helps.

## What to expect

This is a hobby project maintained by one person, so there is no paid bounty and
no formal response-time guarantee. What you will get: an acknowledgement, an
honest assessment of severity, and credit in the fix unless you prefer not to be
named. Please give a reasonable window to fix an issue before disclosing it
publicly.

## Supported versions

Only the current `main` branch is supported. There are no maintained release
branches, and fixes are not backported.
