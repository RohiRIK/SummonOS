---
type: Reference
title: Experimental software — risk and responsibility
description: "SummonOS is experimental, not production-qualified or guaranteed secure. Understand user responsibility, incomplete safeguards, warranty limits and ongoing security work."
tags: [disclaimer, security, experimental, responsibility]
---

# Experimental software — risk and responsibility

**SummonOS is experimental software. It is not production-qualified and is not guaranteed to be secure,
reliable or free of defects. Install, connect and use it at your own risk.** A public website, passing tests,
a signed build or a working demonstration is not a security certification or a promise of suitability.

## Understand the risks before using it

SummonOS connects AI coding agents to Mac context and system tools. Depending on the permissions you grant
and the agent's execution mode, an agent can run commands, read or expose information, change settings and
files, install software or make network requests. Incorrect output, malicious instructions, software defects
and unintended actions can cause data loss, privacy or credential exposure, service disruption and other harm.

Safeguards are incomplete and may fail. MCP confirmation fields and safety hints are not a sandbox or an
independent approval boundary. A checkpoint only covers successfully captured, supported state; it cannot
undo arbitrary commands, external actions, every file change or every agent session. Do not rely on SummonOS
as your only backup, security control or recovery mechanism.

## Your responsibility

You are responsible for deciding whether this preview is appropriate for your environment, reviewing the
source and requested access, choosing trusted agents/providers, evaluating their output and approving the
actions you permit. Agent subscriptions, API usage, downloaded tools and external services can have their own
costs and terms; SummonOS does not supply a model or make those decisions for you.

- Keep independent, tested backups and a recovery plan. Prefer a disposable account or noncritical test Mac.
- Use the least permissions needed. Keep the agent's normal approval controls unless you deliberately accept
  the greater risk of unattended execution; inspect existing saved choices rather than assuming defaults.
- Keep secrets, confidential files and personal information out of prompts/context unless you understand and
  accept where they will be processed. Review logs and diagnostic bundles before sharing them.
- Review commands, connection changes, installations and repository/publication actions. A successful test
  does not make an unrelated action safe. Do not deploy this preview into sensitive or critical environments
  on the assumption that it has been independently security-certified.
- Check [current status and acceptance limits](status.md), [the security model](security-model.md) and
  [installation guidance](getting-started.md). Published older versions do not gain newer safeguards retroactively.

## Security work is ongoing — not a guarantee

We are actively working on the project's security: reviewing trust boundaries, improving release verification,
correcting safety metadata, adding regression tests and documenting known limits. This work is incomplete.
It does not establish comprehensive independent audit coverage, remove residual risk or guarantee a fix,
response deadline or future security outcome. Unverified behavior remains unverified.

Report suspected vulnerabilities using the [private security-reporting process](../SECURITY.md). Do not post
exploitable details, tokens or personal diagnostic data in a public issue. Bug reports help us improve the
project; they are not a substitute for your own risk assessment.

## No warranty; limits on liability

SummonOS is provided **"AS IS"**, without warranties or conditions of any kind, as set out in the
[MIT License](../LICENSE), including the disclaimer of merchantability, fitness for a particular purpose and
noninfringement. To the fullest extent permitted by applicable law, the authors and copyright holders are
not liable for claims, damages or other liability arising from the software or its use, including losses
resulting from defects, misuse or unintended agent actions. You bear responsibility for your use and the
consequences of the permissions and actions you authorize.

This notice explains risks; it does not promise that every legal claim can be waived or override rights,
duties or liabilities that applicable law does not allow to be excluded. The project license remains
unchanged, and this page is not a replacement for legal advice about your own obligations.
