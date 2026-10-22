# Relentless

First-person horror chase game in Unreal Engine 5, inspired by the Dahaka chases in *Prince of Persia: Warrior Within*. Something unkillable is behind you. You can only run, look back, and use your flashlight.

Level 1: **The Building** (claustrophobic). Level 2: **The Jungle** (next).

## Setup

1. Install **Unreal Engine 5.6+** from the Epic Games Launcher.
2. Install a C++ compiler:
   - **Windows:** Visual Studio 2022 (Community is free) with the **Game development with C++** workload. In its *Individual components*, also tick a recent **Windows 10/11 SDK** and **.NET Framework 4.8 SDK**.
   - **Mac:** Xcode.
3. Double-click `Relentless.uproject` and say **Yes** when asked to build the missing modules. Alternatively, right-click it → *Generate Visual Studio project files*, open `Relentless.sln`, and build `Development Editor | Win64`.
   - If you installed a newer engine version, it will offer to convert the project. Choose *Open a copy* or *Convert in-place*.
4. In the editor: **Tools → Execute Python Script…** → `Scripts/build_building_level.py`.
   This builds and saves `/Game/Maps/Building` (geometry, doors, triggers, lights, fog, pursuer).
5. Press **Play**.

Everything runs with **zero imported assets**. Input, the creature and the props are built from code and engine basic shapes, so you can playtest before any art exists.

## Controls

| Key | Action |
| --- | --- |
| WASD / mouse | Move / look |
| Shift | Run |
| Ctrl or C | Crouch (automatic in vents) |
| Space | Jump |
| **Q** or middle mouse | **Look back** while running |
| F | Flashlight on/off |
| **Right mouse** | **Focus beam**: stuns it briefly, drains battery fast |
| E or left mouse | Slam doors / hold to force heavy doors |

## The building route

Lobby → long corridor (**it bursts out of the lobby behind you**) → ward with a red emergency light → **slam the door** behind you (it bashes through in ~2.5s) → corridor → **heavy door: hold E** while you hear it coming → storage room → **crawl into the vent** (it's too big to follow, so it waits, then vanishes) → corridor → **it ambushes from a side closet** → outside, where it won't follow.

Checkpoints: chase start, storage room, and after the vent.

## How it works

| Class | Role |
| --- | --- |
| `ChaseSubsystem` | Chase state, checkpoints, and the single **danger** value (0–1) that drives everything |
| `PursuerCharacter` | Follows your exact **breadcrumb trail** (no navmesh). Speed is **rubber-banded** to hold ~6.5m behind you; only mistakes kill. Bashes doors, gets stunned, loses you in vents |
| `RelentlessCharacter` | First-person player: look-back camera, stamina, flashlight battery and flicker, head bob, fear shake, vignette and grain driven by danger |
| `ChaseDoor` | Slammable door, or heavy hold-to-open door. Smashes into physics debris |
| `ChaseTrigger` | Starts the chase, sets a checkpoint, or shows a hint |
| `VentZone` | Crawlspace: forces crouch, makes the pursuer lose you and ambush from `AmbushPoint` |
| `SafeZone` | Ends the chase; can load the next level |
| `FlickerLight` | Faulty ceiling light that dies when the pursuer passes under it |
| `ChaseMusicDirector` | Adaptive music: fades layers in by danger, cuts ambience as it closes in, speeds up a heartbeat |
| `BatteryPickup` | Flashlight battery |

## Adding sound (the biggest upgrade)

Import looping `.wav` stems, then select **MusicDirector** in the level and fill **Layers**, for example:

| Layer | Fade in (danger) |
| --- | --- |
| Low drone | 0.0 – 0.2 |
| Percussion | 0.2 – 0.5 |
| Strings | 0.4 – 0.7 |
| Choir / brass | 0.7 – 0.95 |

Plus **Ambience** (insects, building creaks) and **Heartbeat**. On **Pursuer**, set Roar, Footstep, Bash and Screech sounds. On doors, set Slam, Creak and Break. Stems must loop and share a tempo.

## Tuning (all editable in the Details panel)

- **Too easy / too hard**: on the Pursuer, use `IdealGap`, `NearSpeedScale` (keep it < 1), `FarSpeedScale` and `BashTime`. On the heavy door, use `HoldTime`.
- **Too dark / too bright**: on the player, `ExposureEV` (lower is brighter), and `FlashlightLumens` and `Lumens` on each light.
- **Stamina**: `ChaseSprintDrain`, `StaminaRegen`.

## Next steps

- Replace the greybox creature with a real skeletal mesh and animations (the gameplay code doesn't care what it looks like).
- Jungle level: same systems, plus foliage that thrashes as it pushes through, ambience cut-out, a stalking phase, and a rope-bridge set piece.
