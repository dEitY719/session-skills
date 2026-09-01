"""Compute the next future <reset + buffer> moment as cron fields + ISO.

Invoke from Bash with three integers inlined:

    python3 references/compute-fire-time.py HH MM B

Output (single line, space-separated):
    <min> <hour> <dom> <month> <iso8601>

The first four fields are the cron expression (minus DoW); the trailing
ISO timestamp is for the state file written by Step 5 of SKILL.md.
"""

import sys
from datetime import datetime, timedelta

H, M, B = (int(x) for x in sys.argv[1:4])
now = datetime.now()
fire = now.replace(hour=H, minute=M, second=0, microsecond=0) + timedelta(minutes=B)
if fire <= now:
    fire += timedelta(days=1)
print(fire.strftime("%M %H %d %m"), fire.isoformat())
