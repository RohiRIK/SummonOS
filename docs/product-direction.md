---
type: Plan
title: Product direction and roadmap
description: "An accessible Mac agent companion: current onboarding, proposed improvements and measurable release gates for three audiences."
tags: [product, roadmap, onboarding, acceptance]
status: proposed
created: 2026-11-12
---

# Product direction and roadmap

**One product, three starting points:** connect an agent, understand/control your Mac, or build a native app.
SummonOS should serve existing coding-agent users, developers making native Mac apps with AI, and
nontechnical Mac users. No group should need to understand the whole toolchain before their first useful action.
This is a proposed direction, not a claim that broad nontechnical usability is already proven.

## Current source versus future work

The base version is 0.2.5; the latest numbered public release checked on 2026-11-12 is v0.2.5 (prerelease).
Source implementation, published availability, and acceptance are separate. See [status](status.md).

Source already provides a four-step welcome flow: introduction, installed-agent selection/account status,
Accessibility, and a live panel try-it step. It is skippable and reopenable through Settings → General →
Show Welcome Again. This is implemented in `OnboardingView.swift`; do not propose building it from scratch.
Settings, CLI and connection tools offer power-user paths, while nine templates support native app creation.
These source capabilities still need fresh acceptance on the chosen candidate.

| Starting point | Existing path | Gap to validate or address next |
|---|---|---|
| I already use an agent | Welcome agent picker, login checks, CLI connection and context visibility | Explain launch versus connection; offer one inspection-only first success and show exactly what context was shared |
| I want to build a Mac app | Native starters, private project list, build/repo tooling | Lead from an app idea to one working local template before introducing repository/publication choices |
| I am not technical | Native welcome, panel, Settings, permission guidance | Terminal installation and agent setup remain barriers; test clear no-agent/error states and plain-language dependency explanations |

## Proposed first success

1. Explain that this is a preview and that a separate agent account/provider may cost money. Summon does not supply a model.
2. Detect whether an agent is ready. Reuse the current picker/login status; explain missing prerequisites without silently installing tools.
3. Explain permission scope before the user opens System Settings. Skipping must remain useful; never claim a grant was made automatically.
4. Show one read-only context request, the fields allowed, and where to change sharing. Preserve the agent's own approval controls by default.
5. End at the existing live panel try-it step. Offer app building, themes and scheduling afterward, not as mandatory setup.

Downloaded provenance adds a current usability constraint: this candidate needs recent `gh` and working GitHub
access. Future packaging must preserve fail-closed verification rather than remove it to shorten onboarding.
A graphical verified-download path is a proposal requiring design and implementation, not an existing feature.

## Ordered roadmap and done conditions

| Priority | Work | Done when |
|---|---|---|
| P0 — candidate integrity | Combine security/manual/site work; reconcile installation instructions and help; test the exact source | Reproducible local tests, strict rendered-link build and independent review pass; exact-head macOS checks are recorded separately |
| P0 — real-Mac acceptance | Use the [Mac checklist](mac-acceptance.md) on the pinned candidate | Installation, identity, denied/granted context, one agent connection and native UI results are recorded, with blocked update paths explicit |
| P1 — first-user clarity | Validate the three entry paths above and improve only observed obstacles | At least one tester from each audience completes an inspection-only first action without facilitator intervention; record time and failures, not invented targets as measurements |
| P1 — trustworthy delivery | Prepare a numbered preview and evaluate signing/notarization | Source/artifact identity, provenance, upgrade/recovery and owner publication approvals are recorded; do not imply notarization without a verified artifact |
| P2 — broader qualification | Close profiling, memory, native notification and accessibility gaps | Fresh evidence closes each named gate in [status](status.md); until then retain the preview/non-production label |

Release preparation can proceed while real-Mac tests are pending. Production qualification cannot.
Avoid making every profiler gap a claim that a preview cannot be prepared; distinguish preview publication
criteria from the stronger production claim. No dates or acceptance results are promised here.

## Boundaries

- Keep native Settings separate from the panel. Preserve CLI/source/edge options for experienced users.
- Do not auto-connect all agents, enable unattended execution, buy accounts or create repositories as onboarding defaults.
- Existing user settings can retain prior execution choices; do not silently reset them.
- Checkpoints cover supported captured state, not arbitrary agent actions or a whole-Mac backup.
- Merging, website deployment and app release publication remain separate owner decisions.

[Release preparation](release-candidate.md) · [Current features](features.md) · [Security model](security-model.md)
