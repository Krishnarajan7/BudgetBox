# BudgetBox Design System — "The Ledger"

> The design language for BudgetBox. Read this before designing or building any screen.
> Grounded in [research.md](research.md). 2026-07-31.

## Concept

BudgetBox is a **digital bahi-khata** — the Indian account ledger, rebuilt as one person's
daily ritual. Every screen is a page in Krish's book: ruled lines, ink numerals, a day that
gets closed with a stamp. The light theme is the ledger by daylight; the dark theme is the
same ledger under lamplight at night — one identity, two illuminations, never an inversion.

This is home-cooked software (Robin Sloan sense): personal from inception, no acquisition
surface, the author's taste visible in every corner. If a screenshot could belong to any
other app, it has failed.

**The one aesthetic risk:** money amounts are typeset like ledger entries — mono figures on
ruled lines, no cards, no tiles — and the interface's only true red is a stamp.

## Palette

Tokens first (Jupiter/Europa lesson): no raw hex in widgets, ever.

### Roles

| Token | Light ("day page") | Dark ("night page") | Role |
|---|---|---|---|
| `paper` | `#F2EFE8` | `#13151E` | App background. Warm unbleached paper / indigo-black night desk. Never pure white or pure black. |
| `paper-raised` | `#FAF8F3` | `#1B1E2A` | Sheets, the keypad, raised surfaces. |
| `ink` | `#1B2033` | `#E9E6DB` | Primary text. Indigo-black iron-gall ink / moonlit paper. |
| `ink-faint` | `#616682` | `#9A9EB4` | Secondary text, captions, labels. |
| `rule` | `#DDD8CA` | `#2A2E3E` | The ruled ledger lines. Hairlines, 1px, everywhere structure lives. |
| `quill` | `#2F4AB8` | `#8FA3FF` | The pen. Interactive ink: links, active states, selection, the FAB, focus. |
| `seal` | `#C6402E` | `#E86A50` | The vermilion stamp. RESERVED: day-closed seal, save-stamp, over-budget verdicts, destructive confirm. If `seal` appears more than twice on a screen, the screen is wrong. |
| `jama` | `#2E7D52` | `#5DB388` | Credit/income marks and on-pace status. Small marks only — never floods. |
| `warn` | `#A97B14` | `#D9A441` | Projected-to-overrun status (amber). |

Category identity comes from **icons and names, not hues** — one color system per screen
(research conclusion #4): status owns color; categories own glyphs.

Dark-mode rules: chart and accent ink desaturated ~10–15% vs light; surfaces are layered
indigo-greys; shadows become darker paper, never glows.

## Typography

| Role | Face (Flutter / google_fonts) | Mockup fallback | Usage |
|---|---|---|---|
| Display | **Fraunces** (optical size high, soft wonk) | Georgia, 'Iowan Old Style' | Hero amounts, screen titles, the wordmark, the monthly story. Old-style figures give handwritten-ledger warmth. |
| Body/UI | **Hanken Grotesk** | system-ui | Everything conversational: labels, buttons, settings, microcopy. |
| Ledger | **Spline Sans Mono** | ui-monospace, Menlo | Every tabular amount, date column, account number. Tabular by nature — columns align like a real book. |

Scale (mobile): display-hero 44/48 (Fraunces 560wght), display 32, title 22, body 16,
label 13 (Hanken 600, +0.4 tracking, sentence case — **never all-caps list items**),
ledger-amount 16 mono, ledger-total 20 mono.

**Number rules (identity-critical):**
- `₹` before the number, no space. Indian 2-2-3 grouping: `₹1,23,456`.
- Compact only at lakh+: `₹5.2L`, `₹1.4Cr`. Never K/M.
- `.00` hidden; paise shown only when non-zero.
- Hero amounts in Fraunces; every amount in a row/column in Spline Sans Mono tabular.
- Dates DD MMM (`14 Jul`); periods offer month, FY (Apr–Mar), and salary-anchored cycles.

## Structure

- **Rules, not cards.** Lists are ruled lines on paper — full-bleed hairlines (`rule`),
  generous 16dp side margins, no bordered boxes, no cards-in-cards, no shadows on rows.
  Elevation exists only for sheets and the keypad (`paper-raised` + soft shadow).
- **The day is the unit.** Transactions group by day: date + weekday left, day total right
  in mono, entries as ruled lines beneath. Today's page is always first.
- **Numbers in the spotlight** (Jupiter): the answer renders at display size; its label is a
  caption above it. Never `Label: value` at equal weight.
- Radius: 0 on the page and rows (ledger geometry), 12 on sheets, 999 on chips. One radius
  per role, not one radius everywhere.
- Spacing: 4-based scale (4/8/12/16/24/32/48).

## Signature elements

1. **The seal.** A small vermilion stamp mark (rounded-square outline, like a chop) that
   appears when a day is closed, when setup completes, and as the pressed state of "Save" —
   saving a transaction *stamps* it (scale-press + haptic + seal flash). Earned at most once
   per day for day-close; never confetti.
2. **The pace line.** Every budget surface draws solid-actual vs dotted-ideal with a marker
   at today (Copilot/Cashew synthesis). Bars are colored by *forecast*: `jama` on pace,
   `warn` projected over, `seal` already over; **outlined** bars = expected but not yet paid.
3. **The shelf.** Tapping the wordmark opens the life-app shelf — Money, Calendar, Notes,
   Focus, Journal, Vault as spines of books in the box. Only Money is bound in v1; the
   others are faint unbound sleeves ("still being written"). Progressive disclosure of the
   life app, zero tab-bar cost.

## Motion

- Curve: one spring (gentle, ~250ms) for everything. No bounce/elastic. Respect
  reduced-motion.
- Count-up numerals when a hero amount first computes (setup, day totals). Digits settle,
  never jitter (tabular figures).
- Saves: press-down 0.97 scale + haptic light + seal flash 300ms + the amount slides into
  its ledger line. No toasts for success — the ledger itself is the confirmation.
- Ink-in: new lines draw their hairline left→right (120ms) as entries append.

## Voice

Calm, wry, first person to one person, by name. The app is Krish's book, and it talks like
a sharp friend keeping it, in plain English.

- Greets by name; speaks progress ("Two accounts in. One to go.")
- Permission to be imperfect: "Rough is fine — everything here can be corrected."
- Transparent, never punitive: over-budget reads "Food is ₹840 past its line this month" —
  a fact on a page, not a red alarm. No streak-shaming, no backlog guilt; a missed span
  offers "catch up the quiet days?" batch entry.
- No exclamation marks in system copy. The seal is the celebration.

## Never (the anti-slop contract)

- No onboarding carousel, signup, paywall, rating prompt, promo card, notification nag.
- No 12-slice pie, no 3-across KPI tiles, no gauges, no gradient hero metrics, no
  glassmorphism, no purple-blue mesh gradients.
- No progress bars for spending (depletion ≠ completion) — pace lines and drained bars only.
- No `₹500K`, no `100,000`, no MM/DD, no `.00` noise, no `Label: value` rows.
- No red floods, no all-caps rows, no cards inside cards, no Inter-for-everything.
- No added taps to the most-repeated action, ever (Axio's sin). The add flow's tap count is
  a guarded budget: 3 taps for a repeat entry, ≤6 for a novel one.
