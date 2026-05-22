// Custom promptfoo provider for the agentic-coding suite.
//
// For each test it runs opencode headless inside the oc-agent container (the
// model self-directs: read code, write code, run its own tests, fix), then
// either grades the result with a HIDDEN test the model never saw, or hands the
// model's produced artifact to a judge (g-eval in the suite). Returns the result
// plus tokenUsage + metadata{turns} so promptfoo reporting and summarize.sh's
// efficiency table can use them.
//
// Per-test vars drive behavior:
//   mode: solo | seeded | review | summarize        (default solo)
//   solo     — empty sandbox; model writes solution.py; graded by the hidden
//              pytest at large-code/<test_name>/test_solution.py.
//   seeded   — fixtures/repos/<seed> copied in (a real buggy repo); model fixes
//              it; graded by copying fixtures/hidden/<hidden> to <dest> and
//              running <grade_cmd> (parse: gotest|pytest).
//   review   — repo seeded + fixtures/<diff> dropped at /work/PR.diff; model
//              writes a review; output = its final assistant text (judge-graded).
//   summarize— repo seeded; model writes <capture> (e.g. AGENTS.md); output =
//              that file's contents (judge-graded).
//
// Runs ON jason-server (docker + llm-swap local). Model comes from provider
// config.model (rendered from {{env.MODEL}}); LLM_SWAP_URL defaults to local.
const { execFileSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const URL = process.env.LLM_SWAP_URL || 'http://localhost:11436/v1';
const AGENT_TIMEOUT_MS = (Number(process.env.AGENT_TIMEOUT_S) || 600) * 1000;
const FIXTURES = path.join(__dirname, 'fixtures');

function parsePytest(s) {
  const n = (re) => { const m = s.match(re); return m ? parseInt(m[1], 10) : 0; };
  const passed = n(/(\d+) passed/), failed = n(/(\d+) failed/), errors = n(/(\d+) error/);
  return { passed, total: passed + failed + errors };
}

// `go test -v` prints one "--- PASS:"/"--- FAIL:" line per test function.
function parseGoTest(s) {
  const passed = (s.match(/^--- PASS:/gm) || []).length;
  const failed = (s.match(/^--- FAIL:/gm) || []).length;
  return { passed, total: passed + failed };
}

// The final assistant message in opencode's --format json stream is the last
// {"type":"text","part":{"text":"..."}} event.
function captureFinalText(events) {
  let last = '';
  for (const line of events.split('\n')) {
    if (!line.trim()) continue;
    let ev; try { ev = JSON.parse(line); } catch { continue; }
    if (ev.type === 'text' && ev.part && typeof ev.part.text === 'string' && ev.part.text.trim()) {
      last = ev.part.text;
    }
  }
  return last.trim();
}

class AgenticProvider {
  constructor(options) {
    this.config = (options && options.config) || {};
  }
  // Model comes from promptfoo (provider config.model, rendered from
  // {{ env.MODEL }}); falls back to MODEL env. In the id so the cache key
  // differs per model under test.
  modelName() { return this.config.model || process.env.MODEL || 'unknown'; }
  id() { return `agentic:${this.modelName()}`; }

  async callApi(prompt, context) {
    const v = (context && context.vars) || {};
    const mode = v.mode || 'solo';
    const graded = mode === 'solo' || mode === 'seeded';
    const model = this.modelName();
    // Distinct per test: solo uses test_name; seeded uses the seed; review/
    // summarize append the mode (they can share a seed, e.g. dp-summary).
    const label = mode === 'solo' ? (v.test_name || 'task')
      : mode === 'seeded' ? v.seed : `${v.seed}-${mode}`;
    const sandbox = fs.mkdtempSync(path.join(os.tmpdir(), `agentic-${label}-`));

    try {
      // 1. Seed the sandbox (solo: empty; others: copy the fixture repo in).
      if (mode !== 'solo') {
        const repo = path.join(FIXTURES, 'repos', v.seed || '');
        if (!fs.existsSync(repo)) {
          throw new Error(`seed repo missing: ${repo} — run test-suites/agentic/fixtures/prep.sh`);
        }
        execFileSync('cp', ['-a', `${repo}/.`, sandbox]);
        if (mode === 'review' && v.diff) {
          execFileSync('cp', [path.join(FIXTURES, v.diff), path.join(sandbox, 'PR.diff')]);
        }
      }

      // 2. Agentic run — model self-directs in /work; events stream on stdout.
      const cname = `oc-agent-${path.basename(sandbox)}`;
      let events = '';
      try {
        events = execFileSync('docker', [
          'run', '--rm', '--name', cname, '--network', 'host', '-v', `${sandbox}:/work`,
          '-e', `LLM_SWAP_URL=${URL}`, '-e', `MODEL=${model}`, '-e', `MODE=${mode}`,
          '-e', `CAPTURE=${v.capture || ''}`, '-e', `TASK=${prompt}`, 'oc-agent',
        ], { timeout: AGENT_TIMEOUT_MS, maxBuffer: 64 * 1024 * 1024 }).toString();
      } catch (e) {
        events = (e.stdout || '').toString(); // timeout/non-zero: grade what exists
        // On timeout the docker CLI is killed but the container keeps running
        // detached (and its opencode keeps hammering llm-swap) — force-remove it.
        try { execFileSync('docker', ['rm', '-f', cname], { stdio: 'ignore' }); } catch (e2) {}
      }
      if (process.env.AGENTIC_DEBUG) {
        try { fs.writeFileSync(path.join(os.tmpdir(), `agentic-events-${label}.jsonl`), events || '(empty)'); } catch (e) {}
      }

      // 3. Turns + tokens. `total` includes cached prompt reads
      // (input+cache.read+output); input alone undercounts once caching kicks in.
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
      const tokenUsage = { prompt: promptTok, completion: completionTok, total: totalTok };

      // 4a. Judge-graded modes: output is the model's produced artifact.
      if (!graded) {
        let output = '';
        if (v.capture && v.capture.startsWith('file:')) {
          const f = path.join(sandbox, v.capture.slice(5));
          output = fs.existsSync(f) ? fs.readFileSync(f, 'utf8') : '';
        }
        // Fall back to the model's final message if no file was captured (e.g.
        // it wrote nowhere findable, or timed out before the entrypoint salvage).
        if (!output.trim()) output = captureFinalText(events);
        return { output, tokenUsage, metadata: { turns, tokens: totalTok, mode, test_name: label } };
      }

      // 4b. Test-graded modes: copy the hidden test in AFTER the run, then run it.
      let hiddenSrc, dest, gradeCmd, parseFn;
      if (mode === 'solo') {
        hiddenSrc = path.join(__dirname, '..', 'large-code', v.test_name, 'test_solution.py');
        dest = 'test_solution.py';
        gradeCmd = 'python3 -m pytest test_solution.py --tb=no -q';
        parseFn = parsePytest;
      } else {
        hiddenSrc = path.join(FIXTURES, 'hidden', v.hidden);
        dest = v.dest;
        gradeCmd = v.grade_cmd;
        parseFn = v.grade_parse === 'gotest' ? parseGoTest : parsePytest;
      }

      let passed = 0, total = 0, reason = '';
      try {
        // Grade the source fix, not the agent's test scaffolding: in seeded mode
        // reset every *_test.go in the target package to the pristine snapshot
        // (so a test the agent wrote/broke can't change the verdict or break
        // compilation), then drop in the hidden test.
        if (mode === 'seeded') {
          const pkgDir = path.dirname(dest);
          const sbPkg = path.join(sandbox, pkgDir);
          const seedPkg = path.join(FIXTURES, 'repos', v.seed, pkgDir);
          for (const f of fs.readdirSync(sbPkg)) {
            if (f.endsWith('_test.go')) fs.rmSync(path.join(sbPkg, f));
          }
          for (const f of fs.readdirSync(seedPkg)) {
            if (f.endsWith('_test.go')) fs.copyFileSync(path.join(seedPkg, f), path.join(sbPkg, f));
          }
        }
        const destPath = path.join(sandbox, dest);
        fs.mkdirSync(path.dirname(destPath), { recursive: true });
        fs.copyFileSync(hiddenSrc, destPath);
        const [bin, ...args] = gradeCmd.trim().split(/\s+/);
        const gname = `oc-grade-${path.basename(sandbox)}`;
        let out = '';
        try {
          out = execFileSync('docker', [
            'run', '--rm', '--name', gname, '--network', 'host', '-v', `${sandbox}:/work`, '-w', '/work',
            '--entrypoint', bin, 'oc-agent', ...args,
          ], { timeout: 300000, maxBuffer: 16 * 1024 * 1024 }).toString();
        } catch (e) {
          out = (e.stdout || '').toString() + (e.stderr || '').toString();
          try { execFileSync('docker', ['rm', '-f', gname], { stdio: 'ignore' }); } catch (e2) {}
        }
        ({ passed, total } = parseFn(out));
        reason = out.trim().split('\n').pop() || '';
      } catch (e) {
        reason = `grading error: ${e.message}`;
      }

      const result = { task: label, passed, total, turns, tokens: totalTok };
      return {
        output: JSON.stringify(result),
        tokenUsage,
        metadata: { turns, passed, total, test_name: label, mode, reason },
      };
    } finally {
      // The container writes files as root; rm -rf works on the host-owned dir.
      try { execFileSync('rm', ['-rf', sandbox]); } catch (e) { /* leak beats failing the eval */ }
    }
  }
}

module.exports = AgenticProvider;
