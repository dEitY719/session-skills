/**
 * session plugin for OpenCode.ai
 *
 * Auto-registers the skills directory via the config hook (no symlinks needed).
 *
 * Unlike superpowers, this plugin injects no per-session bootstrap context.
 * These skills bracket a session rather than running inside it — you reach for
 * `restart` when a turn died, `close` or `handoff` when the session is ending,
 * `worktree-spawn` when starting isolated work — so OpenCode's native `skill`
 * tool discovering them is all that is needed.
 *
 * Three of the eight (`rate-limit-guard`, `resume-after-limit`, `schedule`)
 * need Claude Code's CronCreate/CronDelete tools. OpenCode has no equivalent;
 * they are registered so the skill can explain the gap and stop, not so it can
 * fake a timer.
 */

import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export const SessionPlugin = async () => {
  const sessionSkillsDir = path.resolve(__dirname, '../../skills');

  return {
    // Inject skills path into live config so OpenCode discovers session skills
    // without requiring manual symlinks or config file edits.
    // This works because Config.get() returns a cached singleton — modifications
    // here are visible when skills are lazily discovered later.
    config: async (config) => {
      config.skills = config.skills || {};
      config.skills.paths = config.skills.paths || [];
      if (!config.skills.paths.includes(sessionSkillsDir)) {
        config.skills.paths.push(sessionSkillsDir);
      }
    },
  };
};
