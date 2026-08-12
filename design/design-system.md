# BudgetBox Design System — "The Moonlit Ledger"

> The design language for BudgetBox. Read this before designing or building any screen.
> **v3 (2026-08-12).** Supersedes the beige paper Ledger (2026-07-31) and the violet
> "Lightning Ledger" (2026-08-11) — Krish rejected red and violet accents on device.
> Monochrome carries the identity now. Grounded in [research.md](research.md) plus
> CRED/NeoPop analysis.

## Concept

BudgetBox is still a **digital bahi-khata** — one person's daily ledger ritual — and the
object is the book at night in **moonlight monochrome**: lacquer black, warm ivory ink,
and the interactive accent is *light itself* — pure moonlit white, a weight brighter than
the text around it. No brand hue. The seal's vermilion and the two status inks are the
only color on any page, so when they appear they mean it. Dark is the primary identity;
day is the same book in a bright room (accent = ink at full black), never an inversion.

Structure borrows CRED/NeoPop's discipline (hard corners, dimensional pressable objects,
serif-over-sans) without its monochrome: the drama lives in huge serif numerals and one
electric accent. If a screenshot could belong to any other app, it has failed.

**The signatures:** the chop (an extruded, pressable stamp — the add button), calendar-leaf
date blocks, verdict chips, the seal ritual, pen-drawn chrome glyphs (never Material icons
in chrome), and words-as-nav.

## Palette

Tokens first: no raw hex in widgets, ever. Token *names* keep their ledger vocabulary.

### Roles

| Token | Night (primary) | Day | Role |
|---|---|---|---|
| `paper` | `#0B0A08` | `#F7F5F0` | App background. Lacquer black / warm paper-white. |
| `paper-raised` | `#161511` | `#FFFFFF` | Cards ("plates"), sheets, the keypad. |
| `ink` | `#EDE8DC` | `#1A1814` | Primary text. Warm ivory / iron ink. |
| `ink-faint` | `#97917F` | `#6F6A60` | Secondary text, captions, labels. |
| `rule` | `#272520` | `#E6E2D9` | Hairlines and the month table's grid. |
| `quill` | `#FFFDF6` | `#11100D` | **Moonlight.** All interactive ink — light itself, a weight brighter than text (night) / full-black ink (day). No hue, ever. |
| `seal` | `#E8402A` | `#C93A24` | The vermilion stamp. RESERVED: day-close seal, save-stamp, over-budget verdicts, destructive confirm. ≤2 per screen. Never brand/interactive. |
| `jama` | `#43C98D` | `#1E8F5D` | Credit marks and on-pace status. Small marks only. |
| `warn` | `#F2A64B` | `#B07E1E` | Projected-to-overrun status. |

Category identity comes from **glyphs and names, not hues**: status owns color; categories
own marks.

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

- **Plates, not paper rules.** Content that *reads the book back* (pace, upcoming, goals,
  grids) sits on `paper-raised` plates: **hard corners (radius 4–8), no outlines, no
  shadows** — the edge is the tone change. The hero and the ledger lines stay directly on
  `paper`. Cards-in-cards remain forbidden.
- **Hero hierarchy.** Every module leads with the number that decides something (what's
  *left*, what's *saved*), set large in Fraunces; the arithmetic (`spent of limit`) is a
  mono footnote; the verdict is a chip. Never `Label: value` at equal weight.
- **Calendar leaves.** A dated row leads with a torn-leaf block: month tiny over day large,
  hard-cornered, `paper` on a plate (or `paper-raised` on the page).
- **Verdict chips.** Status is a small hard-cornered chip: status ink on a 14%-alpha wash
  of itself. One per module.
- **Stamp blocks.** Chips/filters are lifted blocks (radius 6, `paper-raised`, no border);
  selected takes a 16% `quill` wash.
- **The chop.** Key action buttons are extruded: face + zero-blur offset shadow in the same
  hue darkened ~45%, collapsing on press. Reserved for the most important press on screen.
- **Chrome is drawn, never typed.** No Material icons in chrome — pen-drawn glyphs only
  (`pen_marks.dart`). Words-as-nav: lowercase section names, active in ink with a small
  square `quill` chip beneath.
- **The day is the unit.** Transactions group by day; today's page first. The month grid is
  a ruled table: shared hairlines, square cells, ink-wash fills.
- Radius: 0 page & rows · 4–8 plates/leaves/chips · 22 sheets · never 999 pills.
- Spacing: 4-based scale. Dark ships first; day is derived.

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
