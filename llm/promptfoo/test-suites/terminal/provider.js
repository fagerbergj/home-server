// Custom promptfoo provider — terminal/sysadmin agentic tasks (Terminal-Bench
// style). Reuses the oc-agent image (opencode) from the agentic suite: the model
// self-directs in a /work sandbox to fix a broken script / produce an output,
// then a HIDDEN grade.sh (copied in only after the run) checks the result by
// exit code. Deterministic, no judge.
//
// Fixture layout:  fixtures/<task>/{ task.txt, grade.sh, work/* }
//   work/*    — files seeded into the sandbox (the broken state / inputs)
//   task.txt  — the prompt (pinned; must NOT reveal the hidden check)
//   grade.sh  — run in the sandbox AFTER the agent; exit 0 = pass
//
// Runs ON jason-server. Needs the oc-agent image (test-suites/agentic/Dockerfile).
const { execFileSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const URL = process.env.LLM_SWAP_URL || 'http://localhost:11436/v1';
const FIXTURES = path.join(__dirname, 'fixtures');
const AGENT_TIMEOUT_MS = (Number(process.env.AGENT_TIMEOUT_S) || 600) * 1000;

class TerminalProvider {
  constructor(options) { this.config = (options && options.config) || {}; }
  modelName() { return this.config.model || process.env.MODEL || 'unknown'; }
  id() { return `terminal:${this.modelName()}`; }

  async callApi(prompt, context) {
    const v = (context && context.vars) || {};
    const model = this.modelName();
    const fdir = path.join(FIXTURES, v.task || '');
    if (!fs.existsSync(fdir)) return { error: `fixture missing: ${fdir}` };
    const task = fs.readFileSync(path.join(fdir, 'task.txt'), 'utf8').trim();

    const sandbox = fs.mkdtempSync(path.join(os.tmpdir(), `terminal-${v.task}-`));
    try {
      // 1. Seed the sandbox with the task's work/ files.
      execFileSync('cp', ['-a', `${path.join(fdir, 'work')}/.`, sandbox]);

      // 2. Agentic run — opencode self-directs in /work.
      const cname = `oc-agent-${path.basename(sandbox)}`;
      try {
        execFileSync('docker', [
          'run', '--rm', '--label', 'com.centurylinklabs.watchtower.enable=false',
          '--name', cname, '--network', 'host', '-v', `${sandbox}:/work`,
          '-e', `LLM_SWAP_URL=${URL}`, '-e', `MODEL=${model}`, '-e', 'MODE=seeded',
          '-e', `TASK=${task}`, 'oc-agent',
        ], { timeout: AGENT_TIMEOUT_MS, maxBuffer: 64 * 1024 * 1024 });
      } catch (e) {
        try { execFileSync('docker', ['rm', '-f', cname], { stdio: 'ignore' }); } catch (e2) {}
      }

      // 3. Grade: copy the hidden grade.sh in, run it in the sandbox (exit 0 = pass).
      let passed = 0, reason = '';
      try {
        fs.copyFileSync(path.join(fdir, 'grade.sh'), path.join(sandbox, '.grade.sh'));
        execFileSync('docker', [
          'run', '--rm', '--label', 'com.centurylinklabs.watchtower.enable=false',
          '--network', 'none', '-v', `${sandbox}:/work`, '-w', '/work',
          '--entrypoint', 'bash', 'oc-agent', '.grade.sh',
        ], { timeout: 120000, maxBuffer: 8 * 1024 * 1024 });
        passed = 1; reason = 'grade.sh exit 0';
      } catch (e) {
        reason = `grade.sh failed: ${((e.stdout || '') + (e.stderr || '')).toString().trim().slice(-160)}`;
      }

      return {
        output: JSON.stringify({ task: v.task, passed, total: 1 }),
        metadata: { task: v.task, passed, total: 1, reason },
      };
    } finally {
      try { execFileSync('rm', ['-rf', sandbox]); } catch (e) { /* ignore */ }
    }
  }
}

module.exports = TerminalProvider;
