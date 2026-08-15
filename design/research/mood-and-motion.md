# Research: The Two-Axis Check-In & Gesture Motion — How We Feel, dissected

> Researched 2026-08-15 via web. Scope: How We Feel (the emotion check-in app) taken apart for
> **two things only** — (1) the *mechanic* of placing a feeling on an energy × pleasantness field
> and naming it precisely, and (2) the *motion craft* that makes a check-in feel like an object
> rather than a form. Its visual design language is explicitly **not** adopted (see §6).
> Framed for BudgetBox's Moonlit Ledger: monochrome, no brand hue, one spring, drawn chrome.
> Companion to [core screens](core-screens.md); design law is [design-system.md](../design-system.md).

---

## 1. What the app actually is (so we're citing facts, not vibes)

| | |
|---|---|
| **Maker** | The How We Feel Project, Inc. — a nonprofit founded 2020. Multidisciplinary team incl. Pinterest co-founder **Ben Silbermann**; scientific guidance from **Dr. Marc Brackett** and the **Yale Center for Emotional Intelligence** (the RULER approach). |
| **History** | Began 2020 as a *COVID symptom* tracker; relaunched 2021 as the emotion check-in app. The pivot matters: the check-in cadence was designed for epidemiological compliance before it was designed for feelings, which is why the flow is unusually cheap to complete. |
| **Model** | Free. No ads, no paywall, no premium tier, no account required for core use. |
| **Data stance** | On-device by default; anonymised sharing for research is **opt-in**. |
| **Recognition** | Finalist, **2024 Apple Design Awards** (Social Impact). |
| **Core object** | The **Mood Meter** — a 2D field of *energy* (vertical) × *pleasantness* (horizontal), four quadrants, **144 emotion words** in the current build (earlier ~100). Custom words can now be added. |
| **Also logs** | Sleep/exercise via HealthKit, physical sensations ("tight chest", "heavy shoulders"), water/caffeine/alcohol, reflections, voice memos, photos. |
| **Reads back** | Monthly calendar of daily marks, trend/pattern reports, weekly review, "Seasonal Snapshot" across three wellbeing dimensions. |

**The single sentence worth keeping:** it replaced *"rate your day 1–5"* with *"put your finger where
the day sat, then find its word"* — and that one change turns a rating into a statement.

---

## 2. The mechanic: why two axes beat a 1–5 row

### 2.1 The lineage is 50 years old and well-evidenced

- **Russell's circumplex model of affect** (1980) places emotion on two orthogonal axes — *valence*
  (unpleasant↔pleasant) and *arousal* (low↔high energy). ~14,000 citations; it is the default
  computational representation of affect.
- The **Affect Grid** (Russell, Weiss & Mendelsohn) operationalised it as a **9×9 grid** where you
  mark one point. Schubert's *2DES* made it interactive, with schematic faces at the corners and
  midpoints as legends.
- **Usability finding worth stealing verbatim:** in early interactive Affect Grids, subjects kept
  dropping their marker *exactly on the face icons* used as hints. The fix was to **move the legend
  glyphs outside the selection area** and put a border on the field. Any legend drawn *inside* a 2D
  picker becomes a magnet and corrupts the data.

### 2.2 Why the second axis earns its place

A 1–5 scale collapses two independent facts into one number. "Rough" is either *drained* or
*agitated*; "good" is either *calm* or *elated*. Those are opposite problems with opposite answers,
and a single row cannot tell them apart — which is exactly why a mood row's history reads as noise
after two months. Two axes make the same tap twice as informative at **zero extra taps**.

### 2.3 Naming is the actual payload

- **Affect labeling** (Lieberman, UCLA, fMRI): naming an emotion reduces amygdala activity and
  increases prefrontal engagement. Effect is **modest, not magic** — intensity is reduced, not
  removed. The distinction that matters: *labeling* is one brief precise word; *rumination* is open
  dwelling. A picker that asks for one word is the antidote to a journal box that invites the dwell.
- **Emotion granularity**: a 2026 28-day diary study found higher negative-emotion granularity
  predicted lower depressive symptoms and social anxiety. Apps that push toward *drained / restless /
  content* over *bad / okay / good* are doing the mechanically useful thing.
- Practical consequence: **the field is the input; the word is the record.** Store both.

### 2.4 Cadence and friction (the numbers)

- Optimal check-in frequency is **2–4/day**; ≥5/day *reduces* accuracy and *increases* abandonment.
- The consensus killer is friction: if logging takes more than a few seconds, most people quit inside
  two weeks. The best flows are "one anchor cue, frictionless input, one reminder, and a missed day
  treated as a data point, not a failure."
- **BudgetBox reading:** Krish's book is a *day* book, not an ESM study. **One anchored check-in per
  day** (the evening, next to the money) plus an optional second — never a nagging four.

---

## 3. How We Feel's check-in flow, step by step

1. Tap the check-in prompt (home, widget, or notification).
2. **Place the point** on the Mood Meter field → quadrant + rough position.
3. **Narrow to the word** — the quadrant's vocabulary surfaces; pick one (or add a custom one).
4. Optional steps, each skippable: what you were doing, who you were with, physical sensations,
   note/voice memo, photo, health data.
5. Save → returns to home; the day's calendar cell takes its mark.

**The two shortcuts that reveal the design's priorities:**
- **Press-and-hold the arrow** → save immediately, skipping every remaining step.
- **iOS: press-and-hold the emotion in the Mood Meter** → bypasses the check-in steps entirely.

That is the whole lesson in one gesture: *the long-press is the express lane*. Every optional step is
genuinely optional, and the fastest path is a single sustained touch. Compare our own law — "no added
taps to the most-repeated action, ever."

**What it gets wrong (do not copy):** the surrounding survey has crept — sensations, water, caffeine,
alcohol, exercise, HealthKit. Each is defensible alone; together they turn a 4-second act into a
form. The check-in survived because the express lane exists, not because the survey is good.

---

## 4. The motion inventory — what is actually animated

Catalogued from 60fps.design's capture set for the iOS app, the app's motion budget is spent on
**eight** moments, not everywhere:

| Animation (their names) | What class of motion it is | Transferable? |
|---|---|---|
| **Emotion Picker** | Gesture-driven 2D field; continuous tracking, snap-on-release | **Yes — the core steal.** |
| **Check-in Card Flip** | State change carried by a 3D flip, not a fade | Yes, in ledger terms (see §7.4). |
| **Seasonal Snapshot Blobs Scale Color** | Organic shapes scaling + colour-morphing as a period summary | No — blobs and hue are their identity, not ours. |
| **Story Burn Fire** | Destructive-confirm rendered as a *ritual* (burning a page) | **Yes, conceptually** — a destructive act deserves an animation, not a dialog. |
| **Onboarding** | Sequenced narrative motion, one idea per beat | Already our setup ritual's model. |
| **Splash** | Identity mark resolving | We have `splash_screen.dart` + wordmark ink-in. |
| **Exercise Start Screen** | Entering a focused mode; chrome recedes | Applies to `focus/`. |
| **Tools Card** | Card affordance responding to touch before commit | Already `Pressable`. |

**The read:** their motion budget goes to (a) the one continuous gesture, (b) mode changes, and
(c) ritual moments. Nothing animates for decoration in the list surfaces. That allocation is right
and matches our "every interaction needs felt motion, but the seal is the only celebration."

---

## 5. Motion principles to build against (the general craft, sourced)

**Fluid interfaces** (Apple, WWDC18 "Designing Fluid Interfaces" — still the canonical text):
1. **Responsive** — motion starts from the value currently on screen, never from a reset origin.
2. **Interruptible** — if a state change can be triggered mid-animation, the animation must accept it.
3. **Redirectable** — the object can be grabbed and reversed at any instant.
4. **Velocity handoff** — on gesture end, the finger's velocity seeds the simulation, so the object
   keeps the momentum the hand gave it.
5. **Rubber banding** — resistance past a valid bound: tracks the finger closely at first, resists
   progressively, snaps back on release. This is how a 2D field says "there is no outside" without
   an error message.

**Flutter mechanics:**
- `SpringSimulation` + `SpringDescription(mass, stiffness, damping)` from `package:flutter/physics.dart`
  drive a normal `AnimationController` via `.animateWith()`. Higher mass = more inertia, higher
  stiffness = faster oscillation, higher damping = less oscillation.
- Convert `DragEndDetails.velocity` (px/s) into normalised units before seeding the spring, or the
  motion will feel violently wrong on different screen sizes.
- Physics simulations **preserve velocity across target changes** — this is what makes a re-grab
  during settle feel continuous instead of snapping.
- Packages exist (`flutter_physics`, `springster`) but we should not add a dependency for one screen;
  `SpringSimulation` in core `motion.dart` is enough.

**Haptics** (Android haptics principles + iOS guidance, in agreement):
- Haptics are **information, not decoration**. Overuse gets the feature switched off system-wide.
- `selectionClick` for value changes as you scrub; `lightImpact` for small-object collisions/commits;
  reserve heavier notification patterns for outcomes.
- Timing must be **immediate** with the causing action or the causality breaks.
- **Our rule:** a check-in fires at most **two** haptics — one selection tick when the point crosses
  into a new named region, one light impact on commit. Nothing during free drag.

---

## 6. What we deliberately reject from How We Feel

Krish's call, and it is the right one — the mechanic is good, the dress is not ours.

- **Hue-as-identity.** Their whole system is the four coloured quadrants: red / yellow / blue / green.
  The Moonlit Ledger spends colour only on `seal`, `jama`, `warn`. **The field will be monochrome.**
  Colour cannot be the axis legend here; §7.3 solves that instead.
- **Blobs, gradients, soft organic shapes.** Directly against hard corners, no shadows, no gradient
  hero metrics.
- **The wellness voice** — "let's check in!", coaching strategies, mini-courses, exclamation marks.
  Our voice is calm and wry, first person to one person.
- **The survey creep** — sensations, water, caffeine, alcohol, HealthKit. The day thread already
  gathers facts from the other books automatically; we do not ask what we can read.
- **Social sharing / support-a-friend.** Single user, no social surface, ever.
- **Sentiment face icons.** ⚠️ **Existing debt:** `journal_page.dart:55` uses Material
  `Icons.sentiment_*_outlined` for the 1–5 row — a direct violation of "chrome is drawn, never typed."
  Whatever else happens, that row's glyphs owe a `pen_marks.dart` replacement.
- **Seasonal snapshots / scored wellbeing dimensions.** We do not score a person. We report and stop.

---

## 7. The BudgetBox translation — "how it felt", two axes, no colour

### 7.1 Where it lives (recommendation)

| Candidate | Verdict |
|---|---|
| **Daily → `_FeltCard`** (`daily_page.dart:1146`) | **Build it here.** Daily *is* the day-object page; it already owns the felt card, already writes `journalRepo.upsert(key, mood:)` at `daily_page.dart:281`, already sits beside habits/meals/the day thread, and already scrolls five weeks back — so a missed day is caught up in place, not shamed. |
| **Journal editor** (`journal_page.dart`) | **Second, read-mostly.** The editor shows the chosen word inline on the dateline ("*restless* — Friday, 31 July") and lets you re-open the field, but the field's home is Daily. Journal is for words; the picker is for the mark. |
| **Today** | **A single line, no picker.** Today is the money home; it earns one quiet deferred line in the evening ("the day's not marked yet") that pushes to Daily. Today must not grow a second input surface — its module order is already spoken for. |

### 7.2 The field itself

- A **square field** on a `paper-raised` plate, hard corners (radius 4–8), no outline, no shadow —
  the edge is the tone change, per the plate rule.
- **X = pleasantness** (rough → good). **Y = energy** (still → wired). Axis words set in Hanken
  label size, lowercase, sentence case, **outside the field** — never inside it (the Affect Grid
  magnet finding, §2.1).
- **No quadrant fills.** Structure comes from a **hairline cross** in `rule` at the centre and a
  faint 9×9 tick lattice at the field edges only — the same ruled-table vocabulary as the month grid.
- The mark is a **single drawn point in `quill`** with a soft radial wash. Moonlight *is* the accent;
  the field stays dark and the choice is the only bright thing on the plate.
- The word appears **beneath** the field in Fraunces at title size — the hero of the card is the
  word, not the dot. (Hero hierarchy: the thing that decides something is the thing set large.)

### 7.3 Encoding two dimensions without hue (the monochrome problem, solved)

The month grid currently tints a dot by mood 1–5 (`journal_page.dart:835`). With two axes and no
colour, use **separable dimensions** — the visualisation literature is explicit that bivariate
glyphs work when the two channels are perceptually separable (shape vs lightness), and that
quantitative encodings should be **monotonic in luminance**:

- **Pleasantness → ink luminance** of the mark (faint `inkFaint` at rough, full `ink`/`quill` at good).
  Monotonic, reads instantly, works in both themes.
- **Energy → mark form**, drawn by `pen_marks.dart`: a **low, flat dash** at still; a **taller,
  narrower upright tick** at wired; the neutral is a square. Same ink density at every step so no
  row of the month visually shouts louder than another (the "consistent ink density" balance rule).

That gives a month grid where you read *mood* by brightness and *energy* by the shape of the stroke —
two facts, one monochrome table, zero hue. It also finally makes the month grid worth looking at.

### 7.4 Motion spec (this is the part Krish wants)

Every number below is inside the existing envelope: one spring ~250ms, no bounce, reduced-motion
respected via `Motion.reduced(context)` / `MediaQuery.maybeDisableAnimationsOf`.

1. **Open — the field rules itself in.** The plate arrives, then the centre hairlines **draw**
   left→right and top→bottom (`DrawIn`, 120ms each, 60ms apart), then the axis words `InkIn` at
   +200ms. The field is built in front of you like a ruled page, not faded in.
2. **Touch down.** The mark appears *under the finger immediately* — responsive means starting from
   where the touch is, with no entry animation to wait through. Existing point (if any) does not
   jump: it **springs** from its old position toward the finger, so you see your last answer move.
3. **Drag.** The mark tracks 1:1. Its radial wash grows slightly with distance from centre (intensity
   reads as commitment). Past the field bounds it **rubber-bands** — tracks at a diminishing rate,
   never leaves. **No haptic during free drag.**
4. **Crossing a named region.** As the point enters a new word-neighbourhood, the word beneath the
   field **cross-fades and re-inks** (`InkIn`, 120ms) and a single `selectionClick` fires. This is
   the moment the interaction stops being a slider and starts being a vocabulary.
5. **Release.** `SpringSimulation` seeded with the release velocity, settling to the nearest lattice
   point (9×9 → a stable, recordable value). Gentle spring, **no overshoot past 1.0** — our system
   forbids bounce, so use high damping and let the *velocity*, not the wobble, carry the feel.
6. **Re-grab mid-settle.** Must be interruptible and redirectable — grab it again and it continues
   from its current position with its current velocity. This single behaviour is 80% of why the
   interaction will feel expensive.
7. **Commit.** The word slides up into the card's dateline and the field collapses to a one-line
   summary (their "card flip", in our idiom: a **ruled fold**, not a 3D flip). `lightImpact`, and
   the day's cell in the week table takes its new mark with an `InkIn` hairline.
8. **Clear/undo.** The mark doesn't vanish — it **fades to a scratch-out** (a single pen stroke
   through it, `pen_marks.dart`), then the cell empties. Corrections are visible in a real book.
9. **Reduced motion:** all of the above collapses to instant state changes; the haptics stay. Never
   ship a motion path that is the *only* carrier of meaning.

### 7.5 The vocabulary

- **Not 144 words.** For one user, that is a search problem, not a naming aid. Target **48–64**,
  12–16 per quadrant, and let Krish add his own (the app authors, Krish edits).
- Words must survive the voice test: plain, unclinical, natural in Indian English, no therapy-speak.
  - *still + good*: settled, easy, rested, unhurried, content, quiet
  - *wired + good*: keen, charged, sharp, up for it, restless-in-a-good-way, buoyant
  - *still + rough*: flat, drained, dull, heavy, low, hollow
  - *wired + rough*: rattled, wound up, on edge, short-tempered, frayed, scattered
- The word is stored alongside the coordinates. Reports quote *words*, never quadrant names —
  "eleven days were *frayed*" is a sentence; "Q2: 11" is a spreadsheet.

### 7.6 Data & backend

- `JournalEntries` currently: `mood int? // 1 (rough) … 5 (great)` (`tables.dart:182`).
  Add `energy int?` (1–9), rename the intent of `mood` → `pleasant int?` (1–9), add `feelWord text?`.
- **Migration is free:** existing `mood` 1–5 maps linearly onto pleasantness 1–9 with `energy = null`;
  a null energy renders as the neutral dash. No data is thrown away and no screen breaks.
- Mirror in the backend `journal` module + a new alembic revision; `openapi.json` stays the contract.
- `moodMoneyWhisper` (`journal_page.dart:126`) keeps its honesty guards (3 days a side, 20% gap) but
  gains a **second, better** question: *does spending track energy rather than pleasantness?* That is
  the genuinely useful projection — "the wound-up days cost more" is actionable in a way that "the
  rough days cost more" is not. Keep the silence-by-default rule: no gap, no line.

### 7.7 The friction budget (non-negotiable)

- Marking the day: **one press-drag-release. One gesture. Zero extra taps.**
- The express lane, borrowed directly: **long-press the field → commits the point without opening
  the word list.** The word is optional; the coordinates are the record.
- Never blocks the journal, never a modal on launch, never a notification that says "check in!"
  The evening reminder, if any, reuses the existing day-close/seal moment.

---

## 8. Decisions (locked 2026-08-15, Krish)

1. **Cadence: one evening mark.** The ledger's unit is the day, so the day gets one mark. The field
   stays re-openable any number of times — last write wins, no "you changed your mind" copy, no
   second prompt. Rejects the 2–4/day research optimum deliberately: this is a day book, not an ESM
   study, and a second daily prompt is a second thing to ignore.
2. **Not coupled to the seal.** The seal closes the *money* day; the felt-mark stays voluntary and
   uncoupled. An unmarked day must never read as an unfinished one, and the close flow gains no step.
3. **Continuous drag, snapped on release.** Free 1:1 tracking under the finger; the spring settles to
   the nearest node of a 9×9 lattice, and that node is what's stored. Months stay comparable, the
   motion stays fluid, and the spring has something to land on. (§7.4 step 5 is the spec.)
4. **Home is Daily's `_FeltCard`.** Journal shows the chosen word inline on the dateline and can
   re-open the field; Today gets exactly one deferred line ("the day's not marked yet ›") and never
   grows a picker.

Still to settle when the card is drawn: the exact word list (§7.5 is a starting draft, not a ruling),
and whether the week table's marks get the two-channel encoding from §7.3 at the same time or after.

---

## 9. Addendum (2026-08-15, same day): the field is dead — long live the cloud

The abstract 2D gradient field (§7.2–7.4) was built and rejected on sight ("AI slop"). Krish
supplied How We Feel screenshots as the bar, and the surface was rebuilt to match their *actual*
body, not an abstraction of it:

- **The picker is a room of words, not a field.** A full-screen pannable canvas
  (`feel_picker.dart`) holding the whole vocabulary as big coloured rounds — strong words large
  and vivid, mild words small and sand-pale — packed by a deterministic relaxation
  (`feelBubbleLayout`). You move through the cloud and press the word that fits; the coordinates
  (§7.6's schema, unchanged) ride along underneath.
- **The pick is the ceremony.** The chosen round swells a fifth and morphs from a circle into
  its word's own seeded blob shape (`feelBlobPath` — every word always draws the same shape,
  like a pen glyph), glows in its own colour, and a bottom pill surfaces the word + a one-line
  definition with the arrow that commits.
- **The invitation is a ring of light.** Unmarked days wear `CheckInRing` — the four families
  as one blurred sweep-gradient ring, turning once every 36 seconds — with "check in" at its
  centre (their home screen's move, in our families).
- **Colour system:** `feelBubbleColor` — quadrant blend at full voice in the corners, paling to
  warm sand at the middle. `feelAtmosphere` (a darkened variant) stays on small marks: month
  dots, list chips.
- Every word gained a **hint** — a plain one-breath definition in the book's voice.
- `felt_field.dart` deleted. The drag/spring/rubber-band spec of §7.4 survives only where it
  now applies: the cloud's pan physics and the swell.
- **The second breath** (same session): after the arrow commits the word, the room turns a page
  — HWF's post-check-in step, ours: three chip groups (*what were you doing / who with / where*,
  Krish's life not a wellness template, multi-pick, chips take the word's own colour when
  picked), plus a *"why did it sit that way?"* free line. All optional — the word is saved
  before the step opens, "complete check-in" adds `feelWhy` + `feelTags` (comma-joined; Drift
  v12 / alembic 0011), back-arrow returns to the cloud, cross skips. The water room and this
  live in `water_page.dart` / `feel_picker.dart`.
- **Daily de-boxed** (same session): the check-in moved to the page's top-right corner (mini
  ring unmarked / word-blob marked, key `felt-mark`), the "how it felt" card is gone (the word
  lives in an open "the page" section beside the journal line), and every Daily section shed its
  `LedgerCard` plate — sections now sit straight on the paper, ruled apart by their headers'
  hand-drawn lines alone. Krish's read of stacked plates: "dead boxes boxes feeling."

---

## Sources

**How We Feel — product & provenance**
- [How We Feel — App Store](https://apps.apple.com/us/app/how-we-feel/id1562706384)
- [How We Feel — Google Play](https://play.google.com/store/apps/details?id=org.howwefeel.moodmeter&hl=en_US)
- [Marc Brackett — the How We Feel app](https://marcbrackett.com/how-we-feel-app-3/)
- [Ben Silbermann on launching the nonprofit app](https://www.linkedin.com/posts/silbermann_this-year-i-helped-launch-a-non-profit-app-activity-7009184042298335232-YEIu)
- [Pinterest CEO partners with doctors to launch How We Feel (2020 origin)](https://www.businesswire.com/news/home/20200402005761/en/Pinterest-CEO-Ben-Silbermann-Partners-With-Leading-Doctors-and-Scientists-to-Launch-How-We-Feel-an-App-That-Lets-Everyone-Help-Track-and-Fight-COVID-19)
- [The How We Feel App: Harnessing Emotional Awareness — themoodmeter.com](https://www.themoodmeter.com/the-how-we-feel-app-harnessing-emotional-awareness-for-a-healthier-mind/)
- [How We Feel Review 2026 — Selfpause](https://www.selfpause.com/resources/how-we-feel)
- [Wireframing the How We Feel app: a look into the user flow — Nina Koplyk](https://medium.com/design-bootcamp/wireframing-the-how-we-feel-app-a-look-into-the-user-flow-b04583041f6d)
- [Ch-Ch-Ch-Changes — How We Feel Substack](https://howwefeel.substack.com/p/ch-ch-ch-changes)
- [2024 Apple Design Award winners & finalists](https://www.apple.com/newsroom/2024/06/apple-announces-winners-of-the-2024-apple-design-awards/)

**Motion inventory & craft**
- [How We Feel iOS app UI/UX animations — 60fps.design](https://60fps.design/apps/how-we-feel)
- [Designing Fluid Interfaces — WWDC18 session 803](https://developer.apple.com/videos/play/wwdc2018/803/)
- [Building Fluid Interfaces — Nathan Gitter](https://medium.com/@nathangitter/building-fluid-interfaces-ios-swift-9732bb934bf5)
- [10 Principles for Fluid UI — Karl Koch](https://karlkoch.me/writing/10-principles-for-fluid-ui)
- [SpringSimulation — Flutter API](https://api.flutter.dev/flutter/physics/SpringSimulation-class.html)
- [Flutter physics simulation in animation — GeeksforGeeks](https://www.geeksforgeeks.org/flutter-physics-simulation-in-animation/)
- [flutter_physics package](https://pub.dev/packages/flutter_physics) · [springster package](https://pub.dev/packages/springster)
- [Haptics design principles — Android Developers](https://developer.android.com/develop/ui/views/haptics/haptics-principles)
- [Haptic feedback UI guidelines for iOS](https://vp0.com/blogs/haptic-feedback-ui-design-guidelines-ios)

**The science under the mechanic**
- [The Circumplex Model of Affect — MorphCast](https://www.morphcast.com/blog/circumplex-model-of-affects/)
- [Russell's Circumplex Model of Affect explained](https://www.manifested.me/blog/russells-circumplex-model-explained)
- [The Valence–Arousal Model](https://imentiv.ai/blog/the-valencearousal-model-a-simple-map-to-understand-complex-human-emotions/)
- [EmojiGrid: a 2D pictorial scale (Affect Grid lineage, legend-magnet finding)](https://pmc.ncbi.nlm.nih.gov/articles/PMC6279862/)
- [Using the Circumplex Model to study valence and arousal ratings](https://pmc.ncbi.nlm.nih.gov/articles/PMC4301408/)
- [Putting Feelings Into Words — Lieberman et al., UCLA (affect labeling fMRI)](https://teams.semel.ucla.edu/sites/default/files/publications/May%202007%20-%20Putting%20Feelings%20Into%20Words.pdf)
- [Affect labeling: the fMRI evidence behind "name it to tame it"](https://cortexos.app/library/why-naming-an-emotion-reduces-its-intensity/)
- [Best mood tracking apps 2026 — friction & abandonment data](https://moodgrade.com/en/blog/best-mood-tracking-apps-2026)
- [7 best mood tracking apps 2026 — granularity study, check-in cadence](https://habitbox.app/blog/best-mood-tracker-app)

**Monochrome bivariate encoding**
- [Bivariate separable-dimension glyphs improve visual analysis](https://arxiv.org/pdf/1712.02333)
- [Design characterization for black-and-white textures in visualization](https://www.researchgate.net/publication/372468821_Design_Characterization_for_Black-and-White_Textures_in_Visualization)
- [Typography as a data visualization encoding channel](https://www.sciencedirect.com/science/article/pii/S2405872616300107)
