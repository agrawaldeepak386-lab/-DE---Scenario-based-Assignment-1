# Gen AI — Paper 4 Scenario Based Assignment

Saffron Shield claims binder, GenAI workloads R1–R8.

## R1 — AI functions extraction

Notebook: `R1_AI_Functions_Extraction`.

- `claims.genai.grievance_emails` — 200 grievance emails loaded unchanged from `grievance_emails.csv`.
- `claims.genai.grievance_classified` — one category per email via `ai_classify` with the five labels and descriptions from policy doc 08 (claim_delay 46 / claim_rejection 42 / payout_deduction 40 / cashless_network 38 / policy_service 34).
- `claims.genai.discharge_extracted` — the 60 discharge-summary PDFs parsed with `ai_parse_document` then field-extracted with `ai_extract` into diagnosis_code, procedure_code, admission_date, discharge_date (DATE), room_type. Raw model outputs are kept once, in session temp views (`_discharge_raw_extract`, `_grievance_raw_classified`), and each final table is built from a single read.
- Validation against `claims.silver.claims_clean`: 100% on all five fields for all 60 claims (bar: 90%); the trap case CLM-10163 (past-history J45.9 vs final J18.9) is extracted correctly. Evidence: `evidence/r1_grievance_predictions.csv`.

## R2 — Chunking, embedding, vector index

Notebook: `R2_chunk_embed and index`.

- `claims.genai.policy_chunks` — the 8 policy markdown docs split one `##` section per chunk, chunk id `<filename>#<anchor>` (lowercase heading, non-alphanumeric collapsed to `-`), Delta Change Data Feed enabled.
- Vector Search endpoint `claims_vs` (standard) and Delta Sync index `claims.genai.policy_chunks_idx` (databricks-gte-large-en embeddings), trigger-updated. Evidence: `evidence/r2_index.png`.

## R3 — LangChain basics

Notebook: `R3_Langchain_basics`.

- `ChatDatabricks` and the Databricks vector-store retriever wrapped as LangChain components against the R2 index; structured-output chains read plan terms from `02_Waiting_Periods_Individual_Plans.md` (individual, 30-day initial wait, 36-month PED) and `03_Waiting_Periods_Group_Plans.md` (group, 0 days, 12 months). Evidence: `evidence/r3_langchain.json`.

## R4 — Hybrid retriever + rerank

Notebook: `R4_Hybrid_retriever+rerank` (SQL, 4 steps).

**Hybrid query used: HYBRID** — a keyword-plus-vector query

- **Vector side**: `vector_search()` against the Delta Sync index `claims.genai.policy_chunks_idx` (databricks-gte-large-en embeddings), top 20 per question.
- **Keyword side**: token-overlap scoring of question tokens against chunk text (`policy_chunks`), top 20 per question.
- **Fusion**: reciprocal rank fusion (RRF, k = 60) of the two rankings → top 10 candidates per question.

**Rerank step used: ai_query pointwise LLM reranker** — `databricks-meta-llama-3-1-8b-instruct`
served via `ai_query()` scores each hybrid candidate 0–10 for how well its section answers the
question. The final ordering is rerank score first, hybrid fused score as tie-breaker; the
ranking pipeline lands in `claims.genai.hybrid_candidates` and is evaluated (Step 3) against
`gold_set.json` expected chunks with hit-rate@5 and MRR over G01–G18 (G19 excluded per its own
multi-hop note). `claims.genai.gold_answers` was later rebuilt into the R5 shape
(question/answer/cited_chunk_ids) — see R5.

## R5 — Governed RAG chain

Notebook: `R5_governed_RAG_chain`.

- `answer_policy_question(q)` → `{'answer', 'cited_chunk_ids'}`: top-5 vector retrieval on `claims.genai.policy_chunks_idx`, grounded system prompt, every claim traced to chunk ids; unanswerable questions fall back to exactly `not in policy`.
- `claims.genai.gold_answers` — question_id, question (STRING), answer (STRING), cited_chunk_ids (ARRAY<STRING>); 21 rows = G01–G19 plus U01 (pet dog premium) and U02 (gym membership), both exactly `not in policy`.
- Verified: 18/18 G01–G18 answered, 0 banned-phrase leaks, all 105 cited chunk ids resolve to `policy_chunks`; G19 answered from structured facts (`claims.gold.claims_enriched` joined to policy rules).

## R6 — Conversation memory

Notebook: `R6_conversation_memory`.

- A 3-turn scripted client chat over the R5 chain with a running summary (LLM-updated each turn) and a follow-up-to-standalone rewrite (LLM, based on the summary only). Turn 3 (`And for group plans?`) is rewritten to a standalone question and the answer cites a `03_Waiting_Periods_Group_Plans.md` chunk first (12-month group PED wait).
- One MLflow trace covers the whole chat. Evidence: `evidence/r6_memory.json` (turns, summary, trace_id).

## R7 — Evaluation + observability

Notebook: `R7_evaluation_observability`.

- Retrieval metrics over the R5 retriever on the gold single-doc questions: hit-rate@5 = 0.9444, MRR = 0.8889 (G01–G18; thresholds ≥ 0.80 / ≥ 0.70). Weakest-metric note: `evidence/r7_weakest_metric.md`.
- MLflow experiment `genai_paper4_r7_eval`: 18 gold questions traced with retriever spans, then judged with `mlflow.genai.evaluate` — retrieval_groundedness, relevance_to_query, correctness and safety all 1.0 (expectations attached per trace). Evidence: `evidence/r7_eval.json`; screenshots `evidence/screenshots/r7_trace.png`, `r7_eval.png`.

## R8 — ai_query batch adjudication

Notebook: `R8_ai_query_adjudication`.

- Deterministic rule-based verifier, pure SQL (claims facts joined to plan terms): `claims.genai.adjudication_probes` (the 20 probe claim_ids) and `claims.genai.adjudication_verifier` — claim_id, payable, waiting_period_ok, network_at_admission (BOOLEAN), room_rent_deduction_pct (DOUBLE, 2 dp), copay_pct (INT), reason_code (INITIAL_WAITING / PED_WAITING / PAYABLE_WITH_DEDUCTION / PAYABLE_IN_FULL), one row per probe claim.
- Batch LLM adjudication of the same claims, run in SQL via `ai_query` (`databricks-meta-llama-3-3-70b-instruct`, temperature 0, JSON response format, replies parsed with `from_json`; worked examples on made-up claims; the LLM never sees the verifier's answers) → `claims.genai.adjudications` — the seven verifier columns plus reasoning.
- Agreement (Definitions rule): 20/20 = 100% (threshold ≥ 90%), including all four trap claims CLM-20001–CLM-20004. Screenshot: `evidence/screenshots/r8_adjudications.png`.
