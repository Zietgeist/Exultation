# Exultation design guide (for checking feedback)

The Discord bot reads this before acting on any feedback. Ivan owns this file: change it when the vision changes.

## The vision
- Fast, fun isometric action RPG. **Action over strategy.** An original take on the genre.
- Play in focused blocks of about 20-25 minutes, then rest at home or a campfire (empty bags, swap gear, update skills).
- **Consistency over grinding.** Rewards taper after 3-4 hours a day. Showing up often beats playing long.
- Test for every feature: *"What would the player tell a friend about this?"* "I got +5 damage" is thin. "I finally beat the thing that kept stopping me" is the goal.
- Gear changes **how you play**, not just numbers. Gear carries the story of how it was earned.

## Combat core: the Halo triangle
Original Halo had three tools, guns, grenades and melee, plus always moving. Each one is clearly the right
answer for a certain moment. The fun is reading the fight and picking, not memorizing a rotation.
That keeps Exultation from becoming "skill rotation" heavy.

| Halo | Exultation | When it's the obvious choice |
|---|---|---|
| Melee | Sweep (right click) | a close group of small, weak enemies |
| Gun | Strike (left click) | one tough enemy: the leader, a Master, a Boss |
| Grenade | Big ability (F or a side mouse button: Blast, Whirlwind, Root Field...) | a big pack; costs energy, so it's a choice |
| Running | Moving | always: where you stand matters most |

A good fight looks like: run into a group, sweep the trash, strike the leader, drop the big ability on a big pack.

Rules:
- No rotations or "press A, then B, then C" orders. Each button has one clear "when".
- Any new skill must answer: *"What moment is this the obvious answer to?"* No clear answer = ask.
- The player picks, the game never switches for them. Mouse wheel picks the auto-attack style:
  up = single target (Strike), down = multi target (Sweep). Auto-attack (Tab) then keeps swinging,
  so the player's choices are where to stand, which style, and when to use E / Q / F.
- Attack speed vs. damage is a slower "how I like to fight" setting, in the character window (C).

## We avoid
- Skill rotations: long button orders to memorize.
- Talent trees, cookie-cutter "best" builds, gear treadmills.
- Paying or grinding for power. Better recipes come ONLY from the shrine ladder (spaced over days), never from shops.
- Anything that needs audio to play (trials are visual only).
- Mods or features that run downloaded code on players' machines.

## Every class has its own job
All classes share: left click = Strike, right click = Sweep, mouse wheel = auto-attack style, side mouse button = F, Q = Self Heal.
What makes each one different (keep these unique):

| Class | Role | Its own thing | Energy comes from |
|---|---|---|---|
| DPS | Damage | Stacking damage Boost (E), big Blast on a crowd (F) | dealing damage (slow regen) |
| Tank | Tank | Shield that soaks hits (E), Thorns Aura that taunts and reflects (F) | getting hit |
| Healer | Healer | Heals OTHER players: Mending Vow (E), Life Drain aura (F) | refills on its own |
| Skirmisher | Mobile damage | Dash with no damage taken (E), Whirlwind spin (F), lower health, faster | running |
| Warden | Control | Totems that fight (E), Root Field holds enemies (F) | refills on its own |

Signs a request might belong to another class:
- Healing other players -> Healer.
- Taunting, soaking or reflecting damage, extra health -> Tank.
- Damage multipliers that stack, big burst on a crowd -> DPS.
- Dashes, being untouchable, speed, energy from moving -> Skirmisher.
- Holding enemies still, placed helpers (totems, turrets, pets that fight) -> Warden.

Overlap is not always wrong (every class has Self Heal). But it needs a reason, so ask.

## Quick check for any request
1. Does it fit "action over strategy" and short focused sessions?
2. Does it copy another class's job? (table above)
3. Does it add a grind, a treadmill, a "best build", or power for sale?
4. Does it add a rotation, or a button without one clear "when"? (Halo triangle above)
5. Is it a number tweak, or does it change how the game feels?
