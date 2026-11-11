---
type: Plan
title: Commit-aligned documentation wiki
description: "Convert canonical project Markdown into a complete searchable website and refresh current contracts against the November source baseline."
tags: [documentation, website, wiki, verification]
status: complete
created: 2026-11-11
---

# Commit-aligned documentation wiki

## Requirements

- Update project documentation against the commits and current implementation.
- Deliver a full website, like a wiki: searchable, navigable and usable on desktop and mobile.
- Keep current product behavior distinct from proposed work and historical verification evidence.

## Decisions and scope

Baseline: `18c7688`, marketing version `0.2.4`. GitHub release metadata checked November 11 identifies
`v0.2.4` (October 28) as the newest numbered prerelease; November branch fixes are unreleased.

Use MkDocs Material with docs-only Python dependencies. Existing Markdown is canonical: stage selected public
sources without moving them or maintaining a second copy. Include root/project guides, the full `docs/`
knowledge base, component docs and template READMEs. Repository-only files stay linked on GitHub.

Do not rewrite historical measurements as fresh results, edit vendored skills, audit absent plugin repos,
install a new app build, publish a release or change repository Pages settings. Pages API lookup returned
HTTP 404; deployment requires the maintainer's GitHub Pages configuration and a merged workflow.

## Work

1. Audit current root, Summon, macctl, feature, installation, security, tool and contributor documentation
   against source/commit history. Preserve historical terminal captures and dated research/plans.
2. Add a wiki entry page, first-use guide, troubleshooting and source-versus-release status. Correct version,
   agent/MCP, recovery, update, inventory, theme and build/CI drift in existing references.
3. Add grouped navigation, search, theme switching, responsive layout, code formatting, diagram rendering,
   GitHub source/edit links and automatically discoverable archives.
4. Provide strict builds, local preview, rendered link/anchor/asset checking, OKF index regeneration and a
   GitHub Pages workflow with deployment separated from pull-request validation.

## Acceptance

- Current guides describe implemented behavior without claiming unreleased changes shipped.
- All selected public pages are discoverable; internal links, anchors and images resolve in the built site.
- Desktop/mobile navigation, search, light/dark and diagram rendering are exercised in a browser.
- Build outputs, Python dependencies and temporary sources remain outside the synced checkout.
- Existing OKF indexes are regenerated, not edited by hand.

## Verification

The strict MkDocs build passed for **65 public Markdown documents**, including rendered local links, heading
anchors and assets. Four standard-library link regressions passed: escaped delimiters, literal code examples,
relocated raw HTML/reference links, and missing/outside targets. No Swift runtime test or app install ran.

Browser evidence: desktop at 1440 × 1000 and mobile at 390 × 844; desktop search returned 23 matches for
`checkpoint`, mobile search returned 22 for `accent`. Exercised the mobile drawer, nested Start here section
and Getting started route. Inspected light/dark content, a rendered Mermaid architecture diagram, historical
notices and correct source/edit links. All seven images on Summon's overview loaded. The inspected mobile
guide had no document-level horizontal overflow.

Integration fixed an unsupported search option, source-link rewriting after escaped backticks, stale research
heading links, one historical skill link and unescaped label placeholders. The preview now watches canonical
sources instead of repeatedly rebuilding from its own generated staging changes.

The Python environment, staging and HTML output stayed outside the checkout. The OKF indexes were regenerated.
GitHub Pages publication remains a maintainer setup/deployment action; no live-site or native app release
qualification is claimed.

## Visual design pass (2026-11-11)

The owner asked for a distinctive UX/UI rather than a stock, table-led wiki. The resulting field guide keeps
the same canonical documents and native Material interactions, with no new frontend dependencies or JavaScript.

- `docs/home.md`: editorial cover, real read-only command examples, task-based starting paths, toolkit links,
  focused help links and a knowledge-base section. No simulated live output or invented runtime state.
- `docs/assets/wiki.css`: light/dark surfaces, original Summon identity, system typography, clearer article/code/
  table styling, active navigation, focus rings and reduced-motion handling.
- `tools/docs-site.py`: five navigation groups with every public page retained; CSS and existing original brand
  assets are staged explicitly. Theme override paths resolve from the canonical checkout, not temporary staging.
- `docs/theme/main.html`: the homepage's keyboard skip link, preserving Material's standard header and behavior.

Browser verification covered the desktop cover and reading page at 1440 × 1000, the mobile drawer/nested guide
route and search at 390 × 844, and the homepage at 320 px wide without horizontal document overflow. Mobile
search returned 24 matching documents for `checkpoint`; input/completion fonts now align at 16 px. Light/dark
layouts and key link destinations were inspected. The first keyboard focus is Skip to content; reduced-motion
emulation produced a zero-duration card transition and no hover transform. Selected light-theme body/action
contrast ranged from 5.07:1 to 6.90:1; this is not a full accessibility audit. Four link regressions passed.

The desktop sidebar is hidden only for the cover; the native mobile drawer remains reachable. Source/release
boundaries and historical labels remain unchanged. No native application code, installation, release channel
or repository Pages setting changed.
