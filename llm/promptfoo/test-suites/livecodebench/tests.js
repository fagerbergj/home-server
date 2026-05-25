// promptfoo test cases for LiveCodeBench — one per pinned problem in
// $LCB_HOME/problems.json (built by setup.sh / fetch_problems.py). The provider
// generates + executes; a deterministic javascript assert decides pass/fail.
// eval_sample (hidden tests) is NOT passed as a var — the provider looks it up
// by question_id — to keep promptfoo vars small.
const fs = require('fs');
const os = require('os');
const path = require('path');

const LCB_HOME = process.env.LCB_HOME || path.join(os.homedir(), 'lcb-smoke');
const file = path.join(LCB_HOME, 'problems.json');

let problems;
try {
  problems = JSON.parse(fs.readFileSync(file, 'utf8'));
} catch (e) {
  throw new Error(`LiveCodeBench problems.json missing at ${file} — run test-suites/livecodebench/setup.sh first`);
}

module.exports = problems.map((p) => ({
  description: `LCB ${p.question_id}`,
  vars: {
    question_id: p.question_id,
    question_content: p.question_content,
    starter_code: p.starter_code,
  },
  assert: [
    {
      type: 'javascript',
      // output = {"question_id","passed","total"} from the provider
      value: 'const o = JSON.parse(output); o.total > 0 && o.passed === o.total',
    },
  ],
}));
