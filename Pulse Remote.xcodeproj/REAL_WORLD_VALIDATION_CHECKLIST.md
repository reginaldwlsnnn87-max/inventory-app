# Real-World Validation Checklist (Offline Pulse Remote)

Use this checklist to prove the app works in real operations and is worth paying for.

## 1) Validation Goal (Pass/Fail)

- [ ] Prove a small business can run daily inventory workflows in the app with no hand-holding.
- [ ] Prove measurable value in 14 days.
- [ ] Prove reliability and trust for production use.

Target outcomes:
- [ ] Count time reduced by >= 25%.
- [ ] Shrink visibility improved (weekly shrink report generated and reviewed).
- [ ] Data accuracy >= 98% on spot checks.
- [ ] Crash-free sessions >= 99.5%.
- [ ] At least 2 pilot businesses say they would pay.

## 2) Pilot Scope (14-Day Plan)

### Days 1-2: Baseline
- [ ] Document current process (before app): time spent, errors, missed items, shrink handling.
- [ ] Capture baseline KPIs for each pilot business.

### Days 3-5: Shadow Mode
- [ ] Team keeps current process.
- [ ] Team also performs same workflow in app.
- [ ] Compare differences and log gaps.

### Days 6-10: Assisted Mode
- [ ] App becomes primary workflow.
- [ ] Legacy process used only as fallback.
- [ ] Track completion time per task and error corrections.

### Days 11-14: Owner Mode
- [ ] Shift lead runs daily process fully in app.
- [ ] Review weekly outcomes and pricing willingness.
- [ ] Final go/no-go decision.

## 3) Pre-Pilot Readiness Gate (Must Pass First)

- [ ] App builds clean: `xcodebuild build`.
- [ ] Tests pass clean: `xcodebuild test`.
- [ ] Backup/restore verified with one real dataset.
- [ ] No blocker bugs in launch, add/edit item, count session, quick actions, exception feed.
- [ ] Offline behavior verified with Wi-Fi and cellular disabled.
- [ ] At least one device with low battery mode tested.

## 4) Pilot Cohort Setup

- [ ] Recruit 3 pilot businesses (different inventory complexity).
- [ ] Assign one owner per location.
- [ ] Load initial catalog for each business.
- [ ] Define 3 mission-critical workflows per business.

Recommended profiles:
- [ ] Retail shop (fast turns, many SKUs).
- [ ] Stockroom/warehouse (larger counts).
- [ ] Service parts business (frequent adjustments).

## 5) Critical Workflow Validation (Must Execute Daily)

- [ ] Launch app and reach primary screen in <= 3 taps.
- [ ] Start count session and complete a zone count.
- [ ] Resolve at least one exception from Exception Feed.
- [ ] Create or update replenishment draft from detected risk.
- [ ] Adjust quantity and verify audit trail intent (who, what, when).
- [ ] Find an item by search in <= 10 seconds.
- [ ] Complete shift summary/KPI review.

## 6) Data & Reliability Validation

- [ ] Spot-check 20 SKUs per location against physical count.
- [ ] Verify no data loss after app restart.
- [ ] Verify no data loss after device reboot.
- [ ] Verify no data loss after forced app close.
- [ ] Verify same-day changes appear consistently in all relevant screens.
- [ ] Confirm no duplicate actions from repeated taps.

## 7) UX Validation (Grandmother Test)

- [ ] New user can complete first count without external help in <= 10 minutes.
- [ ] New user can find quick actions without instruction.
- [ ] Text, contrast, and tap targets are readable/usable for non-technical users.
- [ ] Error messages are clear and actionable.
- [ ] Help/instruction flow resolves confusion in under 2 minutes.

## 8) KPI Tracking Template (Per Pilot, Per Day)

- [ ] `count_time_minutes`
- [ ] `items_counted`
- [ ] `exceptions_opened`
- [ ] `exceptions_resolved`
- [ ] `replenishment_actions_created`
- [ ] `stock_adjustments`
- [ ] `cycle_count_completion_rate`
- [ ] `shrink_dollars_flagged`
- [ ] `user_confusion_events`
- [ ] `app_crashes`

## 9) Severity Rules for Issues

- [ ] P0: Data loss, blocked counting, app crash at core workflow.
- [ ] P1: Wrong totals, failed save, repeated action bug.
- [ ] P2: Slow workflow, confusing UX, visual inconsistency.
- [ ] P3: Cosmetic issues.

Response SLA:
- [ ] P0 fixed in 24 hours.
- [ ] P1 fixed in 72 hours.
- [ ] P2/P3 batched weekly.

## 10) Go/No-Go Scorecard (End of Day 14)

Go to paid beta only if all are true:
- [ ] 0 open P0 issues.
- [ ] <= 2 open P1 issues.
- [ ] Time-to-count improvement >= 25%.
- [ ] Accuracy >= 98%.
- [ ] Crash-free sessions >= 99.5%.
- [ ] At least 2/3 pilot businesses agree to continue using and paying.

If any fail:
- [ ] Run one more 14-day cycle with focused fixes.

## 11) Immediate Execution (Today)

- [ ] Pick 3 pilot businesses and assign owners.
- [ ] Capture baseline metrics sheet.
- [ ] Run the pre-pilot readiness gate.
- [ ] Start Day 1 baseline logging.
