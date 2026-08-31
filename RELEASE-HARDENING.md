# Local-tracker recovery and release hardening — QA-01 and REL-01

The deterministic timer suites cover first-save authority, rollback, retries,
idempotent duplicate Stop, rapid app/intent competition, restart
reconstruction, malformed multiple-active state, explicit repair, exact intent
boundaries, and projection failures. UI fixtures additionally exercise
background/relaunch recovery, projection failure with Retry, disabled Live
Activities, a continuing timer beyond eight hours, and malformed-state
guidance.

Recovery copy always distinguishes source data from a projection:

- `Your timer is saved` confirms the database command succeeded even if the
  Lock Screen projection failed.
- A queued Lock Screen Stop remains durable and retryable until SwiftData
  acknowledges it.
- Multiple active records are never silently rewritten; users are directed to
  Session History.
- Disabled Live Activities expose a direct Billable Hours iPhone Settings
  action in both the recovery banner and Settings screen while in-app timing
  continues normally. Transient projection failures continue to expose Retry.
- Empty report, project, session, and onboarding states retain their direct
  creation or navigation actions.

No recovery path claims success for a failed database command, and no
projection repair mutates session timestamps.
