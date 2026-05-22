// Custom promptfoo provider for the agentic-coding suite.
//
// For each test it runs opencode headless inside the oc-agent container
// (the model self-directs: write code, run its own tests, fix), then grades the
// produced solution.py against the HIDDEN pytest the model never saw. Returns
// the result as JSON plus tokenUsage + metadata{turns} so promptfoo's reporting
// and summarize.sh's efficiency table can use them.
//
// Runs ON jason-server (docker + llm-swap local). Model comes from env.MODEL
// (set per-run by eval.sh); LLM_SWAP_URL defaults to the local llm-swap.
const { execFileSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const URL = process.env.LLM_SWAP_URL || 'http://localhost:11436/v1';
const AGENT_TIMEOUT_MS = (Number(process.env.AGENT_TIMEOUT_S) || 600) * 1000;

function parsePytest(s) {
  const n = (re) => { const m = s.match(re); return m ? parseInt(m[1], 10) : 0; };
  const passed = n(/(\d+) passed/), failed = n(/(\d+) failed/), errors = n(/(\d+) error/);
  return { passed, total: passed + failed + errors };
}

class AgenticProvider {
  constructor(options) {
    this.config = (options && options.config) || {};
    this.providerId = (options && options.id) || 'agentic';
  }
  // Model comes from promptfoo: provider config.model, which promptfoo renders
  // from {{ env.MODEL }} at load time. Falls back to the MODEL env var. Put in
  // the id so promptfoo's cache key differs per model under test.
  modelName() { return this.config.model || process.env.MODEL || 'unknown'; }
  id() { return `agentic:${this.modelName()}`; }

  async callApi(prompt, context) {
    const model = this.modelName();
    const testName = (context && context.vars && context.vars.test_name) || '';
    const testFile = path.join(__dirname, '..', 'large-code', testName, 'test_solution.py');
    const sandbox = fs.mkdtempSync(path.join(os.tmpdir(), `agentic-${testName}-`));

    // 1. Agentic run — model writes solution.py in the sandbox; events on stdout.
    let events = '';
    try {
      events = execFileSync('docker', [
        'run', '--rm', '--network', 'host', '-v', `${sandbox}:/work`,
        '-e', `LLM_SWAP_URL=${URL}`, '-e', `MODEL=${model}`, '-e', `TASK=${prompt}`,
        'oc-agent',
      ], { timeout: AGENT_TIMEOUT_MS, maxBuffer: 64 * 1024 * 1024 }).toString();
    } catch (e) { events = (e.stdout || '').toString(); } // timeout/non-zero: grade what exists
    if (process.env.AGENTIC_DEBUG) {
      try { fs.writeFileSync(path.join(os.tmpdir(), `agentic-events-${testName}.jsonl`), events || '(empty)'); } catch (e) {}
    }

    // 2. Turns + tokens from the event stream. `total` includes cached prompt
    // reads (input+cache.read+output); input alone undercounts once caching kicks in.
    let turns = 0, promptTok = 0, completionTok = 0, totalTok = 0;
    for (const line of events.split('\n')) {
      if (!line.trim()) continue;
      let ev; try { ev = JSON.parse(line); } catch { continue; }
      if (ev.type === 'step_finish' && ev.part && ev.part.tokens) {
        const t = ev.part.tokens;
        turns++;
        promptTok += (t.input || 0) + ((t.cache && t.cache.read) || 0);
        completionTok += t.output || 0;
        totalTok += t.total || 0;
      }
    }

    // 3. Grade with the hidden pytest (copied in AFTER the run).
    let passed = 0, total = 0, reason = '';
    try {
      fs.copyFileSync(testFile, path.join(sandbox, 'test_solution.py'));
      let py = '';
      try {
        py = execFileSync('docker', [
          'run', '--rm', '-v', `${sandbox}:/work`, '-w', '/work',
          '--entrypoint', 'python3', 'oc-agent', '-m', 'pytest', 'test_solution.py', '--tb=no', '-q',
        ], { maxBuffer: 16 * 1024 * 1024 }).toString();
      } catch (e) { py = (e.stdout || '').toString() + (e.stderr || '').toString(); }
      ({ passed, total } = parsePytest(py));
      reason = py.trim().split('\n').pop() || '';
    } catch (e) {
      reason = `grading error: ${e.message}`;
    } finally {
      // The containers create files as root, including nested __pycache__/ and
      // .pytest_cache/ dirs. The host user can unlink root-owned files sitting
      // directly in the host-owned sandbox dir, but NOT files inside those
      // root-owned subdirs (that needs write perm on the subdir itself). Chown
      // the whole tree back to the host user from inside a container (runs as
      // root), then the host rm -rf can remove everything.
      try {
        const { uid, gid } = os.userInfo();
        execFileSync('docker', [
          'run', '--rm', '-v', `${sandbox}:/work`, '--entrypoint', 'chown', 'oc-agent',
          '-R', `${uid}:${gid}`, '/work',
        ], { stdio: 'ignore' });
      } catch (e) { /* fall through to rm; leak beats failing the eval */ }
      try { execFileSync('rm', ['-rf', sandbox]); } catch (e) { /* leak beats failing the eval */ }
    }

    const result = { task: testName, passed, total, turns, tokens: totalTok };
    return {
      output: JSON.stringify(result),
      tokenUsage: { prompt: promptTok, completion: completionTok, total: totalTok },
      metadata: { turns, passed, total, test_name: testName, reason },
    };
  }
}

module.exports = AgenticProvider;
