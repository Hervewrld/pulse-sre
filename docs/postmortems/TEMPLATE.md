# Postmortem: <short incident title>

|              |                                    |
| ------------ | ---------------------------------- |
| **Date**     | YYYY-MM-DD                         |
| **Author**   | who wrote this up                  |
| **Severity** | SEV-1 / SEV-2 / SEV-3 (see below)  |
| **Status**   | Draft / Reviewed / Follow-ups open |

Severity guide (pick one, don't overthink it):
- **SEV-1** — full outage or data loss/corruption risk.
- **SEV-2** — degraded (elevated errors/latency, or one AZ/service down but the
  system as a whole still serves traffic).
- **SEV-3** — no user-visible impact; caught by internal alerting only.

## Summary

Two or three sentences. What broke, for how long, who/what was affected.
Written so someone who wasn't there understands the shape of the incident
without reading further.

## Impact

- What was actually affected (which service(s), which monitors/checks, real
  users if any)
- Duration: from **first user/system impact** to **full recovery** - not
  from when someone noticed
- Anything irreversible (data loss, missed alerts, an SLO burned)

## Detection

How was this noticed - **which alarm/alert fired**, and in which system
(CloudWatch alarm → SNS from `terraform/modules/observability`, or Pulse's
own app-level Slack alert from `src/alerting`)? If it was noticed by a human
poking around instead of an alert, say that plainly - that's a finding, not
something to gloss over.

- Time of first impact:
- Time of detection:
- **Time to detect**: (detection − first impact)
- How it was detected:

## Timeline

All times UTC. Pull from CloudWatch Logs Insights (saved queries in
`terraform/modules/observability`), the CloudWatch alarm history, and the
GitHub Actions run if a deploy was involved.

| Time (UTC) | Event |
| ---------- | ----- |
|            | Change/trigger introduced (deploy, chaos drill, external event) |
|            | First user/system impact |
|            | Alarm fired / alert sent |
|            | Someone acknowledged |
|            | Root cause identified |
|            | Mitigation applied |
|            | Confirmed recovered |

- **Time to detect** (first impact → alarm fired):
- **Time to mitigate** (alarm fired → mitigation applied):
- **Time to resolve** (first impact → confirmed recovered):

## Root cause

What actually broke and why - not just "the database was down," but *why*
it went down and *why* the system responded to that the way it did. If this
was a deliberate chaos drill (`scripts/chaos/`), say which script and what
it does.

## What went well

Things that worked as designed - an alarm that fired correctly, a rollback
that actually rolled back, a runbook step that was accurate. Worth naming
explicitly so they don't get quietly redesigned away later.

## What went wrong / follow-ups

One row per gap. Every row needs an owner and should be an issue/ticket, not
just a bullet that quietly disappears.

| Follow-up | Owner | Status |
| --------- | ----- | ------ |
|           |       | open   |

## Lessons

The 1-2 things worth remembering from this incident in an interview - what
would you do differently, and what does this say about the system's design.
