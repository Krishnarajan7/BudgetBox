# BudgetBox Design Research — Synthesis

> 2026-07-31. Distilled from three sweeps: [onboarding](research/onboarding.md),
> [core screens](research/core-screens.md), [India + indie](research/india-indie.md).
> This file is the brief; the three research files are the evidence.

## The ten conclusions that drive BudgetBox's design

1. **The app authors, Krish edits.** The best onboarding (Copilot) never shows an empty screen — budgets, categories, recurring bills are pre-generated and demoted to review tasks. The setup ritual asks for a handful of facts (name, income, accounts, an archetype) and *renders a finished app* to correct, not a blank one to fill.

2. **Repeat logging is the whole game.** UPI reality: 5–15 entries/day, ~85% under ₹500, mostly the same merchants. The 5-second target is met by pinned one-tap repeats, title→category memory, and a calculator keypad — not by a faster form. Amount is the only required field. Long-press `+` is the power menu.

3. **Predictive, not descriptive, charts.** The premium tells are all forecasts: Copilot's pace line (solid actual vs dotted ideal), projection-colored budget bars (green on-pace / amber projected-over / red over / outlined pending), Cashew's dashed "today" marker. A chart that isn't a verdict is decoration.

4. **One color system per screen.** Either the category owns the hue or the status owns the hue, never both. Restraint is the strongest craft signal; color chaos was the exact critique of Copilot's own budget screen.

5. **INR correctness is identity.** `₹1,23,456` (2-2-3 grouping), `₹5L`/`₹1.2Cr` never `K`/`M`, `.00` hidden, DD/MM dates, FY Apr–Mar periods, salary-anchored months. These details signal "built for me" harder than any illustration. Store paise as integers; hand-roll compact formatting (intl's compactCurrency is Western).

6. **Serif display + sans body.** CRED proved it: in a category that is 100% geometric sans, a serif on headings and hero numbers is the cheapest differentiation and reads as taste, not template. Numbers are the hero at display size (Jupiter); labels shrink to captions.

7. **Home-cooked, not product-y.** Personal from inception: no carousel, no account creation, no rating prompts, no upsell surface, settings by intent not A–Z, hardcode what's true of Krish's life. Malleable: reorderable modular home (Cashew), editable categories, configurable input prompts. Data ownership visible: local DB, export, activity log, undo everywhere.

8. **Kind by default.** People quit tracking because of backlog shame and punitive UI. No red-by-default, no broken-streak banners, batch catch-up mode for missed days, "rough is fine" microcopy, non-judgmental voice. But transparent: the uncomfortable number (subscription creep, over-run) is surfaced, calmly.

9. **Small frequent celebration, one big moment.** Haptic + micro-spring on saves; count-up numbers during setup; a single earned "day closed" moment; the Sankey/story-recap as the monthly centerpiece (Groww Stories format). Never confetti inflation.

10. **Dual-theme is designed, not inverted.** Token shade ramps first (Jupiter/Europa), layered near-black surfaces (#0E0E11-ish, never pure black), chart ink desaturated ~10–15% in dark. Both themes are first-class from the first screen.

## What BudgetBox deliberately rejects

- Onboarding carousels, signup, paywalls, notification nags, referral cards — the entire acquisition layer.
- The 12-slice category pie chart, 3-across KPI tiles, gauges, gradient hero metrics, cards-in-cards.
- Progress bars for spending (completion metaphor on a depletion) — bars drain or show pace instead.
- Chat as a capture interface (Cleo proves chat is for questions, not logging).
- Feature-density shock: the life-app shell exists, but finance ships first and other modules reveal progressively (Actual's discoverability principle).

## The emotional brief

YNAB confers identity ("you are now a budgeter"); Cleo lets you choose the relationship; Monzo speaks progress like a person. BudgetBox's version: it greets Krish by name, speaks in a calm, wry, first-person-to-one-person voice, ends setup with a receipt of what *he* built, and delivers one unearned insight immediately ("at this pace you'll have ₹X by March"). The app is a home-cooked meal — stability, sovereignty, and one user's taste visible everywhere.
