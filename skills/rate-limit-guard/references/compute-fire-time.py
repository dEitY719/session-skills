"""Compute a future cron fire moment as cron fields + ISO timestamp.

Two modes, invoked from Bash:

    python3 compute-fire-time.py HH MM B      # absolute: next HH:MM + B min
    python3 compute-fire-time.py --in N       # relative: now + N min

Absolute mode rolls to the next day if `HH:MM + B` has already passed today
(used by rate-limit-guard's Step 2 to anchor on a reset time). Relative mode
never rolls — it is always in the future by construction (used by
resume-after-limit's Step 4 pre-emptive re-arm and by schedule's Step 2).

Output (single line, space-separated):
    <min> <hour> <dom> <month> <iso8601>

The first four fields are the cron expression (minus DoW); the trailing
ISO timestamp is for the state file.
"""

import sys
from datetime import datetime, timedelta


def _fire_absolute(hour: int, minute: int, buffer_min: int) -> datetime:
    now = datetime.now()
    fire = now.replace(hour=hour, minute=minute, second=0, microsecond=0) + timedelta(
        minutes=buffer_min
    )
    if fire <= now:
        fire += timedelta(days=1)
    return fire


def _fire_relative(minutes: int) -> datetime:
    if minutes <= 0:
        raise ValueError(f"--in N requires a positive integer, got {minutes}")
    return datetime.now() + timedelta(minutes=minutes)


USAGE = (
    "usage: compute-fire-time.py HH MM B | compute-fire-time.py --in N\n"
    "  HH MM B  absolute mode: three integers (hour, minute, buffer-minutes)\n"
    "  --in N   relative mode: N a positive integer (minutes from now)"
)


def main(argv: list[str]) -> None:
    try:
        if argv and argv[0] == "--in":
            if len(argv) < 2:
                raise ValueError("--in requires a value")
            fire = _fire_relative(int(argv[1]))
        else:
            if len(argv) < 3:
                raise ValueError("absolute mode requires HH MM B")
            h, m, b = (int(x) for x in argv[:3])
            fire = _fire_absolute(h, m, b)
    except ValueError as exc:
        print(f"compute-fire-time.py: {exc}\n{USAGE}", file=sys.stderr)
        sys.exit(2)
    print(fire.strftime("%M %H %d %m"), fire.isoformat())


if __name__ == "__main__":
    main(sys.argv[1:])
