---
type: Playbook
title: "Documentation website"
description: "Build, preview, maintain, and publish the wiki from canonical repository Markdown without changing Swift dependencies."
tags: [documentation, wiki, mkdocs, publishing, maintenance]
---

# Documentation website

The SummonOS wiki renders the repository's existing Markdown with
[MkDocs](https://www.mkdocs.org/) and [Material for MkDocs](https://squidfunk.github.io/mkdocs-material/).
The Markdown files remain canonical: edit them in their current repository paths, not in generated output.
The website adds grouped navigation, full-text search, an on-page table of contents, mobile navigation,
light/dark modes, code highlighting and copying, and GitHub source/edit links.

The site describes several different kinds of evidence. Start with [project status](status.md) for the
difference between current checkout behavior, numbered releases, and remaining acceptance gates.
Plans, research, and UX-surface reports appear under **Historical archive**, with a site-only notice;
publication does not turn a dated proposal or old test result into a current product guarantee.

## Local setup

Use Python 3.12 (the CI version), `pip`, and a virtual environment. Documentation dependencies are separate
from the Swift packages; they are not linked into Summon, macctl, or generated apps. No Node tooling,
bespoke JavaScript, or frontend framework is required.

From the repository root:

```sh
python3 -m venv "${TMPDIR:-/tmp}/summonos-docs-venv"
. "${TMPDIR:-/tmp}/summonos-docs-venv/bin/activate"
python -m pip install -r requirements-docs.txt
```

The directly selected MkDocs, Material, Markdown-extension, and YAML versions are pinned in
[`requirements-docs.txt`](../requirements-docs.txt). Update those pins deliberately and run a complete
strict build and browser review together; a dependency upgrade is not an application-runtime dependency
change.

## Preview and strict build

```sh
python tools/docs-site.py serve
```

Open <http://127.0.0.1:8000/SummonOS/>. The `/SummonOS/` prefix mirrors the configured project Pages URL.
The server watches canonical documents and refreshes the staging tree and discovered navigation on
rebuild. Stop it with Control-C. To choose another address:

```sh
python tools/docs-site.py serve --dev-addr 127.0.0.1:8001
```

Build the complete public site, including the archive:

```sh
python tools/docs-site.py build
```

Both commands use MkDocs strict mode. The build also validates rendered HTML links, images, and local
fragments, including raw HTML that MkDocs' Markdown link validation does not cover. A missing source
file, local route, image, or heading is an error, not silently redirected to the homepage. External
GitHub and third-party URLs are not network-checked by this build.

The focused, standard-library link regressions also run in CI:

```sh
python -m unittest discover -s tools/tests -p test_docs_site.py -v
```

They cover relocated links, escaped backticks, literal examples, raw HTML/reference links and rejected
missing/outside targets. Local preview watches canonical sources, not its own generated staging tree.

The default build output is outside the checkout:

- macOS: `$HOME/Library/Caches/SummonOS/docs/site`
- Other platforms: `$HOME/.cache/SummonOS/docs/site`

The temporary staged Markdown and generated MkDocs configuration are removed when the command exits.
The HTML build remains in the output directory until replaced or removed. An explicit output path must
also be outside the repository:

```sh
python tools/docs-site.py build --site-dir "${TMPDIR:-/tmp}/summonos-docs-site"
```

Run the wrapper, **not** a bare `mkdocs build`: the wrapper supplies the multi-directory source mapping,
archive notices, discovered navigation, and correct GitHub edit destinations. Do not copy documents into
`docs/` just to make them visible to MkDocs.

For branch review, make source-only and edit links point at that branch or an exact revision:

```sh
python tools/docs-site.py build --ref feat/example
```

This changes link destinations, not which checkout is built. Without `--ref`, links target `main`.

## Public source mapping

[`tools/docs-site.py`](../tools/docs-site.py) discovers the following sources automatically on each build.
Every selected Markdown document is included in navigation and search, not just documents already linked
from a hand-maintained landing page.

| Canonical source | Site location or grouping |
|---|---|
| `docs/home.md` | Site homepage (`index.md` in temporary staging) |
| Root `README.md` | Get started → About SummonOS (`overview.md` in staging) |
| Root `CONTRIBUTING.md`, `SECURITY.md`, `plugins.md` | Build apps, Knowledge base, and Use SummonOS |
| `docs/**/*.md` | User guides, feature/security references, architecture decisions, catalog, and historical archive |
| `incubator/summon/README.md`, `CHANGELOG.md`, `THIRD_PARTY_NOTICES.md` | Use SummonOS → Summon |
| `incubator/summon/docs/**/*.md` | Use SummonOS → Summon, including its interface specifications and audits |
| `macctl/README.md`, `macctl/docs/**/*.md` | Use SummonOS → macctl and its settings reference |
| `incubator/summon/templates/*/README.md` | Build apps → Templates |
| Public images and PDF assets referenced by selected pages; public images/PDF/text/CSS assets under selected docs trees | Copied into temporary staging with their repository-relative paths |

All selected `README.md` filenames become `overview.md` in staging. This avoids MkDocs' special handling
of `README.md` as an index, especially in directories that already have a generated `index.md`.
Other filenames and directory layouts are preserved, apart from the homepage relocation. The wrapper
rewrites links using the **original document's directory**, so source-relative links work on GitHub and
on the site, including links from the relocated homepage. HTML `href`, `src`, and `srcset` attributes are
mapped to the final output location too. Fenced examples and inline code are left as examples.

Task files, `AGENTS.md`, `PROJECT-CONTEXT.md`, hidden directories, and vendored skills are not staged or
search-indexed. Links to existing repository-only targets, such as a Swift file, shell script, agent rule,
license, or source directory, become explicit GitHub `blob` or `tree` URLs at the selected ref. They do
not create pretend website routes. Missing source targets still fail the build; do not hide a genuine
broken link by widening the public allowlist. Linked symlinks are refused rather than following files
outside the public tree.

## Maintaining documentation

1. Edit canonical Markdown and keep its existing source-relative links. Use Markdown links to `.md`
   documents, not generated HTML paths. Link to a real heading when adding a fragment.
2. New `docs/` concepts need OKF frontmatter: `type`, `title`, `description`, and `tags`. Plans retain
   historical `created` and `status` fields and distinguish later amendments from the original proposal.
3. Regenerate the knowledge-catalog indexes with `python tools/okf-index.py`; do not hand-edit them.
   These indexes remain useful when reading the repository without the website.
4. Add a notable documentation change to [the update log](log.md). Update [features](features.md) only
   when implemented user-visible behavior changes, not when a plan merely proposes it.
5. Run the strict site build. Fix missing files and heading fragments at the source. Never weaken
   validation to accommodate a stale link or turn an unverified historical result into acceptance.
6. Review desktop and narrow/mobile navigation, search results, code fences/tables, light/dark mode,
   images, archive notices, and GitHub source/edit links in the browser.

## Visual system and navigation

The field-guide homepage lives in [`home.md`](home.md), with semantic HTML for its hero, real command
examples, task-based entry cards and knowledge links. It remains the canonical content; there is no separate
marketing page or generated copy to maintain. Its metadata hides the article table of contents; CSS hides
the desktop sidebar only, keeping the mobile drawer reachable. A small [`theme/main.html`](theme/main.html)
override adds the homepage's keyboard skip link while retaining Material's standard header.

[`assets/wiki.css`](assets/wiki.css) provides the Summon visual identity: system typography, violet accents,
coordinated light/dark surfaces, readable code/tables, focus outlines and reduced-motion handling. It also
styles the reading pages without replacing Material's search, drawer, keyboard behavior or Mermaid integration.
Brand logo/favicon are staged explicitly from Summon's existing original artwork. No new font service,
JavaScript bundle or frontend dependency was added.

The five top-level destinations are **Overview**, **Get started**, **Use SummonOS**, **Build apps** and
**Knowledge base**. Historical archive content remains explicitly labeled inside the knowledge base.
Every discovered public page stays in navigation and search. Check mobile nested navigation as well as
the desktop tabs when changing these groups; the mobile drawer uses Material's native controls.

Navigation uses readable top-level groups and automatically appends new public pages. Adjust deliberate
prominent-page ordering in `navigation()` when needed; change the public selection rules only when the
new source belongs in the published wiki. [`mkdocs.yml`](../mkdocs.yml) owns theme, search, Markdown
extensions, canonical URL, and strict validation settings. GitHub-style fenced blocks and tables render
as code and tables. Mermaid fences use [Material's native diagram integration](https://squidfunk.github.io/mkdocs-material/reference/diagrams/),
including light/dark styling, without custom JavaScript. Other fence languages remain code rather than
becoming raw HTML.

Material loads Mermaid's runtime from its CDN when a diagram page opens; diagram rendering therefore needs
network access. Navigation, search, theme assets and ordinary document content are served from the built site.

## CI and publishing

The [Documentation workflow](../.github/workflows/docs.yml) validates documentation-related pushes on any
branch and pull requests with the same strict build. PRs and ordinary non-main pushes **do not upload a
Pages artifact or deploy**, and the build job has read-only repository access. Relevant root documents,
public docs trees/assets, template READMEs, and site tooling/configuration trigger it.

Publishing is separate from application releases:

- A documentation push to `main` uploads the built Pages artifact and requests deployment.
- A maintainer can run **Documentation → Run workflow** on a deliberately selected ref. With **deploy**
  left false, this only validates; selecting **deploy** requests publication of that ref.
- Only the deployment job receives `pages: write` and `id-token: write`. It uses the `github-pages`
  environment and does not check out or execute source. Publishing jobs are serialized.
- The workflow uses pinned action commit IDs and does not edit repository settings, create a `gh-pages`
  branch, publish Swift binaries, or modify application-release channels.

### Owner prerequisites

As of the documentation refresh, GitHub Pages was not available through the repository Pages API. The
presence of this workflow is **not evidence that the site is deployed**. Before publishing, an owner must:

1. Enable Pages for the repository in **Settings → Pages → Build and deployment → Source → GitHub Actions**,
   subject to repository visibility, account-plan, and organization policy restrictions.
2. Configure or approve the `github-pages` environment and its branch protection/reviewer rules. A
   dispatch from a feature branch must be intentionally permitted by those rules if it is to deploy.
3. Confirm the expected public URL. The configuration targets
   `https://RohiRIK.github.io/SummonOS/`; update `site_url` before publishing to a custom domain or another
   repository path.
4. Confirm the selected documents and assets are appropriate for a public website. Read-only CI
   validation does not authorize disclosing private state or publishing experimental acceptance claims.
5. Run the workflow, review the deployment result and actual site in a browser, and only then advertise
   the live URL.

Until those prerequisites are met, local preview and PR validation remain usable; a requested deployment
may fail at the Pages service rather than making the site public. This task does not change those settings.
See GitHub's [custom Pages workflow guide](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages)
for the deployment permission and environment contract.
