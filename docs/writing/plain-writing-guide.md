# Plain writing guide

How to write product copy, docs, and UI text that doesn't read like it came out
of a language model. Project-agnostic: copy this file into any repo and point
agents and humans at it.

The test for every sentence: would a busy person say this out loud to a friend?
If not, rewrite it.

## The tells (don't do these)

1. **Em dashes everywhere.** LLMs squeeze them between clauses constantly — like
   this — often several per paragraph. Use a comma, a period, or parentheses.
   If a dash feels essential, the sentence usually wants to be two sentences.

2. **The "not X, but Y" pivot.** "It's not an app, it's a way of life." "Split
   trips, not friendships." Punchy once, machine-generated at scale. Say the
   true thing directly instead.

3. **Fragments for drama.** "All of it. Forever. No catch." Real people write
   complete sentences and vary their rhythm naturally, not for effect.

4. **Triads.** "Fast, fair, and friendly." Three parallel items in every list,
   every sentence, every heading. If there are two things, list two things.

5. **Hype vocabulary.** Seamless, effortless, frictionless, supercharge,
   unlock, elevate, empower, delve, leverage, harness, journey, game-changer.
   Delete on sight. Describe what the thing does instead.

6. **Perfect parallelism.** Every heading the same shape, every paragraph the
   same length, every section ending on a quip. Human writing is lumpier.

7. **Uniform enthusiasm.** Every feature described at the same breathless
   pitch. Real writers care more about some things than others, and it shows.

8. **Vague claims with no anchor.** "Powerful features", "loved by users",
   "studies show". If you can't attach a number, a name, or an example, cut it.

9. **Rhetorical wind-ups.** "Have you ever wondered...", "What if I told
   you...", "In today's fast-paced world...". Start with the point.

10. **No contractions.** "It is free and you will not see ads" reads stiff.
    Write "it's" and "you won't" like a person would.

## The opposite direction (do these)

- **Short declarative sentences.** Subject, verb, object. One idea each.
- **Concrete over abstract.** Not "handles complex multi-party transactions"
  but "two people can pay one bill". Use real numbers when you have them:
  "€420, paid by you, split four ways."
- **Modest claims.** "A simple way to keep track of shared expenses" beats
  "the ultimate expense companion". Understatement reads as confidence.
- **Plain words.** Use, not utilize. Help, not empower. Show, not surface.
- **Have an opinion, state a fact.** "We made it for our own trips and kept it
  free" says more than three paragraphs of mission statement.
- **Vary the rhythm.** Mix a long sentence with a short one. Let one section
  run longer than another because it has more to say.
- **Read it aloud.** Anything you stumble over or would feel silly saying to a
  friend gets rewritten.

## Before and after (real examples from this project)

| Before (AI register) | After (plain register) |
|---|---|
| Split trips, not friendships. | Trip expenses, kept simple. |
| Who owes who, sorted. | Keep track of who owes what. |
| Every trip keeps a ledger. This one keeps itself. | A simple way to keep track of shared expenses. |
| All of it. Forever. We built this because the alternatives nickel-and-dimed our own trips. | Everything's included. We made it for our own trips and kept it free. |
| Dinner, taxis, the Airbnb — log it as it happens. Multiple payers on one bill? Fine. Someone sat that one out? Also fine. | Dinner, taxis, the Airbnb. Log it when it happens. Two people can pay one bill, and someone who skipped dinner can be left out of that one. |
| trip expenses, no friction | keep track of shared expenses |

## Quick checklist before shipping any text

- [ ] Zero em dashes (logo glyphs and code excluded)
- [ ] No "not X, but Y" constructions
- [ ] No hype words (seamless, effortless, unlock, empower, elevate...)
- [ ] Contractions where a person would use them
- [ ] At least one concrete detail (number, name, example) per claim
- [ ] Read aloud once without wincing
