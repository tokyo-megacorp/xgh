# Slack Urgency Taxonomy Report

**Date:** 2026-03-15
**Channels scanned:** 3
**Messages analyzed:** ~250 (including thread replies)

---

## 1. Channels Scanned

| Channel | ID | Activity Level | Nature |
|---|---|---|---|
| #workgroup-account-recovery-improvements | C09JR6UGXV1 | Medium (~20 msgs/week) | Feature launch coordination, experiment rollout |
| #workgroup-new-web-login | C0AFD043BCL | Very High (~80+ msgs/week) | Active feature development under deadline pressure |
| #psd2-internal | C09P6BETMTR | Low (~5 msgs/week) | External partner API support, compliance |

---

## 2. Real Urgency Examples by Category

### A. DEADLINE PRESSURE SIGNALS

**[HIGH]** "Deadline is EOD tonight" + merge into hotfix branch
- Source: #workgroup-new-web-login, Lucas, 2026-03-12
- Full text: "We are allowed to merge into hotfix branch (Deadline is EOD tonight) - confirmed with core"
- Pattern: explicit "EOD" + "deadline" + "hotfix"/"merge" in same message
- Language signal: `deadline.*EOD|EOD.*tonight|by EOD`

**[HIGH]** Rollout schedule with daily percentages
- Source: #workgroup-account-recovery-improvements, Lucas, 2026-03-13
- Full text: "8:30 -> we set up experiment / 9:00 -> Go live call / 9:10 -> Feature activation (FF for 1% of users) / Roll-out: Monday 1%, Tuesday 10%, Wednesday 20%, Thursday 50%, Friday 100%"
- Pattern: numbered daily rollout plan with specific times
- Language signal: `go.?live|roll.?out.*\d+%|feature activation`

**[HIGH]** Launch date shift announcement
- Source: #workgroup-new-web-login, Lucas, 2026-03-06
- Full text: "we should move the Web launch by one day (min) to ensure full QA coverage. Because the login flow is critical, we need to be 100% confident before it goes live."
- Pattern: launch date change + "critical" qualifier
- Language signal: `move.*launch|new target.*Thursday|launch.*moved`

**[MEDIUM]** "for Monday" action list with @-mentions
- Source: #workgroup-new-web-login, Lucas, 2026-03-13
- Full text: "for Monday: @Emmanuel can you check android behavior / @tokyo-megacorp please have a look at this iOS issue again"
- Pattern: day-of-week as deadline + assigned actions
- Language signal: `for (Monday|Tuesday|Wednesday|Thursday|Friday):\s*\n.*@`

**[MEDIUM]** "let's aim to close all open topics tomorrow"
- Source: #workgroup-new-web-login, Cem, 2026-03-09
- Pattern: aspirational deadline with "tomorrow"
- Language signal: `close all.*tomorrow|aim to.*by tomorrow`

### B. SCOPE/REQUIREMENT CHANGE SIGNALS

**[HIGH]** P0 list that forces plan change
- Source: #workgroup-new-web-login, Lucas, 2026-03-10
- Full text: "we found a few p0 that we need to fix before we can actually go live... reason: localisation team is under water, and we will not get the copy changes as needed this week"
- Pattern: "p0" + "before we can go live" + workaround rationale
- Language signal: `p0|P0|p1|P1|before we can.*go.?live`

**[MEDIUM]** Timer/config change mid-flight
- Source: #workgroup-new-web-login, Lucas, 2026-03-12
- Full text: "Change timer for approval to 2 minutes - confirmed with compliance"
- Pattern: parameter change + compliance confirmation
- Language signal: `change.*timer|adjust.*duration|confirmed with compliance`

**[MEDIUM]** Copy/text changes during QA
- Source: #workgroup-new-web-login, Liza, 2026-03-04
- Full text: "I noticed that the copy in the key is incorrect for the new Can't login modal. We need to distinguish between bold and grey text"
- Pattern: spec discrepancy found during QA
- Language signal: `copy.*incorrect|difference.*Figma|different.*Figma.*prod`

**[LOW]** "Why we are changing copies that frequent, is it because we make mistakes?"
- Source: #workgroup-new-web-login, Cem, 2026-03-12
- Pattern: frustration signal about churn
- Language signal: `why.*changing.*frequent|keep changing`

### C. BLOCKER SIGNALS

**[CRITICAL]** "the issue on iOS is critical and a release blocker"
- Source: #workgroup-new-web-login, Lucas, 2026-03-11
- Full text: "the issue on iOS is critical and a release blocker. If a user doesn't have the app started, they can't login on web. -> We need to fix it before going live."
- Pattern: explicit "release blocker" + "critical" + "need to fix before"
- Language signal: `release blocker|critical.*blocker|blocker.*critical|need to fix.*before.*go.?live`

**[HIGH]** "blocked to do any proper QA"
- Source: #workgroup-new-web-login, Liza, 2026-03-06
- Full text: "I'm basically blocked to do any proper QA because I have only iOS device without mocking"
- Pattern: person blocked from doing their work
- Language signal: `blocked to|blocked on|can'?t.*QA|can'?t proceed`

**[HIGH]** External partner escalation with "blocking our API integration"
- Source: #psd2-internal, Carla, 2026-03-05
- Full text: "As the issue remains unresolved and is currently blocking our API integration, we would appreciate an update"
- Pattern: external partner escalation + "blocking" + "unresolved"
- Language signal: `blocking our.*integration|remains unresolved|blocking.*API`

**[HIGH]** "test will fail until we fix this, which is unlikely today"
- Source: #workgroup-new-web-login, Cem, 2026-03-09
- Full text: "test will fail until we fix this / Which is unlikely today"
- Pattern: blocking statement + timeline pessimism
- Language signal: `will fail until|unlikely today|can'?t.*until we fix`

**[MEDIUM]** "Waiting for the copy update for 'Change PIN' keys, translations being too long"
- Source: #workgroup-new-web-login, Emmanuel, 2026-03-10
- Full text: loading emoji + "Waiting for the copy update"
- Pattern: dependency on another team (localisation)
- Language signal: `:loading:|waiting for.*update|waiting for.*team`

### D. DECISION SIGNALS

**[HIGH]** "We consciously delayed the launch to do more extensive QA"
- Source: #workgroup-new-web-login, Cem, 2026-03-09
- Pattern: conscious strategic decision communicated to team
- Language signal: `consciously|we decided|decision.*go.?live|confirmed.*decision`

**[HIGH]** "this means, we cannot launch tomorrow. With account recovery on Monday, we do it on Tuesday."
- Source: #workgroup-new-web-login, Lucas, 2026-03-11
- Pattern: launch date decision with dependency reasoning
- Language signal: `cannot launch|new.*launch.*date|do it on (Monday|Tuesday|Wednesday|Thursday|Friday)`

**[MEDIUM]** Architectural recommendation with rationale
- Source: #workgroup-new-web-login, Liza, 2026-03-04
- Full text: "our recommendation is to go without [QR expiration] on web, because: 1. Timer will drop to 5 min anyway... 3. We'd need extra effort (~1 day estimation)"
- Pattern: "our recommendation" + numbered reasons + effort estimate
- Language signal: `recommendation is|let'?s go with|approach is|we should go`

**[MEDIUM]** "for p0: let's use our current copy and send after accepted log in"
- Source: #workgroup-new-web-login, Lucas, 2026-03-10
- Pattern: scoping decision under pressure (workaround chosen)
- Language signal: `for (p0|now|the moment).*let'?s (use|go with|keep)`

### E. ACTION REQUEST SIGNALS

**[HIGH]** Direct assignment with @-mention + "can you"
- Source: #workgroup-new-web-login, Lucas, 2026-03-12
- Full text: "@Bahadir can you adjust?" / "@Emmanuel and @tokyo-megacorp [merge into hotfix]"
- Pattern: @person + action verb
- Language signal: `<@U\w+>.*can you|<@U\w+>.*please|<@U\w+>.*could you`

**[HIGH]** "Can we make sure we are ready for the test at 2pm"
- Source: #workgroup-new-web-login, Lucas, 2026-03-12
- Full text: "can we make sure we are ready for the test at 2pm: ensure latest web changes merged / build on iOS to be used"
- Pattern: readiness check with checklist + time
- Language signal: `make sure.*ready|ensure.*before|ready for.*test`

**[MEDIUM]** Ticket transition requests
- Source: #workgroup-new-web-login, Liza (recurring pattern)
- Full text: "Could you please move these tickets into ready for release [JIRA links]"
- Pattern: ticket state change request + JIRA links
- Language signal: `move.*ticket.*ready for release|move.*into.*release`

**[MEDIUM]** "can you reset this counter on your side"
- Source: #workgroup-new-web-login, Emmanuel, 2026-03-03
- Pattern: unblock-me request (environment/config action needed)
- Language signal: `can you (reset|enable|disable|turn on|turn off|check)`

### F. STATUS CHANGE SIGNALS

**[HIGH]** "Go live" confirmation
- Source: #workgroup-new-web-login, Lucas, 2026-03-13
- Full text: "we just got thumbs up. We will go-live on Monday!"
- Pattern: approval received + go-live date
- Language signal: `go.?live|thumbs up|approved|green light`

**[HIGH]** Revert/rollback
- Source: #workgroup-new-web-login, Liza, 2026-03-09
- Full text: "since prod testing failed, I'll revert login v2 on beta as web trading team has also a QA session tomorrow and we want to minimise risks"
- Pattern: revert + risk reasoning
- Language signal: `revert|rolled? back|rollback|minimise risks`

**[MEDIUM]** Deploy/merge confirmation
- Source: #workgroup-new-web-login, Bahadir, 2026-03-11
- Full text: "Sending the email once the web login process is successful has been released :white_check_mark:"
- Pattern: feature released + checkmark
- Language signal: `:white_check_mark:|released|deployed|merged|is live`

**[MEDIUM]** Feature flag toggle
- Source: #workgroup-new-web-login, Liza, 2026-03-11
- Full text: "Enabled the FF, should be there in ~5 min"
- Pattern: feature flag state change
- Language signal: `enabled.*FF|disabled.*FF|feature flag.*enabled|turned (on|off)`

**[LOW]** Environment status
- Source: #workgroup-new-web-login, Bahadir, 2026-03-03
- Full text: "the PATCH API implementation is finally merged. It will be available in stg as well in 10 minutes."
- Pattern: staging/prod availability update
- Language signal: `available in (stg|staging|prod|production)|deployed to.*env`

---

## 3. Proposed Detection Patterns

### Regex/Keyword Patterns per Category

```yaml
deadline_pressure:
  high:
    - '\b(EOD|end of day)\b'
    - '\bdeadline\b.*\b(today|tonight|tomorrow)\b'
    - '\bgo.?live\b.*\b(Monday|Tuesday|Wednesday|Thursday|Friday|tomorrow)\b'
    - '\bbefore.*release\b'
    - '\bcode.?freeze\b'
    - '\bhotfix\b'
    - '\broll.?out.*\d+%'
  medium:
    - '\bfor (Monday|Tuesday|Wednesday|Thursday|Friday)\b'
    - '\bby (Monday|Tuesday|Wednesday|Thursday|Friday)\b'
    - '\baim to.*\b(tomorrow|today)\b'
    - '\btarget.*\b(Monday|Tuesday|Wednesday|Thursday|Friday)\b'

scope_change:
  high:
    - '\bp0\b|\bP0\b'
    - '\bbefore we can.*go.?live\b'
    - '\bchange of plans\b'
    - '\bneed to fix before\b'
  medium:
    - '\bcopy.*incorrect\b'
    - '\bdifferent.*Figma\b'
    - '\bupdated the spec\b'
    - '\bchange.*timer\b|\badjust.*duration\b'
    - '\bconfirmed with compliance\b'

blocker:
  critical:
    - '\brelease blocker\b'
    - '\bcritical.*blocker\b|\bblocker.*critical\b'
  high:
    - '\bblocked (to|on|by)\b'
    - '\bblocking our\b'
    - '\bcan.?t proceed\b'
    - '\bremains unresolved\b'
    - '\bwill fail until\b'
  medium:
    - '\bwaiting for\b.*\b(update|team|approval|review)\b'
    - ':loading:'

decision:
  high:
    - '\bwe decided\b'
    - '\bcannot launch\b'
    - '\bconsciously\b.*\b(delay|decide)\b'
    - '\bnew.*launch.*date\b'
  medium:
    - '\brecommendation is\b'
    - '\blet.?s go with\b'
    - '\bfor (p0|now).*let.?s\b'

action_request:
  high:
    - '<@U\w+\|[^>]+>.*\b(can you|please|could you)\b'
    - '\bmake sure.*ready\b'
    - '\bensure.*before\b'
  medium:
    - '\bmove.*ticket.*ready for release\b'
    - '\bcan you (reset|enable|disable|check|turn)\b'
    - '\bplease have a look\b'

status_change:
  high:
    - '\bgo.?live\b'
    - '\brevert\b|\brolled?.?back\b'
    - '\bthumbs up\b|\bapproved\b|\bgreen light\b'
  medium:
    - ':white_check_mark:'
    - '\breleased\b|\bdeployed\b|\bmerged\b'
    - '\benabled.*FF\b|\bfeature flag\b'
  low:
    - '\bavailable in (stg|staging|prod)\b'
```

---

## 4. Novel Patterns (Not in Original Categories)

### G. CROSS-TEAM DEPENDENCY SIGNALS
Messages referencing other teams as constraints or gates.
- "localisation team is under water, and we will not get the copy changes as needed this week"
- "we'd need a support from a web-trading engineer to approve our deployment"
- "confirmed with compliance" / "synced with Compliance and FinCrime"
- Pattern: team name + constraint language
- Regex: `\b(team|localisation|compliance|FinCrime|security|core)\b.*\b(under water|not available|waiting|synced with|confirmed with|aligned with)\b`

### H. ENVIRONMENT/INFRA INCIDENT SIGNALS
Real-time debugging in production or staging.
- "beta version is broken" / "Something is off"
- "I'm restarting the pods now" / "It'll take 5 minutes"
- "upstream sent too big header while reading response header from upstream"
- Pattern: infra action + real-time narration
- Regex: `\b(restarting|pods|5xx|500|502|broken|misconfigured)\b`

### I. RISK MITIGATION / SAFETY NET SIGNALS
Messages about fallback plans and defensive measures.
- "we need to add a fallback to login v1 on web in case of 5xx"
- "we want to minimise risks"
- "I am aligning with Bradley to include our web login iOS change in [the code freeze extension]"
- Pattern: fallback planning language
- Regex: `\b(fallback|minimise risks|safety|rollback plan|code freeze extension)\b`

### J. AVAILABILITY/ABSENCE SIGNALS
Team capacity signals that affect delivery.
- "I'll be partially off next Monday starting 2pm"
- "sorry for the inconvenience, but I need to take my son to the dentist urgent"
- "I need to finish earlier tomorrow, will be off starting 17:30"
- Pattern: absence notice near deadline
- Regex: `\b(off|offline|AFK|out of office|OOO)\b.*\b(today|tomorrow|Monday|Tuesday)\b`

### K. CONFIDENCE/READINESS CHECK SIGNALS
Proactive pre-launch verification.
- "do we have any blockers / anything I should be aware of before doing some prod QA?"
- "is everything ready on prod for testing?"
- "Can we make sure we are ready for the test at 2pm"
- Pattern: question-form readiness probe
- Regex: `\b(any blockers|anything.*aware|ready for|ready on prod)\b`

### L. WORKAROUND/COMPROMISE SIGNALS
Scope cuts under time pressure.
- "for p0: let's use our current copy and send after accepted log in. We should remove the button"
- "let's stay with duration times" (declining a suggested improvement)
- "no blocker, but we need to fix"
- Pattern: explicit tradeoff being made
- Regex: `\bfor (p0|now|the moment)\b.*\blet.?s\b|\bno blocker, but\b|\bnot a blocker\b`

---

## 5. Recommended Urgency Scoring Heuristic

### Base Score (by category match)
| Category | Base Score |
|---|---|
| Blocker (critical keywords) | 90 |
| Deadline pressure (EOD/today) | 80 |
| Scope change (P0/before go-live) | 75 |
| Status change (revert/rollback) | 70 |
| Decision (launch date change) | 65 |
| Action request (with @-mention) | 50 |
| Cross-team dependency | 45 |
| Environment incident | 60 |
| Status change (deploy/merge) | 30 |
| Availability notice | 20 |

### Multipliers
| Signal | Multiplier |
|---|---|
| Contains `@here` or `@channel` | x1.5 |
| Contains P0/critical/blocker | x1.4 |
| Posted outside business hours (before 9am or after 6pm) | x1.3 |
| Contains multiple @-mentions (>2) | x1.2 |
| Has thread with >10 replies | x1.2 |
| Posted on weekend | x1.3 |
| Contains Jira/Confluence links | x1.1 |
| Contains "before we can go live" or similar | x1.3 |
| Message from PM/lead role (pattern: schedules meetings, assigns tasks) | x1.1 |

### Composite Score
```
urgency_score = base_score * product(applicable_multipliers)
```

### Thresholds
| Score Range | Label | Action |
|---|---|---|
| 0-30 | Low | Log only |
| 31-55 | Medium | Surface in daily digest |
| 56-79 | High | Alert team lead |
| 80+ | Critical | Immediate notification |

### Key Observation
The highest-urgency messages in these channels share a consistent structure: **problem statement + impact on timeline + assigned owner**. The single strongest signal of real urgency is the combination of a blocker keyword with an explicit person assignment and a date reference in the same message or thread.
