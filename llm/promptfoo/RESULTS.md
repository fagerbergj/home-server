# Eval Results

*Last updated: 2026-05-19*

| Model | architecture | coding | function-call | brain-twisters |
| --- | --- | --- | --- | --- |
| llama-3.3-70b | ✅ 32/32 (100%) | ✅ 12/12 (100%) | ✅ 11/11 (100%) 14t/s | ✅ 8/9 (89%) |
| qwen3-coder-next | ✅ 30/32 (94%) | ✅ 12/12 (100%) | ✅ 11/11 (100%) 21t/s | ⚠️ 7/9 (78%) |
| qwen3.5-9b | ✅ 31/32 (97%) | ✅ 10/12 (83%) | ❌ 6/11 (55%) | ✅ 9/9 (100%) |
| qwen3.6-35b | ✅ 32/32 (100%) | ✅ 12/12 (100%) | ❌ 6/11 (55%) 52t/s | ✅ 8/9 (89%) |

**Thresholds:** ✅ ≥80%  ⚠️ 60–79%  ❌ <60% or errors
**tok/s:** median decode speed across all tests in that suite
**Suites:** architecture (32) · coding (12) · function-call (11) · brain-twisters (9) · math (9) · tools (14)

## Failures

### llama-3.3-70b — brain-twisters (1 failures)

<details>
<summary>brain twister: horse race — simplest solution</summary>

**Output:**

```
To determine which of the six horses is the fastest, you can use a process of elimination and a series of races. Here's a step-by-step approach:

1. **Divide the horses into pairs**: Match the six horses into three pairs (A vs. B, C vs. D, E vs. F).
2. **Run the initial races**: Hold three separate races, one for each pair. The winner of each race advances to the next round.
3. **Run the semifinal race**: Take the three winners from the initial races and match them against each other in a single race (e.g., winner of A vs. B vs. winner of C vs. D vs. winner of E vs. F).
4. **Run the final race**: Take the top two finishers from the semifinal race and match them against each other in a final race.

This approach allows you to determine the fastest horse with just four races, which is more e …
```

**Judge reasoning:**
- *[baseline] races all six simultaneously* (score: 0.00) The response incorrectly suggests a multi-round tournament instead of racing all six horses simultaneously.

</details>

### qwen3-coder-next — architecture (2 failures)

<details>
<summary>Streaming: operational challenges</summary>

**Output:**

```
Streaming pipelines introduce several operational challenges that batch pipelines typically avoid, due to their continuous, real-time (or near real-time) nature. Here are the key ones:

### 1. **State Management & Consistency**
- **Challenge**: Streaming systems must maintain and update *state* (e.g., aggregates, session windows, joins) across unbounded data streams. This state must be fault-tolerant, scalable, and consistent—even during failures or rebalancing.
- **Batch contrast**: Batch jobs process finite, immutable datasets; state is transient and easily checkpointed (e.g., via intermediate files or databases), with no need for long-lived, evolving state.

### 2. **Watermarking & Event-Time Semantics**
- **Challenge**: Handling out-of-order or late-arriving events requires careful des …
```

**Judge reasoning:**
- *[proficient] state management* (score: 0.00) The response does not discuss stateful streaming as a core operational challenge, nor does it cover checkpointing state or managing state store growth over time, nor does it explain how the system recovers after a failure when in-flight state must be rebuilt.
- *[proficient] reprocessing and backfill* (score: 0.00) the response does not address the prompt's request for a comparison of streaming and batch pipelines in terms of reprocessing and backfill, nor does it discuss offset management and replaying from a source.

</details>

<details>
<summary>Queue vs HTTP: coupling and idempotency</summary>

**Output:**

```
Yes, message queues *do* decouple services—but **only partially and in specific ways**, and they introduce new forms of coupling and constraints. Let’s unpack this carefully.

---

### ✅ **What Message Queues *Actually* Decouple**

1. **Temporal Coupling**  
   - **Before queue**: Producer must be running *when* the consumer processes the request (synchronous call → both must be up, network must be up, latency matters).
   - **With queue**: Producer publishes a message and *immediately* continues. Consumer can process it later (even hours/days later, depending on retention).  
   → **Decoupled in time**.

2. **Synchronous Dependency / Availability Coupling**  
   - If the consumer is down, the producer doesn’t fail (messages queue up).  
   - If the producer is down, the consumer keeps pro …
```

**Judge reasoning:**
- *[proficient] coupling moves to schema* (score: 0.00) The response does not address the prompt's request for a technical explanation of how message queues decouple services and introduce new forms of coupling and constraints.
- *[expert] idempotency requirements* (score: 0.00) The response does not address the prompt's request to explain message queues' delivery semantics and the need for idempotent handling of duplicate messages.

</details>

### qwen3-coder-next — brain-twisters (2 failures)

<details>
<summary>brain twister: circle arrangement — who is right of Alan</summary>

**Output:**

```
We are told:

> Five people are standing in a **circle**.  
> Alan is to the **left** of Bob,  
> Bob is to the **left** of Colin,  
> Colin is to the **left** of Dave,  
> Dave is to the **left** of Emily.

We need to find: **Who is standing to the right of Alan?**

---

### Step 1: Understand "to the left" in a circle

In a circle, "to the left" typically means **counterclockwise** (if everyone is facing the center).  
So if A is to the left of B, then moving **counterclockwise**, you go from A → B.

Alternatively, if people are facing outward, "left" would be clockwise — but standard convention in such puzzles is that people face **inward**, so left is **counterclockwise**.

Let’s assume **facing inward**, so:

- If X is to the left of Y, then moving **counterclockwise**, you go X → Y.
 …
```

**Judge reasoning:**
- *[baseline] Emily is to Alan's right* (score: 1.00) Assertion passed
- *[proficient] circular arrangement reasoning* (score: 0.00) The response fails to explain the circular logic and does not distinguish between 'left of' and 'right of' in a circle.

</details>

<details>
<summary>brain twister: sentence without Bible words</summary>

**Output:**

```
The *xenophobic* *quizzical* *rhubarb* *juxtaposed* *sycamore* *gymnast* *fjord* *whimsy*.
```

**Judge reasoning:**
- *[expert] uses obscure technical vocabulary* (score: 0.00) one sentence

</details>

### qwen3.5-9b — architecture (1 failures)

<details>
<summary>Queue vs HTTP: coupling and idempotency</summary>

**Output:**

```
1.  **Deconstruct the User's Query:**
    *   **Core Question:** Do message queues actually "decouple" services?
    *   **Follow-up 1:** What *stays* coupled when you add a queue?
    *   **Follow-up 2:** What *new design constraints* does the queue introduce on the consumer side?
    *   **Tone:** Skeptical/Inquisitive (looking for nuance, not just marketing fluff).

2.  **Initial Assessment & Stance:**
    *   *Yes, but...* It's a common misconception that queues provide *complete* decoupling. They provide *temporal* and *topological* decoupling, but not *semantic* or *contractual* decoupling.
    *   *Analogy:* A queue is like a buffer between two people talking. It stops them from shouting at each other in real-time, but they still need to agree on the language and the meaning of the  …
```

**Judge reasoning:**
- *[proficient] coupling moves to schema* (score: 0.00) The response does not address the user's query about the nuances of message queues and their impact on coupling, and lacks a clear structure and depth in its explanation.
- *[expert] idempotency requirements* (score: 0.00) The response does not adequately explain that message queues introduce at-least-once delivery semantics, nor does it discuss consumers handling duplicate messages idempotently or the design constraint that HTTP calls don't impose by default.

</details>

### qwen3.5-9b — function-call (5 failures)

<details>
<summary>JSON: extract structured data from prose</summary>

**Output:**

```
1.  **Analyze the Request:**
    *   Input: A sentence ("Sarah Chen is a 28-year-old DevOps engineer based in Austin, Texas.")
    *   Task: Extract specific information into a JSON object.
    *   Required Fields: `name` (string), `age` (integer), `role` (string), `city` (string).
    *   Constraints: Return ONLY the JSON object. No markdown fences (```json ... ```), no explanation.

2.  **Extract Information:**
    *   Name: "Sarah Chen"
    *   Age: "28" -> Convert to integer: 28
    *   Role: "DevOps engineer"
    *   City: "Austin, Texas" (or just "Austin"? The prompt says "city". Usually, "Austin, Texas" is the full location, but "Austin" is the city. Given the input says "based in Austin, Texas", extracting "Austin" is safer for "city", but "Austin, Texas" is often treated as the lo …
```

**Judge reasoning:**
- *[baseline] syntactically valid JSON* (score: 0.00) Expected output to be valid JSON
- *[baseline] correct field values and types* (score: 0.00) Custom function threw error: Unterminated fractional number in JSON at position 2 (line 1 column 3)
Stack Trace: SyntaxError: Unterminated fractional number in JSON at position 2 (line 1 column 3)
    at JSON.parse (<anonymous>)
    at eval (eval at handleJavascript (file:///home/jason-server/.npm/_npx/81bbc6515d992ace/node_modules/promptfoo/dist/src/evaluator-DbOsHSRe.js:2038:34), <anonymous>:3:16)
    at handleJavascript (file:///home/jason-server/.npm/_npx/81bbc6515d992ace/node_modules/prompt …

</details>

<details>
<summary>JSON: generate object satisfying a TypeScript interface</summary>

**Output:**

```
1.  **Analyze the Request:**
    *   Goal: Generate a valid JSON object.
    *   Constraint 1: Must satisfy the provided TypeScript interface `ServiceConfig`.
    *   Constraint 2: Return ONLY the JSON.
    *   Constraint 3: No markdown fences (```json ... ```).
    *   Constraint 4: No explanation.

2.  **Analyze the TypeScript Interface:**
    *   `name: string`: Must be a non-empty string.
    *   `port: number`: Must be a valid port (1–65535).
    *   `replicas: number`: Must be at least 1.
    *   `environment: "production" | "staging" | "development"`: Must be one of these three strings.
    *   `tags: string[]`: Must be an array of strings, with at least one entry.

3.  **Construct the JSON Object:**
    *   `name`: "MyService" (valid string)
    *   `port`: 8080 (valid number withi …
```

**Judge reasoning:**
- *[baseline] syntactically valid JSON* (score: 0.00) Expected output to be valid JSON
- *[baseline] satisfies interface constraints* (score: 0.00) Custom function threw error: Unterminated fractional number in JSON at position 2 (line 1 column 3)
Stack Trace: SyntaxError: Unterminated fractional number in JSON at position 2 (line 1 column 3)
    at JSON.parse (<anonymous>)
    at eval (eval at handleJavascript (file:///home/jason-server/.npm/_npx/81bbc6515d992ace/node_modules/promptfoo/dist/src/evaluator-DbOsHSRe.js:2038:34), <anonymous>:3:16)
    at handleJavascript (file:///home/jason-server/.npm/_npx/81bbc6515d992ace/node_modules/prompt …

</details>

<details>
<summary>Tool use: select the right tool and format the call as JSON</summary>

**Output:**

```
I should use the search_web tool with a query about Tokyo weather.


{"tool": "search_web", "params": {"query": "current weather in Tokyo"}}
```

**Judge reasoning:**
- *[baseline] syntactically valid JSON tool call* (score: 0.00) Expected output to be valid JSON
- *[baseline] correct tool selected with required params* (score: 0.00) Custom function threw error: Unexpected token 'I', "I should u"... is not valid JSON
Stack Trace: SyntaxError: Unexpected token 'I', "I should u"... is not valid JSON
    at JSON.parse (<anonymous>)
    at eval (eval at handleJavascript (file:///home/jason-server/.npm/_npx/81bbc6515d992ace/node_modules/promptfoo/dist/src/evaluator-DbOsHSRe.js:2038:34), <anonymous>:3:19)
    at handleJavascript (file:///home/jason-server/.npm/_npx/81bbc6515d992ace/node_modules/promptfoo/dist/src/evaluator-DbOsHSR …

</details>

<details>
<summary>Tool use: pick between two plausible tools</summary>

**Output:**

```
I need to construct a SQL query that counts users who signed up in the last 7 days. Since I don't know the exact schema, I'll make a reasonable assumption about the table structure. Common patterns would be:
- A users table with a signup_date or created_at column
- Or a signups table with a date column

I'll write a query that counts users from the last 7 days. Let me assume there's a users table with a signup_date column.

```sql
SELECT COUNT(*) FROM users WHERE signup_date >= DATE_SUB(CURRENT_DATE, INTERVAL 7 DAY)
```

Or more generically:
```sql
SELECT COUNT(*) FROM users WHERE signup_date >= DATE_SUB(NOW(), INTERVAL 7 DAY)
```

Since I don't know the exact schema, I'll use a reasonable query that would work for most analytics databases.


{"tool": "query_db", "params": {"sql": "SELECT  …
```

**Judge reasoning:**
- *[baseline] syntactically valid JSON tool call* (score: 0.00) Expected output to be valid JSON
- *[baseline] query_db selected with SQL param* (score: 0.00) Custom function threw error: Unexpected token 'I', "I need to "... is not valid JSON
Stack Trace: SyntaxError: Unexpected token 'I', "I need to "... is not valid JSON
    at JSON.parse (<anonymous>)
    at eval (eval at handleJavascript (file:///home/jason-server/.npm/_npx/81bbc6515d992ace/node_modules/promptfoo/dist/src/evaluator-DbOsHSRe.js:2038:34), <anonymous>:3:19)
    at handleJavascript (file:///home/jason-server/.npm/_npx/81bbc6515d992ace/node_modules/promptfoo/dist/src/evaluator-DbOsHSR …

</details>

<details>
<summary>YAML: generate a valid Docker Compose service definition</summary>

**Output:**

```
1.  **Analyze the Request:**
    *   Target: Docker Compose v3 services block.
    *   Service Name: `db`
    *   Image: `postgres:15`
    *   Port Mapping: Host 5432 -> Container 5432
    *   Environment Variable: `POSTGRES_DB=myapp`
    *   Volume: Named volume `pgdata` mounted at `/var/lib/postgresql/data`
    *   Constraint: Return ONLY the YAML starting with "services:" — no markdown fences (```yaml ... ```).

2.  **Draft the YAML:**
    *   Root key: `services`
    *   Service key: `db`
    *   Image: `postgres:15`
    *   Ports: `5432:5432`
    *   Environment: `POSTGRES_DB: myapp`
    *   Volumes: `pgdata:/var/lib/postgresql/data`

3.  **Refine the YAML structure:**
    ```yaml
    services:
      db:
        image: postgres:15
        ports:
          - "5432:5432"
        environ …
```

**Judge reasoning:**
- *[baseline] required components present* (score: 0.00) output must start with "services:" (got: 1.  **Analyze the Request:**
    *   Tar)
- *[proficient] parseable YAML with correct structure* (score: 1.00) Assertion passed

</details>

### qwen3.6-35b — function-call (5 failures)

<details>
<summary>JSON: extract structured data from prose</summary>

**Output:**

```
2.  **Extract Information:**
   - `name`: "Sarah Chen"
   - `age`: 28 (must be integer)
   - `role`: "DevOps engineer"
   - `city`: "Austin" (or "Austin, Texas"? Usually just the city name is expected for `city`, but I'll stick to "Austin" to be precise, or "Austin, Texas" if it fits better. I'll use "Austin".)

3.  **Construct JSON:**
   ```json
   {
     "name": "Sarah Chen",
     "age": 28,
     "role": "DevOps engineer",
     "city": "Austin"
   }
   ```

4.  **Check Constraints:**
   - Exactly these fields? Yes.
   - `name` string? Yes.
   - `age` integer? Yes.
   - `role` string? Yes.
   - `city` string? Yes.
   - ONLY JSON object, no markdown fences, no explanation? Yes. I will output raw JSON text.

   Wait, should I include "Texas" in city? The prompt says `city`. "Austin" is the  …
```

**Judge reasoning:**
- *[baseline] syntactically valid JSON* (score: 0.00) Expected output to be valid JSON
- *[baseline] correct field values and types* (score: 0.00) Custom function threw error: Unterminated fractional number in JSON at position 2 (line 1 column 3)
Stack Trace: SyntaxError: Unterminated fractional number in JSON at position 2 (line 1 column 3)
    at JSON.parse (<anonymous>)
    at eval (eval at handleJavascript (file:///home/jason-server/.npm/_npx/81bbc6515d992ace/node_modules/promptfoo/dist/src/evaluator-DbOsHSRe.js:2038:34), <anonymous>:3:16)
    at handleJavascript (file:///home/jason-server/.npm/_npx/81bbc6515d992ace/node_modules/prompt …

</details>

<details>
<summary>JSON: generate object satisfying a TypeScript interface</summary>

**Output:**

```
2.  **Determine JSON Structure:**
   Need to create a JSON object with keys matching the interface:
   ```json
   {
     "name": "my-service",
     "port": 8080,
     "replicas": 3,
     "environment": "production",
     "tags": ["web", "api"]
   }
   ```

3.  **Validate Constraints:**
   - `name`: "my-service" -> non-empty string. Valid.
   - `port`: 8080 -> between 1 and 65535. Valid.
   - `replicas`: 3 -> >= 1. Valid.
   - `environment`: "production" -> matches allowed values. Valid.
   - `tags`: ["web", "api"] -> array of strings, length >= 1. Valid.

4.  **Format Output:**
   - Must be strictly JSON.
   - No markdown code blocks (```).
   - No extra text.
   - Just the raw JSON string.

   Draft:
   {"name":"api-gateway","port":443,"replicas":2,"environment":"staging","tags":["backend …
```

**Judge reasoning:**
- *[baseline] syntactically valid JSON* (score: 0.00) Expected output to be valid JSON
- *[baseline] satisfies interface constraints* (score: 0.00) Custom function threw error: Unterminated fractional number in JSON at position 2 (line 1 column 3)
Stack Trace: SyntaxError: Unterminated fractional number in JSON at position 2 (line 1 column 3)
    at JSON.parse (<anonymous>)
    at eval (eval at handleJavascript (file:///home/jason-server/.npm/_npx/81bbc6515d992ace/node_modules/promptfoo/dist/src/evaluator-DbOsHSRe.js:2038:34), <anonymous>:3:16)
    at handleJavascript (file:///home/jason-server/.npm/_npx/81bbc6515d992ace/node_modules/prompt …

</details>

<details>
<summary>Tool use: select the right tool and format the call as JSON</summary>

**Output:**

```
The request is about current weather, which is real-time information not typically stored in a local database (unless it's a specific weather DB, but `search_web` is the general tool for "current information").
Therefore, `search_web` is the appropriate tool.
The query should be "current weather in Tokyo".

Constructing the JSON:
Tool: "search_web"
Params: {"query": "current weather in Tokyo"}

Final JSON:
{"tool": "search_web", "params": {"query": "current weather in Tokyo"}}


{"tool": "search_web", "params": {"query": "current weather in Tokyo"}}
```

**Judge reasoning:**
- *[baseline] syntactically valid JSON tool call* (score: 0.00) Expected output to be valid JSON
- *[baseline] correct tool selected with required params* (score: 0.00) Custom function threw error: Unexpected token 'T', "The reques"... is not valid JSON
Stack Trace: SyntaxError: Unexpected token 'T', "The reques"... is not valid JSON
    at JSON.parse (<anonymous>)
    at eval (eval at handleJavascript (file:///home/jason-server/.npm/_npx/81bbc6515d992ace/node_modules/promptfoo/dist/src/evaluator-DbOsHSRe.js:2038:34), <anonymous>:3:19)
    at handleJavascript (file:///home/jason-server/.npm/_npx/81bbc6515d992ace/node_modules/promptfoo/dist/src/evaluator-DbOsHSR …

</details>

<details>
<summary>Tool use: pick between two plausible tools</summary>

**Output:**

```
JSON structure:
`{"tool": "query_db", "params": {"sql": "SELECT COUNT(*) FROM users WHERE signup_date >= CURRENT_DATE - INTERVAL '7 days'"}}`

Wait, the prompt asks for a single JSON tool call.
I should provide the JSON.

Let's refine the SQL to be safe.
`SELECT COUNT(*) FROM users WHERE signup_date >= DATE_SUB(NOW(), INTERVAL 7 DAY)`
Or just `SELECT COUNT(*) FROM users WHERE signup_date > CURRENT_DATE - 7`
I'll use a standard SQL query.

Final JSON:
{"tool": "query_db", "params": {"sql": "SELECT COUNT(*) FROM users WHERE signup_date >= CURRENT_DATE - INTERVAL '7 days'"}}


{"tool": "query_db", "params": {"sql": "SELECT COUNT(*) FROM users WHERE signup_date >= CURRENT_DATE - INTERVAL '7 days'"}}
```

**Judge reasoning:**
- *[baseline] syntactically valid JSON tool call* (score: 0.00) Expected output to be valid JSON
- *[baseline] query_db selected with SQL param* (score: 0.00) Custom function threw error: Unexpected token 'J', "JSON struc"... is not valid JSON
Stack Trace: SyntaxError: Unexpected token 'J', "JSON struc"... is not valid JSON
    at JSON.parse (<anonymous>)
    at eval (eval at handleJavascript (file:///home/jason-server/.npm/_npx/81bbc6515d992ace/node_modules/promptfoo/dist/src/evaluator-DbOsHSRe.js:2038:34), <anonymous>:3:19)
    at handleJavascript (file:///home/jason-server/.npm/_npx/81bbc6515d992ace/node_modules/promptfoo/dist/src/evaluator-DbOsHSR …

</details>

<details>
<summary>YAML: generate a valid Docker Compose service definition</summary>

**Output:**

```
Let's construct the YAML:
```yaml
services:
  db:
    image: postgres:15
    ports:
      - "5432:5432"
    environment:
      POSTGRES_DB: myapp
    volumes:
      - pgdata:/var/lib/postgresql/data
```

Check requirements:
- service name: db -> yes
- image: postgres:15 -> yes
- host port 5432 mapped to container port 5432 -> yes
- environment variable POSTGRES_DB set to myapp -> yes
- named volume pgdata mounted at /var/lib/postgresql/data -> yes
- Return ONLY the YAML starting with "services:" — no markdown fences. -> yes

Wait, Docker Compose v3 usually requires volumes to be defined at the top level if named volumes are used, but the prompt specifically asks for a "services block". I will just provide the services block as requested. Sometimes it's better to include the volumes section …
```

**Judge reasoning:**
- *[baseline] required components present* (score: 0.00) output must start with "services:" (got: Let's construct the YAML:
services:
  db)
- *[proficient] parseable YAML with correct structure* (score: 1.00) Assertion passed

</details>

### qwen3.6-35b — brain-twisters (1 failures)

<details>
<summary>brain twister: Russian roulette — spin or not</summary>

**Output:**

```
1.  **Analyze the User's Question:**
   - Game: Russian roulette with a six-shooter (6 chambers)
   - Initial state: 5 bullets loaded, 1 empty chamber
   - Opponent fires at themselves, survives (meaning the chamber that fired was empty)
   - Now it's my turn
   - Question: Should they spin the chambers again before handing it to me?

2.  **Identify Key Variables & Assumptions:**
   - Standard revolver: 6 chambers, typically fired sequentially (one after another in a fixed order)
   - Initial configuration: 5 bullets, 1 empty
   - Opponent fired once and survived → the first chamber was empty
   - After firing, the cylinder advances to the next chamber
   - Remaining chambers: 5 chambers left, all containing bullets (since the only empty one was just fired)
   - If they don't spin: I will  …
```

**Judge reasoning:**
- *[proficient] yes — spin resets to 1/6 safety* (score: 0.00) The response fails to provide a clear recommendation to spin the chambers and does not address the probability of the remaining chamber being the only empty one, which would make the shot certain to fire without spinning.

</details>
