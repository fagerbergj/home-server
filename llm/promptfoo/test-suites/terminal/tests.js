// promptfoo tests for the terminal suite — one per fixture under fixtures/.
const fs = require('fs');
const path = require('path');
const FIX = path.join(__dirname, 'fixtures');
let tasks;
try { tasks = fs.readdirSync(FIX).filter((d) => { try { return fs.statSync(path.join(FIX, d)).isDirectory(); } catch { return false; } }); }
catch (e) { throw new Error(`terminal fixtures missing at ${FIX}`); }
module.exports = tasks.map((t) => ({
  description: `terminal: ${t}`,
  vars: { task: t },
  assert: [{ type: 'javascript', value: 'JSON.parse(output).passed === 1' }],
}));
