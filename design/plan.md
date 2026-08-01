# BudgetBox — Flutter Build Plan

> Approved design: [design-system.md](design-system.md) + [screens.md](screens.md) +
> mockups (artifact "The Ledger"). 2026-07-31.

## Architecture

- **Flutter 3.44 / Dart 3.12**, targets: Android + iOS (macOS/web kept enabled for dev preview).
- **Local-first, no server.** Drift (SQLite) on device. Export = CSV + a copyable DB backup.
  No network permission needed in v1 at all.
- **State:** Riverpod. **Routing:** go_router. **Biometric:** local_auth (+ PIN hash in
  flutter_secure_storage). **Haptics:** HapticFeedback (light impact on stamp).
- **Fonts bundled as assets** (variable TTFs: Fraunces, Hanken Grotesk, Spline Sans Mono) —
  offline-complete, no google_fonts runtime fetch.
- **Money:** integer paise everywhere (`int`), one `Inr` formatter (2-2-3 grouping, `₹5.2L`
  `₹1.4Cr` compaction, `.00` hidden). Unit-tested first, used everywhere, never inline.

## Module layout

```
lib/
  core/
    tokens.dart        # LedgerColors day/night, spacing, radii — no raw hex outside
    typography.dart    # Fraunces/Hanken/Spline roles + scale
    theme.dart         # ThemeData day + night from tokens
    inr.dart           # the money formatter (tested)
    haptics.dart, motion.dart (the one spring)
    widgets/           # RuledList, LedgerRow, RuleHeader, Seal, PaceChart, HeroAmount…
  data/
    db.dart            # Drift database + migrations
    tables.dart        # accounts, categories, transactions, budgets, recurring, goals,
                       # pinned_entries, settings, activity_log
    repos/             # transaction_repo, budget_repo (pace/forecast math), …
  features/
    splash/  lock/  setup/  today/  add/  book/  plans/  worth/  story/  shelf/  settings/
```

## Schema (v1)

- `accounts(id, name, kind bank|upi|cash|card|asset|liability, balancePaise, asOf, sortOrder, archived)`
- `categories(id, name, emoji, kind expense|income, sortOrder, archived)` — his categories, editable
- `txns(id, amountPaise, type expense|income|transfer, categoryId?, accountId, toAccountId?,
  title, note?, at, goalId?, recurringId?, createdAt)`
- `recurring(id, title, amountPaise, categoryId, accountId, cadence, nextDue, kind bill|subscription, active)`
- `budgets(id, categoryId?, name, limitPaise, period month|fy|custom, kind all|added, rollover)`
- `goals(id, name, targetPaise, kind save|clear, targetDate?, monthlyPaise?)`
- `pinned(id, title, amountPaise, categoryId, accountId, sortOrder)`
- `day_seals(date, sealedAt)` — the once-daily close
- `activity(id, txnId, action created|edited|deleted, snapshot json, at)` — undo + audit
- `settings(key, value)` — name, salaryDay, theme, lock config, prompt order

## Build order (each milestone ends runnable)

1. **Foundation** *(now)* — scaffold, tokens, themes, bundled fonts, `Inr` + tests,
   splash (wordmark ink-in → seal stamp on plain paper — Krish vetoed the ruled-line
   backdrop, ~2.1s, skippable), app shell
   with bottom nav + placeholder screens.
2. **Data layer** — Drift tables, repos, seed categories, activity log + undo.
3. **The sacred flow** — add-transaction sheet (keypad + expression line, chips by
   frequency, title→category memory, save-stamp animation + haptic, save-and-add-another),
   pinned repeats + long-press FAB menu. Widget-test the tap budget (3 repeat / ≤6 novel).
4. **Book** — day-grouped ledger, month header, search/filters, swipe edit/delete,
   long-press duplicate, heatmap view.
5. **Today** — hero count-up, pinned strip, pace chart, upcoming, close-the-day seal.
6. **Plans** — budgets (pace + forecast coloring + outlined pending + rebalance),
   recurring (committed hero, bills vs subscriptions, calendar), goals (fed by tagged txns).
7. **Worth** — accounts with as-of staleness + sparklines, update-balance sheet, net worth
   chart, assets/owed groups.
8. **Setup ritual + lock** — the 8-page ritual (built late so it fits the real screens),
   biometric/PIN gate, partial-state persistence. Until then, dev-seed data.
9. **Story + polish** — monthly story pages, Sankey, projections; motion/haptics pass;
   both themes audited screen by screen against the mockups.
10. **Later** — home-screen widget + quick-add shortcut (the biggest speed lever),
    CSV import, then the shelf modules (calendar, notes, focus, journal, vault).

Setup ritual intentionally comes late: it produces data the other screens consume, so the
screens must exist first; dev builds seed a fake month instead.

## Working rules

- Follow `.claude/skills/budgetbox-design/SKILL.md` for every screen. Mockups are the spec.
- Tests: `Inr` formatter, budget pace/forecast math, add-flow tap budget, DB migrations.
- Krish decides commits; default is work-in-tree.
