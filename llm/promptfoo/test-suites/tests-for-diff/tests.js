// promptfoo test cases for tests-for-diff — one per fixture under fixtures/.
// The provider generates a test suite for the fixture's diff and mutation-tests
// it; the deterministic js assert passes when the generated tests run green on
// the correct code AND catch a majority of the planted regressions.
const fs = require('fs');
const path = require('path');

const FIX = path.join(__dirname, 'fixtures');
let cases;
try {
  cases = fs.readdirSync(FIX).filter((d) => {
    try { return fs.statSync(path.join(FIX, d)).isDirectory(); } catch { return false; }
  });
} catch (e) {
  throw new Error(`tests-for-diff fixtures missing at ${FIX}`);
}

module.exports = cases.map((c) => ({
  description: `tests-for-diff: ${c}`,
  vars: { case: c },
  assert: [
    {
      type: 'javascript',
      // output = {correct_pass, caught, total, mutation_score}
      value: 'const o = JSON.parse(output); o.correct_pass === true && o.mutation_score >= 0.5',
    },
  ],
}));
