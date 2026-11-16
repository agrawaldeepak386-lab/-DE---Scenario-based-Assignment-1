# Saffron Shield: Agents to Production

**Gen AI — Paper 5, Scenario Based Assignment (Databricks)**

An end-to-end agentic claims-adjudication platform for the fictional **Saffron Shield** health insurer, built on Databricks with Unity Catalog. A tool-calling agent adjudicates claims from four facts (waiting period, network status, room-rent cap, plan at admission), then grows into a guarded, memory-backed, supervised, registry-served production system.

## Configuration conventions

Every notebook starts with a config cell:

* `CATALOG = "claims"` — all functions and tables live in `claims.genai`
* `CHAT_MODEL = "databricks-meta-llama-3-3-70b-instruct"` (Meta Llama 3.3 70B Instruct on Model Serving)
* `EMBED_MODEL = "databricks-gte-large-en"`
* `temperature = 0` on every LLM call (deterministic grading)
* Frozen "today" date: **2026-06-30**

## Rounds

| Round | Deliverable | Where |
| --- | --- | --- |
| R1 | Tools as UC functions: `lookup_claim`, `plan_at`, `search_policy`, `compute_payable` in `claims.genai`; verified 20/20 against the independent key `claims.genai.adjudication_verifier` | `R1_Tools_as_UC_functions` |
| R2 | Tool-calling agent (hand-rolled REST loop, MLflow-traced) with system prompt and two probe traces | `R2_Tool_Calling_Agent`, `agent/prompts/system_v1.md`, `agent/traces/r2_status_probe.json`, `agent/traces/r2_policy_probe.json` |
| R3 | Guardrails over probe suite | `R3_Guardrails`, `evidence/r3_guardrails.json` |
| R4 | Long/short-term memory on Lakebase Postgres (`adjuster_notes`) | `R4_Memory`, `evidence/r4_memory.json` |
| R5 | Supervisor routing across data / policy / adjudication specialists plus a plain-code verifier that recomputes the verdict | `R5_Supervisor`, `agent/traces/r5_attempt1..3.json` |
| R6 | MCP integration | `R6_MCP`, `evidence/r6_mcp.json` |
| R7 | Model/agent registry | `R7_Registry`, `evidence/r7_registry.json` |
| R8 | Streamlit demo app | `app/`, `evidence/r8_app.json`, `evidence/screenshots/r8_app.png`, demo video `evidence/r8_demo.mp4` |

## Repository layout

```
R1_Tools_as_UC_functions.ipynb ... R7_Registry.ipynb   # round notebooks (run in order)
app/            # R8 Streamlit app source
agent/
  prompts/      # system prompts (system_v1.md, system_memory.md)
  traces/       # JSON probe/attempt traces (R2, R5, R6)
src/            # shared source
evidence/
  *.json        # per-round evidence records
  screenshots/  # r2_trace.png, r5_trace.png, r7_endpoint.png, r8_app.png
  r8_demo.mp4   # demo video
```

## How to run

1. Attach to serverless compute with Unity Catalog; ensure the `claims` catalog is provisioned (raw/silver/gold + `claims.genai`).
2. Run `R1_Tools_as_UC_functions` first — it creates the four UC functions everything else calls.
3. Run rounds in order (R2 → R7); each is self-contained after R1.
4. R4 requires the Lakebase project/branch to be enabled.
5. R8 deploys the Streamlit app (see `evidence/r8_app.json` for the recorded app run and `evidence/r8_demo.mp4` for the demo).

## Data notes

* Source tables: `claims.gold.claims_enriched` (claim facts), `claims.silver.policy_history` (SCD2 policy versions — the paper text calls it `claims.silver.dim_policy_scd2`), `claims.raw.plans` (plan terms).
* Probe inputs live in `/Volumes/claims/raw/landing/genai/` (guardrail probes, memory probes, adjudication probe CSV).
