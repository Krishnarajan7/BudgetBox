# BudgetBox — Screen Inventory & Flows

> v1 scope: full life-app shell designed, finance built deeply first. 2026-07-31.
> Visual language: [design-system.md](design-system.md).

## Shell

- **Nav:** bottom bar, 4 slots + FAB. `Today` · `Book` (transactions) · `[+]` · `Plans`
  (budgets/subscriptions/goals) · `Worth` (accounts/net worth/insights).
- **The shelf:** tapping the "BudgetBox" wordmark (top-left, every root screen) opens the
  module shelf — Money (bound), Calendar/Notes/Focus/Journal/Vault (unbound, "still being
  written"). Future modules dock here; the finance nav never pays for them.

## 1. Setup ritual (first launch only, ~90 seconds)

Principle: the app authors, Krish edits (research #1). One question per page, spoken
progress, partial state persists. No carousel.

1. **Cold open** — paper, the wordmark inks itself in, one line: "This book belongs to…"
   → name field. Next page greets by name.
2. **The one question** — "What should this book watch for?" → chips: *leaks* / *a goal* /
   *just the truth*. Answer reorders the Today page modules.
3. **Money in** — monthly income (keypad, "rough is fine"), salary day → enables
   salary-anchored months and "runway."
4. **Accounts** — quick-add rows (bank/UPI/cash/card), each entered account inks a line and
   the running total counts up. "Two in. Add another, or move on."
5. **The proposed book** — from income + archetype, a *finished* budget renders: ~6
   categories with amounts pre-filled, each editable inline. "Nothing here is permanent."
6. **Goal (optional)** — one goal card: name, target, and it immediately answers back:
   "₹4,000 a month gets you there by March 2028."
7. **Lock it down** — designed screen, benefit-first: "This book locks. Only your face
   opens it." → biometric enroll (soft-ask before the OS dialog), PIN fallback.
8. **The receipt** — "Your box is set up, Krish." — summary of what *he* built (₹X across
   N accounts, M budgets, one goal), the first unearned insight ("at this budget you keep
   ₹X a month — [goal] lands in March"), then the seal stamps the page. Ends on Today.

## 2. Lock screen (daily entry)

Paper, wordmark, date in Fraunces, biometric fires immediately; PIN pad (ledger keypad
style) as fallback. No balance shown while locked.

## 3. Today (home)

```
BudgetBox ▾                    ⚙
to-day, 14 Jul                    ← caption
₹340 spent so far                 ← Fraunces hero, counts up
[ + chai ₹20 ] [ + auto ₹60 ] …   ← pinned repeats, one-tap stamp
——— this month ————————————————
₹18,240 of ₹30,000  ·  on pace    ← pace line: solid vs dotted, today-marker
——— coming up ─────────────────
18 Jul  Netflix      ₹649   (outlined = not yet paid)
 1 Aug  Rent         ₹15,000
——— today's page ──————————————
09:12  chai · cash            ₹20
12:40  lunch, Saravana        ₹180
14:05  auto to office         ₹140
                    [ close the day ⬚ ]   ← seal, once/day
```

Modules (reorderable, long-press): today strip+pinned, month pace, upcoming, today's page,
goal progress. "Close the day" stamps today's ledger page — the daily ritual reward.

## 4. Add transaction (the sacred flow — tap budget: 3 repeat / ≤6 novel)

Sheet over the current screen; keypad owns the bottom half, visible on open.

```
˅
₹ 180                              ← Fraunces, live
180 = 120 + 60                     ← running expression line
[food] [auto] [chai] [groc] [more] ← top-5 chips by *his* frequency
Saravana Bhavan                    ← title, autocompletes; carries category
cash ▾ · today ▾ · details ›       ← defaults; details = notes/split/photo/goal
7 8 9   ÷
4 5 6   ×          [ stamp ✓ ]     ← save = stamp; long-press = save+add another
1 2 3   −
0 . ⌫   +
```

- Amount is the only required field. Date=today, account=primary, type=expense.
- Title→category memory; partial-match autocomplete.
- Long-press the FAB anywhere: pinned repeats, transfer, balance correction, income.
- Catch-up mode (from any missed-days prompt): compact multi-row sheet, one line per entry.

## 5. Book (transactions)

Day-grouped ruled ledger, sticky month header with month total + FY/月 selector, search +
filter chips (category/account/type). Row: time · title · account chip · mono amount;
`R` mark for recurring; swipe → edit/delete; long-press → duplicate. Alternate view toggle:
**heatmap** (month grid, cell tint = spend intensity, pale = no-spend day).

## 6. Plans (budgets · subscriptions · goals) — segmented root

- **Budgets:** month pace hero, then categories sorted by spend desc — bar colored by
  forecast (jama/warn/seal, outlined = pending recurring), remaining in mono. Tap amount =
  inline edit. Two budget types: monthly (all matching) vs one-off "trip book" (added only).
  Monthly rebalance action redistributes to match behavior, total unchanged.
- **Subscriptions:** hero = "₹3,247 of this month already spoken for" (committed spending),
  Upcoming / All / Calendar toggle — calendar shows salary day too. Bills vs subscriptions
  as separate groups; yearly cost normalized per month.
- **Goals:** one card per goal — name, mono `saved / target`, thin fill, ETA sentence
  ("on pace for March 2028"). "Add to this" opens the keypad pre-filled with the goal.
  Goals are views over tagged transactions, never a separate ledger.

## 7. Worth (accounts · net worth · insights) — segmented root

- **Accounts:** ruled rows — name, "as of 12 Jul" staleness caption (gentle nudge at 30+
  days), mono balance, 40×16 sparkline. Tap = update-balance keypad sheet.
- **Net worth:** Fraunces hero + delta chip, range-selectable area chart (1M/6M/FY/all),
  assets and liabilities as two collapsible ruled groups.
- **Insights:** the **monthly story** — a swipeable 5-page recap (Groww Stories format):
  spent total → top category → biggest day → subscriptions renewed → verdict vs last month
  ("₹6,800 lighter than June"), ending in a **Sankey** (income → categories) with an
  amounts-hidden mode. Plus projections in the app's voice: "at this pace, ₹4.2L by next
  Diwali." Genuinely-useful-only rule: no stat without a consequence.

## 8. Settings ("the box")

By intent, not A–Z: My book (categories, accounts, pinned entries, input prompts order) ·
Rhythm (salary day, FY vs calendar, reminders) · Lock (biometric, PIN, auto-lock) · The
data (export CSV, backup file, activity log, undo history) · Appearance (day/night/auto,
accent). Every list has a "custom / other" escape hatch.

## Later modules (designed as shelf spines only in v1)

Calendar · Notes · Focus · Journal · Vault — each gets its own page style on the same
paper/ink/rule system when its time comes.

## Flows to mock (for the approval artifact)

1. Setup ritual: cold open → question → income → accounts → proposed book → receipt.
2. Lock → Today.
3. Add: pinned one-tap; novel entry with calculator + autocomplete.
4. Book with day groups + heatmap toggle.
5. Budgets with pace + forecast bars.
6. Subscriptions (committed hero + calendar).
7. Net worth + accounts staleness.
8. Monthly story + Sankey.
9. The shelf.
