---
type: Reference
title: SummonOS documentation
description: "Your field guide to an agent-ready Mac: set up SummonOS, explore the toolkit and build native apps."
tags: [documentation, navigation, summon, macctl]
hide: [toc]
---

<div class="summon-home">

<section class="home-hero" aria-labelledby="home-title">
<div class="home-hero-copy">
<p class="home-eyebrow"><span class="home-spark" aria-hidden="true">✦</span> THE SUMMONOS FIELD GUIDE</p>

<h1 id="home-title">The Mac.<br><span>Agent-ready.</span></h1>

<p class="home-lead">Connect your agent. Make something native. Know what you can change—and what you can undo.</p>
<div class="home-actions">
<a class="home-button home-button-primary" href="getting-started.md">Get started <span aria-hidden="true">↗</span></a>
<a class="home-button home-button-text" href="features.md">Explore the toolkit <span aria-hidden="true">→</span></a>
</div>
<p class="home-platform">Native Swift <span aria-hidden="true">/</span> macOS 15+ <span aria-hidden="true">/</span> Your choice of agent</p>
</div>

<div class="home-console">
<img class="home-console-mark" src="../incubator/summon/design/brand/app-icon-128.png" alt="" width="72" height="72">
<div class="home-console-heading"><span class="home-console-symbol" aria-hidden="true">&gt;_</span> A LITTLE CONTEXT GOES A LONG WAY</div>
<div class="home-command"><span class="home-command-label">01 — KNOW YOUR MAC</span><code><span aria-hidden="true">$ </span>summon context</code></div>
<div class="home-command"><span class="home-command-label">02 — PREVIEW THE CONNECTION</span><code><span aria-hidden="true">$ </span>summon connect --dry-run</code></div>
<div class="home-command"><span class="home-command-label">03 — FIND YOUR RECOVERY POINTS</span><code><span aria-hidden="true">$ </span>summon checkpoint list</code></div>
<div class="home-console-footer"><span aria-hidden="true"></span>Read-only commands. A good place to begin.</div>
</div>
</section>

<div class="home-release">
<span class="home-release-label"><span aria-hidden="true"></span> BUILT IN THE OPEN</span>
<p><strong>0.2.5 preview.</strong> <a href="status.md">See what shipped <span aria-hidden="true">→</span></a></p>
</div>

<section class="home-paths" aria-labelledby="paths-title">
<div class="home-section-heading"><div><p class="home-eyebrow">A PLACE FOR EVERY START</p><h2 id="paths-title">What brings you here?</h2></div><a href="index.md">All documentation <span aria-hidden="true">↗</span></a></div>
<div class="home-path-grid">
<a class="home-path" href="getting-started.md">
<div class="home-path-top"><span class="home-path-icon"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" aria-hidden="true"><path d="M5 5h14v14H5zM9 2v6m6-6v6M2 9h6m-6 6h6m8-6h6m-6 6h6M9 16v6m6-6v6"/></svg></span><span class="home-path-number">01</span></div>
<h3>Make yourself at home.</h3><p>Install SummonOS, choose your agent and get the permissions right.</p><span class="home-path-action">Set up your Mac <span aria-hidden="true">→</span></span>
</a>
<a class="home-path" href="features.md">
<div class="home-path-top"><span class="home-path-icon"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" aria-hidden="true"><path d="m4 6 6 6-6 6m10 0h6M2 2h20v20H2z"/></svg></span><span class="home-path-number">02</span></div>
<h3>Find your next command.</h3><p>Mac context, themes, checkpoints and the tools behind the panel.</p><span class="home-path-action">Explore what’s possible <span aria-hidden="true">→</span></span>
</a>
<a class="home-path" href="workflow.md">
<div class="home-path-top"><span class="home-path-icon"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" aria-hidden="true"><path d="m12 2 10 5-10 5L2 7l10-5Zm-10 10 10 5 10-5M2 17l10 5 10-5"/></svg></span><span class="home-path-number">03</span></div>
<h3>Build something native.</h3><p>From a small idea to a real Mac app, with templates and a clear build loop.</p><span class="home-path-action">Start building <span aria-hidden="true">→</span></span>
</a>
</div>
</section>

<section class="home-toolkit" aria-labelledby="toolkit-title">
<div class="home-toolkit-intro"><p class="home-eyebrow">MEET THE TOOLKIT</p><h2 id="toolkit-title">Two tools.<br>One Mac.</h2><p>A native place to summon your agent. A precise way to change supported settings.</p></div>
<div class="home-tool-list">
<a class="home-tool" href="../incubator/summon/README.md"><span class="home-tool-icon" aria-hidden="true">✦</span><div><h3>Summon</h3><p>The menu bar app, CLI and agent connection.</p></div><span class="home-tool-arrow" aria-hidden="true">↗</span></a>
<a class="home-tool" href="../macctl/README.md"><span class="home-tool-icon home-tool-icon-mono" aria-hidden="true">&gt;_</span><div><h3>macctl</h3><p>Typed macOS settings, snapshots and scoped recovery.</p></div><span class="home-tool-arrow" aria-hidden="true">↗</span></a>
<div class="home-tool-foot"><a href="../macctl/docs/settings.md">Settings catalog <span aria-hidden="true">→</span></a><a href="../plugins.md">Apps &amp; plugins <span aria-hidden="true">→</span></a></div>
</div>
</section>

<section class="home-shortcuts" aria-labelledby="shortcuts-title">
<div class="home-section-heading"><div><p class="home-eyebrow">LESS HUNTING. MORE DOING.</p><h2 id="shortcuts-title">Straight to the useful part.</h2></div></div>
<div class="home-shortcut-grid">
<a href="troubleshooting.md"><span><strong>Something not working?</strong><small>Permissions, connections and updates</small></span><span aria-hidden="true">↗</span></a>
<a href="security-model.md"><span><strong>Understand the boundaries.</strong><small>Agent authority and what undo covers</small></span><span aria-hidden="true">↗</span></a>
<a href="../incubator/summon/CHANGELOG.md"><span><strong>Catch up on the changes.</strong><small>Published previews and branch work</small></span><span aria-hidden="true">↗</span></a>
<a href="../CONTRIBUTING.md"><span><strong>Make it better with us.</strong><small>Source, checks and contribution workflow</small></span><span aria-hidden="true">↗</span></a>
</div>
</section>

<section class="home-knowledge" aria-labelledby="knowledge-title">
<div><p class="home-eyebrow">BEHIND THE DECISIONS</p><h2 id="knowledge-title">Not just the how.<br>The why, too.</h2><p>Design notes, architecture and dated evidence. A working knowledge base—not a promise that every old plan shipped.</p></div>
<div class="home-knowledge-links"><a href="ux-surfaces/index.md">Native Mac design <span aria-hidden="true">↗</span></a><a href="adr/index.md">Architecture decisions <span aria-hidden="true">↗</span></a><a href="research/index.md">Research notes <span aria-hidden="true">↗</span></a><a href="plans/index.md">Plans &amp; reports <span aria-hidden="true">↗</span></a></div>
</section>

<div class="home-bottom"><p>Agents run with your permissions. Checkpoints are not a full-system backup.</p><div><a href="documentation.md">About these docs</a><a href="log.md">Docs history</a><a href="../SECURITY.md">Report a vulnerability</a></div></div>

</div>
