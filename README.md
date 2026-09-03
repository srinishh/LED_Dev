# LED Manufacturing Operations

A mobile app for tracking LED manufacturing from raw material to delivery,
built in Flutter from the `LED APP DEVELOPMENT` blueprint.

The blueprint describes ten production stages, each with its own captured
fields and status vocabulary, plus a management dashboard and a per-order
history. It is a **process specification, not a navigation model**: following
its ordering literally would produce ten near-identical form screens and force
everyone to navigate by process step rather than by the thing they care about.

This app keeps every field, status and rule from that document, and rebuilds
the structure around **the order as the primary object** and **the operator's
station queue as the daily surface**.

---

## Running it

```bash
flutter pub get
flutter run -d chrome        # or -d windows
flutter test                 # 110 tests
flutter analyze              # clean
```

Screenshots of the key screens live in `screenshots/`. Regenerate them with:

```bash
flutter test test/widget/screenshots.dart --update-goldens
```

There is no server. `MockOrderRepository` seeds 24 realistic orders spread
across every stage, including a quality failure holding an order at the gate,
two orders on hold, one in rework, one held back from dispatch with a reason,
several overdue, one short on material, and two delivered and closed.

**More → Review controls** switches the app between normal, loading, empty,
error, offline, stale-data and no-access, so every designed state can be seen
rather than taken on trust. It also switches role and station, which changes
what Today shows and which actions are offered.

---

## How it is put together

```
lib/design/      tokens, theme, icons, ~30 components
lib/domain/      models, the ten stage schemas, the rules, status projection
lib/data/        repository interface, in-memory implementation, seed data
lib/state/       providers, filtering, session, actions
lib/features/    today, orders, stages, pipeline, alerts, more
```

Three decisions carry most of the weight.

**One schema-driven form instead of ten screens.** `stage_schema.dart` holds
every field the blueprint names, with its type, whether it is required, where
its default comes from and which earlier stage it is carried forward from.
`StageExecutionScreen` renders from that. Changing a captured field is a data
edit, not a new screen, and every stage validates and saves identically.

**Rules live in the domain layer and carry their own words.** Each rule in
`rules.dart` returns a `RuleViolation` holding the sentence the user should
read. The UI prints that sentence directly beneath the control it disabled, so
a blocked user learns why at the point of blockage rather than by trial and
error. The same sentence appears in the blocker banner, so the two can never
disagree.

**One status projection.** Each stage has its own vocabulary (eight values for
Raw Material, five for Laser Cutting, six for Wiring and Assembly) but the
dashboard legend has exactly five. `status_projection.dart` owns that mapping,
and a test walks the full cross-product of stage and status, so a new status
cannot quietly render as "not started".

### Navigation

Four destinations: **Today**, **Orders**, **Pipeline**, **More**. Quality and
Dispatch are deliberately not tabs; they are stages, reachable in one tap from
Today, from a pipeline column, or as a saved filter. Alerts is a badged bell in
the app bar rather than a fifth tab, because exceptions already lead the
manager's Today.

### Rules enforced

| | |
|---|---|
| R-01 | Stages advance in order |
| R-02 | Material cannot pass Partially Received while short |
| R-03 | A stage cannot complete with a required field empty; the control names the field |
| R-04 | **Wiring and Assembly cannot start while a mandatory quality check has failed or is unrecorded.** Manager override needs a typed reason and is logged |
| R-05 | Wiring and Assembly completes only when both halves are done |
| R-06 | Ready for Dispatch needs the label verified |
| R-07 | Not Dispatched needs a reason from the blueprint's nine; Other needs free text |
| R-08 | Delivered needs a date, a recipient and proof |
| R-09 | Welding and Grinding derives its status from both activities |
| R-10 | Completion timestamps cannot precede the start or sit in the future |
| R-11 | Every change emits a timeline event; the UI never authors one |
| R-12 | Editing a completed stage is manager-only, with a reason |

Each has tests in `test/domain/rules_test.dart`.

---

## Design

**Colour.** White dominates. `#00132A` carries text, navigation and contrast.
`#05DBB2` is used for fills, strokes, progress and active state. It is 2.0:1 on
white, so it never carries text; `#05A98A` does. Status is always colour **plus**
an icon **plus** a word, and each of the five families has a distinct shape, so
the matrix stays readable in monochrome and for colour-blind readers.

**Type.** Inter, bundled as an asset. Tabular figures on every quantity, time
and identifier so columns align while scanning. Text scales to 1.6x without
clipping; app-bar chrome clamps at 1.3x so the extra size goes to content.

**Density.** Rows are 64dp normally and 72dp on the operator queue, which is
used with gloves. Every target is at least 48dp. More lets the user switch.

**Restraint.** No glass, no gradients, no shadowed cards. Grouping is done with
whitespace and hairlines. Exceptions use a left-ruled banner, KPIs are bare
type on white, lists are hairline-separated rows, stage tiles use a tinted
ground, the matrix is a real table. The same card treatment is never repeated
across every surface.

Design direction was checked against the `ui-ux-pro-max` intelligence base,
which returns "Data-Dense Dashboard" for this product class, and against the
`taste-skill` anti-slop rules. The latter scopes itself out of dashboards and
native mobile, so only its transferable parts were applied: no em-dashes in any
user-visible string, no placeholder names or round demo numbers in the seed
data, one locked accent, one radius system, one icon family, and cards omitted
in favour of spacing.

---

## What is not built

No backend, authentication or push infrastructure. Label verification accepts a
typed number with the scanner hook stubbed. Proof of delivery records that a
photo or signature was captured rather than storing one. No invoice generation,
tablet layouts or store packaging.

`MockOrderRepository` is the only file that would be replaced by a real
backend; no screen imports it.
