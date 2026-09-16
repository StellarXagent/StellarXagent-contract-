# Independent Security Review Process

Defines how the independent review required by
[#26](https://github.com/Stellargent/Smart-contracts/issues/26) is
scoped, run, and signed off. **No review has happened yet** — the sign-off
record at the bottom is intentionally blank. This document is the process
and the template, not a claim that an audit occurred.

## Scope

- `contracts/tokens` (`MyToken`) and `contracts/marketplace`
  (`PromptMarketplace`), at the exact commit being proposed for Mainnet.
- `scripts/deploy-mainnet.sh`, `scripts/verify-mainnet.sh`,
  `scripts/canary-mainnet.sh` — these hold and move real funds and real
  admin authority, so they are in scope, not just the contracts.
- The dependency provenance policy delivered by
  [#9](https://github.com/Stellargent/Smart-contracts/issues/9),
  once it exists.
- Out of scope: Backend/UI staging (tracked separately; see #26 non-goals).

## Who can do this review

Someone with no authorship stake in the reviewed commit: an external
security firm, an independent contributor, or another maintainer who did
not write the code under review. A self-review by the PR author does not
satisfy this requirement.

## Process

1. **Freeze**: tag or record the exact commit hash, `Cargo.lock` hash, and
   WASM hashes being reviewed (see
   `docs/security/MAINNET_RELEASE_CHECKLIST.md` §2).
2. **Engage**: share this document, the frozen commit, and repository
   access with the reviewer.
3. **Review**: the reviewer produces a written findings report.
4. **Triage**: every finding gets a severity (below) and an owner.
5. **Resolve**: fixes for Critical/High findings land as their own
   reviewable commits; the reviewer re-checks each fix against the
   original finding.
6. **Sign off**: once there are zero unresolved Critical/High findings, the
   reviewer and a maintainer complete the sign-off record below (or a
   linked copy of it) for this specific commit.

## Severity definitions and SLA

| Severity | Definition | Release impact |
|---|---|---|
| Critical | Direct loss/theft of funds, unauthorized mint/burn, admin takeover. | Blocks release until fixed and re-reviewed. |
| High | Denial of service on core flows (`buy_prompt`, `remint`, `pause`), auth bypass without direct fund loss. | Blocks release until fixed and re-reviewed. |
| Medium | Incorrect behavior under edge cases, gas/resource inefficiency with user impact. | Must have a tracked follow-up issue before release; does not block by itself. |
| Low / Informational | Style, documentation, defense-in-depth suggestions. | Tracked, does not block release. |

## Advisory/finding exceptions

Any finding accepted as a documented risk instead of fixed (e.g. a Medium
with no practical exploit path before the next release) must record: the
finding, the rationale, the accepting maintainer, and a review/expiry date.
An exception with no expiry date is not valid. Critical/High findings
cannot be excepted — only fixed.

## Sign-off record

_Blank until a real independent review is performed. Do not fill this in
speculatively._

| Field | Value |
|---|---|
| Reviewer | _pending_ |
| Commit reviewed | _pending_ |
| `Cargo.lock` hash reviewed | _pending_ |
| WASM hashes reviewed (token / marketplace) | _pending_ |
| Findings summary (Critical / High / Medium / Low) | _pending_ |
| Resolution commits for Critical/High findings | _pending_ |
| Documented exceptions (if any) | _pending_ |
| Sign-off date | _pending_ |
| Sign-off signatures (reviewer + maintainer) | _pending_ |
