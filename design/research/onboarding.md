# Research: Onboarding / First-Run Flows — Personal Finance Apps

> Researched 2026-07-31 via web (agent sweep). Brief: what the best apps do in the first 60
> seconds to feel personal — feeding BudgetBox's no-auth "setup ritual."
> Confidence note: Copilot, Monarch, YNAB, Revolut, Origin, Rocket Money details come from
> step-level teardowns or first-party help docs (reliable). Cleo design-system details come from
> a designer case study (solid); Emma is reconstructed from reviews (thinnest).

---

## 1. Per-App Breakdown

### Copilot Money (iOS/Mac, Apple Design Award finalist 2024)

**Flow:**
1. **Demo-first entry.** "Take Copilot for a spin before you connect a single account." You can wander a populated, fake-data version of the app before committing anything.
2. Value carousel → soft paywall (annual/monthly toggle, gift/referral code field) placed *during* onboarding, before real value.
3. **Connect accounts** via Plaid, with a "Not on Plaid?" escape hatch to manual entry.
4. **Auto-derived budget.** "Your initial budget is based on your historic spend, but you can edit it at any time." Same for category assignment and income detection.
5. **Auto-detected recurring transactions** surfaced during onboarding as a review list, not a data-entry task.
6. **Goals** created last, each linked to an existing account.
7. Post-onboarding: guided tour via dismissible modals; a "To Review" queue seeds the first habit loop. After ~30 reviewed transactions, "Copilot Intelligence" starts predicting categories.
8. Notification opt-in framed unusually well (per Kristen Berman's behavioral teardown).

**Distinctive best:** **It never shows you an empty screen.** Every artifact you'd normally author — budget amounts, categories, recurring bills, income — is pre-generated and demoted to a *review/edit* task. Onboarding is confirmation, not creation.

**Weakness:** leaves the hard, tedious steps un-gamified — "missed chances to make hard things more fun."

### Monarch Money

**Flow:**
1. **5-slide value carousel** ("See all your money in one place"; cash flow, forecasting, goals/budgeting, privacy). Teardown criticizes slides 3–4 as redundant.
2. **Jobs-to-be-done question:** "what are you here for?" — consolidated view / shared accounts / investment tracking / free-text "something else." Used to shape the experience.
3. Acquisition-source question.
4. Profile info **deliberately placed after** motivation questions (escalating commitment).
5. **Trial timeline screen** — visual timeline of trial start, reminder date, charge date. The best trust-building screen in the flow.
6. **Directed empty dashboard.** Dashboard renders with *only* "Add account" tappable; everything else locked until one account connects. The product itself is the wizard.
7. **Celebration animation on each successful account link.**
8. Manual assets afterward (home, car, crypto) so net worth "starts to look real."

**Distinctive best:** **The constrained dashboard** — the real UI ships in a degraded state where only the next correct action is tappable. No modal tour, no context switch, no "skip."

### YNAB

**Flow:**
1. Fork: jump in yourself, or take the **6-step guided workflow** with animated progress bar.
2. Steps map to the method, not the UI: build category template → collect your cash → give every dollar a job → practice.
3. **Method-first copy:** "take the money you have in your pile, and give every dollar a job, right down to zero." "We only add dollars you have right now."
4. Categories framed as authored-by-you: "add categories to the plan as they come to you over time" — explicitly permitting an incomplete first pass.
5. **Emotional framing:** "stress start to fade away," "your money coming into alignment with the life you want to live."
6. **Identity-conferring completion screen:** congratulates you for *becoming a budgeter*.
7. Drip email sequence: one short lesson per day, extending onboarding across weeks.

**Distinctive best:** **It onboards you to a philosophy, not a UI** — teaches four rules and hands you an identity label at the end. Highest emotional payload of any app here.

### Cleo

**Flow:**
1. Chat-native from first screen — onboarding *is* a conversation, one question at a time.
2. Connect accounts.
3. **Final step is a chat with the AI coach** asking where you want to start — a goal declaration in the app's own voice, not a form.
4. Immediately after connecting: **funny, personalized feedback on your actual spending** — first-session payoff.
5. **Mode selection: Roast vs Hype.** You choose the app's personality toward you.

**Design system (from the Cleo case study):** "big sister" persona; principles: *Be Fun & Quirky, Be Personal ("we're in this together"), Be Bold (authentic, not overly polished)*. **Handmade rather than geometric** illustration; custom chat icons; **"Super Type" full-screen illustration components for onboarding/modals/feedback**; chat **colours and skin transform per mode** — the chrome re-skins based on which Cleo you're talking to.

**Distinctive best:** **It lets you pick the app's attitude toward you, and re-skins itself accordingly.** Personalization isn't data collection — it's choosing a relationship.

### Emma (UK)

**Flow:** Sign-in → dropped **directly onto account-linking** (no carousel, no survey) → within ~2 minutes you're looking at a categorized breakdown of recent transactions. Budgets and subscription detection surface immediately after.

**Distinctive best:** **Speed to first real data — under two minutes to a populated view.** Also cited for a *dedicated permission-request screen* with a stated reason, rather than a bare system dialog.

**Weakness:** constant upgrade nudges "get old fast."

### Rocket Money

**Flow:** Three personalization questions ("Why did you sign up?", "What are your financial goals?", "How did you find us?") → spending info → link first account → **instant analysis on first link** (detected subscriptions + savings opportunities).

**Distinctive best:** **Payoff within seconds of the first connection.** "Here are the 7 subscriptions you're paying for" tells you something you didn't know about yourself before you've done any work.

### Origin

**Flow:** Name + email → plan → **"what is most important to you?"** (single priority question) → account connection → manual assets. Goals are *not* an onboarding step.

**Distinctive best:** **Restraint — one priority question, then straight to work**, on a minimalist heavy-whitespace canvas. Caution: reviewers still note the feature density "can seem overwhelming."

### Revolut

**Flow (from Raw.Studio / Craft Innovations analyses):**
1. Logo on white → bold welcome: *"Ready to change the way you money?"*
2. **Animated hero** — motion carries the brand claim before any copy.
3. Benefits carousel previewed before signup.
4. Micro-stepped flow — each step is one decision. Phone entry then **"Is this number correct?"** inline confirmation.
5. **Intent question rendered as emoji chips**, not dry checkboxes.
6. **Fast-track labeling:** where two paths exist, one is badged *"Faster."*
7. Real-time validation as delight (blur detection on document photos).
8. Username with inline availability check.
9. Permission asks reframed as protection/benefit ("Useful Ads Only" toggle).
10. **Card customization with live preview.**

**Distinctive best:** **Onboarding as storytelling with motion** — animation, verbed copy, emoji chips, live previews; inline confirmation as a trust device.

### Bonus: Monzo & Nubank (microcopy patterns)

- **Monzo:** DOB confirmed conversationally (*"That makes you 40 years old"* + inline edit). Spoken progress: *"That's 1 section down, 3 to go," "You're halfway there."* Emoji-labeled goal options. Permission ask: *"Share exciting things with me"* with **Yes/No equal visual weight**. Estimation explicitly permitted: *"enter an average or your best guess."* Escape hatches everywhere (*"I can't find my address"*). Recovery copy: *"mistakes happen!"*
- **Nubank:** *"como si fuera magia"* process copy; visible "Analizando tu información" progress state; *"¡Ya casi!"* milestones; **PIN setup split Create → Confirm with a celebratory "¡Listo!" screen**; you **choose your own billing date** — a small ownership handoff.

---

## 2. Cross-App Pattern Comparison

### Table stakes
| Pattern | Who |
|---|---|
| 3–5 slide value carousel before anything | Monarch, Revolut, Copilot |
| 1–3 personalization questions ("why are you here?") | Monarch, Rocket Money, Origin, Revolut, Cleo, Monzo |
| Account connection as the pivotal step | All |
| Security/privacy reassurance at the moment of the ask | All |
| Manual-entry fallback | Copilot, Monarch, Origin |
| Progress indication | YNAB (bar), Monzo (spoken), Revolut (micro-steps) |
| Goals/budget setup deferred until after data exists | Copilot, Rocket Money, Origin, Monarch |
| Notification permission asked in-flow with a reason | Emma, Copilot, Revolut, Monzo |

### Where they diverge
| Axis | Pole A | Pole B |
|---|---|---|
| **Who authors the budget** | App generates from history, you edit — Copilot, Rocket Money | You author, app teaches — YNAB |
| **Blank slate vs demo data** | Explore a fake populated app first — Copilot | Locked empty dashboard, one action allowed — Monarch |
| **Tone** | Calm, minimal, deferential — Copilot, Origin, Monarch | Loud, opinionated, funny — Cleo, Revolut |
| **Onboarding target** | The UI — Copilot, Emma, Monarch | A method/mindset — YNAB |
| **Question volume** | One question — Origin | Four-plus sections — Monzo, Rocket Money |
| **Pace** | Under 2 minutes to value — Emma, Rocket Money | Deliberate ritual — Monarch, YNAB |
| **Personalization payload** | Data about you — Monarch, Rocket Money | The app's personality toward you — Cleo (Roast/Hype) |

### What the best do differently
1. **They make the app do the authoring.** Copilot's budget-from-history is the highest-leverage idea in the category. Users confirm; they don't compose.
2. **They give an immediate, unearned insight.** Rocket Money naming your forgotten subscriptions; Cleo roasting your spending.
3. **They degrade the real UI instead of overlaying a wizard.** Monarch's one-live-button dashboard beats a modal tour.
4. **They confer identity at the end.** YNAB doesn't say "setup complete" — it says you are now a budgeter.
5. **They celebrate the mundane.** Monarch animates *every* account link. The unit of celebration is small and frequent.
6. **They give permission to be imperfect.** Monzo's "best guess" and YNAB's "add categories over time" remove the fear that a wrong first answer is permanent.
7. **They speak progress rather than draw it.** "1 section down, 3 to go" is a voice, not a widget.

---

## 3. Ranked Stealable Ideas for the No-Auth "Setup Ritual"

**1. Demo-data sandbox before the real setup — "Take it for a spin."** *(Copilot)* Launch straight into a fully populated fake month with a persistent bar: "This is sample data. Make it yours →". You see the payoff *before* paying the setup cost; tapping it wipes the sample and begins the ritual with the layout already familiar.

**2. Generate the first budget; make the user an editor, not an author.** *(Copilot)* No bank feed, so substitute: ask **one** number — monthly income — plus a lifestyle archetype (2–3 taps), then render a complete proposed budget with categories, emoji, and amounts filled. Copy: "Here's a starting budget. Nothing here is permanent."

**3. The one-and-only personalization question, in the first 15 seconds.** *(Origin, Monarch)* One thing that visibly changes the app — "What's this for? → Stop leaking money / Save for something specific / Just see where it goes" — and the answer actually reorders the home screen.

**4. Name entry that talks back.** *(Monzo, Revolut)* The instant the name is typed, the next screen greets them by it: "Alright, Krish. Let's set your money up." In a single-user app, the name is the entire brand of personalization.

**5. Currency as an identity moment, not a dropdown.** *(Revolut live preview, Nubank billing date)* A large live-updating sample amount that reformats as the currency is picked (₹1,24,500 → $124,500 → €124.500).

**6. Celebrate every account added, not the end of setup.** *(Monarch, Nubank)* Each account entered gets a short spring animation, a haptic tap, and the running net-worth number counting up — the counting number is itself the reward.

**7. Speak the progress.** *(Monzo)* A line of voice between steps instead of/alongside a bar.

**8. Permission asks as a designed screen with a stated benefit — and a real "No."** *(Emma, Monzo, Revolut)* For biometric/PIN this is the load-bearing screen: it's the *last* step, framed as "Lock it down" — protection of the thing they just built. Soft-ask first, system dialog only after yes.

**9. Grant permission to be imperfect, explicitly.** *(Monzo, YNAB)* Under the first amount field: "Rough is fine — you can change everything later."

**10. End with identity, not completion.** *(YNAB)* Not "Setup complete" but "Your box is set up, Krish. ₹X across 4 accounts, 6 budgets, 2 goals." — a receipt of what *they* built, then lock-it-down.

**11. Pick the app's voice.** *(Cleo)* Lightweight version: choose a tone for nudges and empty states — "Gentle / Blunt" — plus an accent colour. Two taps, permanently visible consequence.

**12. Deliver one unearned insight the moment setup ends.** *(Rocket Money, Cleo)* Derived from what they just entered: "At this budget you'll have ₹X left over each month — that funds [goal] by March 2027." The app must produce something the user didn't already know, or the ritual feels like data entry.

---

## 4. Anti-Patterns to Avoid

1. **Question stacking before any value.** 3–5 questions max, only about goals/use case — never demographics or attribution.
2. **Paywall (or anything serving you, not them) inside the flow.**
3. **No pause-and-resume.** A ritual with 15+ inputs must persist partial state and allow bailing to a half-built home screen.
4. **Redundant carousel slides.** Three slides with different promises beat five that overlap.
5. **Dead ends with no escape hatch.** Every picker needs a "custom / other" row.
6. **Blank-slate handoff.** Onboarding ends on an empty dashboard = classic failure. Pre-fill (Copilot) or lock-to-one-action (Monarch).
7. **Bare system permission dialogs at launch.** Defer + explain first; double opt-in lifts grant rates.
8. **Feature-density shock.** Show one section on day one; reveal the rest on later launches.
9. **Confetti inflation.** Haptic + micro-spring for small stuff; save the big moment for the end of the ritual.
10. **Unskippable multi-step sequences with no exit**; excessive fields before product access; dense text instead of visual storytelling.

---

## 5. Sources

- [Copilot Money — Quick Start Guide](https://help.copilot.money/en/articles/11157550-quick-start-guide)
- [Copilot: We Can Do Hard Things — Kristen Berman behavioral teardown](https://kristenberman.substack.com/p/copilot-we-can-do-hard-things)
- [Product Teardown: Monarch Money — John Stone](https://johnstone.substack.com/p/product-teardown-monarch-money)
- [Getting Started with Monarch — Help Center](https://help.monarch.com/hc/en-us/articles/360048393272-Getting-Started-with-Monarch)
- [YNAB — The Ultimate Get Started Guide](https://www.ynab.com/guide/the-ultimate-get-started-guide)
- [YNAB's Friendly UX Copywriting — GoodUX/Appcues](https://goodux.appcues.com/blog/you-need-a-budget-ynab-s-friendly-ux-copywriting)
- [How to Stop People from Skipping Your Onboarding (YNAB) — Built for Mars](https://builtformars.com/case-studies/ynab)
- [Cleo AI — product design case study (izzoul)](https://www.izzoul.com/product-design/cleo-ai)
- [Cleo App Review: AI Chatbot Banking UX Analysis — Vector](https://vector-digital.co.uk/cleo-app-lets-chat-bank-account/)
- [Emma App Review — Money to the Masses](https://moneytothemasses.com/banking/emma-review-is-it-the-best-budgeting-app)
- [Rocket Money Review 2026 — The Quality Edit](https://www.thequalityedit.com/articles/rocket-money-review)
- [Origin Review — Rob Berger](https://robberger.com/origin-review/)
- [Banking Onboarding Best Practices: Revolut, Nubank, Monzo — Craft Innovations](https://craftinnovations.global/banking-onboarding-best-practices-revolut-nubank-monzo/)
- [How Revolut Uses 4 Onboarding UX Tactics — Raw.Studio](https://raw.studio/blog/how-revolut-uses-4-onboarding-ux-tactics/)
- [I Studied the UX/UI of 200+ Onboarding Flows — DesignerUp](https://designerup.co/blog/i-studied-the-ux-ui-of-over-200-onboarding-flows-heres-everything-i-learned/)
- [Fintech Onboarding UX: Why 68% of Users Quit — The Skins Factory](https://www.theskinsfactory.com/uiux-design-blog/fintech-onboarding-ux-design)
- [Asking Nicely: 3 Strategies for Mobile Permission Priming — Appcues](https://www.appcues.com/blog/mobile-permission-priming)
- [15 Onboarding Micro-Interactions — UserGuiding](https://userguiding.com/blog/onboarding-microinteractions)
