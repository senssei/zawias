# Decisions (ADR)

Short records of design and technical decisions that had real alternatives: what we chose, why, and what it
costs. One file per decision, numbered, never rewritten. A changed decision gets a new record that supersedes
the old one (the old one's status changes to `Superseded by NNNN`).

**Write one when** a choice trades something off (balance, look, data format, pipeline) and someone could later
ask "why is it like this?". Skip it for bug fixes and choices the code makes obvious.

**Balance decisions** keep the measured numbers and how to reproduce them (test name, seeds), because the numbers
are the reason. The current rules themselves live in [../mechanics.md](../mechanics.md); a record explains how
they got there.

Template: copy [template.md](template.md).

| # | Decision | Status |
|---|---|---|
| [0001](0001-solo-encounter-scaling.md) | Solo encounter scaling, per encounter and preset | Accepted |
| [0002](0002-fog-of-war-3d.md) | Fog of war in the painted 3D world | Accepted |
| [0003](0003-narrator-quotes.md) | `narrator_quotes`: quotes read by the narrator | Accepted |
| [0004](0004-player-controlled-companions.md) | Player-controlled companions in combat, AI as an option | Accepted |
| [0005](0005-visible-faction-consequences.md) | Visible faction consequences, mostly in data | Accepted |
| [0006](0006-unraveler-entropy.md) | Unraveler entropy in the warehouse fight | Accepted |
| [0007](0007-level-one-risks.md) | Level-one risks stay: warehouse threat shortcut, full fights with Lis | Accepted |
| [0008](0008-degree-of-success.md) | Degree of success: boon, cost and gain on dialogue checks | Accepted |
| [0009](0009-motivations.md) | Character motivations: strength, flaw, desire, fear | Accepted |
| [0010](0010-word-register.md) | Word register: oaths and lies | Accepted |
