# R8 - Saffron Shield claims agent chat (app: claims-agent-chat).
#
# The model serving endpoint is NEVER hardcoded here: its name comes from the
# CLAIMS_AGENT_ENDPOINT environment variable, which app.yaml (the app's config)
# declares. The endpoint itself is declared as the app's resource in app.yaml with
# CAN_QUERY, so the app's own service principal is authorized to query it.
import os

import streamlit as st
from databricks.sdk import WorkspaceClient

st.set_page_config(page_title="Saffron Shield Claims Assistant", page_icon="shield")

ENDPOINT_NAME = os.environ.get("CLAIMS_AGENT_ENDPOINT", "")

st.title("Saffron Shield Claims Assistant")
st.caption("Ask about claims, plan terms and policy documents - answers come from the governed claims tools.")

with st.sidebar:
    st.header("Configuration")
    if ENDPOINT_NAME:
        st.success(f"Serving endpoint (from app.yaml): **{ENDPOINT_NAME}**")
    else:
        st.error("CLAIMS_AGENT_ENDPOINT is not set - declare it in app.yaml.")
    st.divider()
    st.markdown("The agent answers via its tools: `lookup_claim`, `plan_at`, "
                "`search_policy`, `compute_payable`.")

if "history" not in st.session_state:
    st.session_state.history = []

for turn in st.session_state.history:
    with st.chat_message("user"):
        st.write(turn["question"])
    with st.chat_message("assistant"):
        st.write(turn["answer"])
        if turn["tool_calls"]:
            with st.expander(f"tool calls ({len(turn['tool_calls'])})"):
                st.json(turn["tool_calls"])

question = st.chat_input("e.g. What's the status of claim CLM-10039?")
if question:
    if not ENDPOINT_NAME:
        st.error("Endpoint name missing from config (app.yaml) - cannot query the agent.")
        st.stop()
    with st.chat_message("user"):
        st.write(question)
    with st.chat_message("assistant"):
        with st.spinner("Asking the claims agent..."):
            try:
                w = WorkspaceClient()  # in-app OAuth (the app's service principal)
                resp = w.serving_endpoints.query(
                    name=ENDPOINT_NAME,
                    dataframe_records=[{"question": question}],
                )
                preds = resp.predictions
                pred = preds[0] if isinstance(preds, list) else preds
            except Exception as e:  # noqa: BLE001
                st.error(f"Endpoint call failed: {e}")
                st.stop()
        answer = (pred.get("answer") or "").strip() or "(no answer)"
        st.write(answer)
        tool_calls = pred.get("tool_calls") or []
        if tool_calls:
            with st.expander(f"tool calls ({len(tool_calls)})"):
                st.json(tool_calls)
    st.session_state.history.append(
        {"question": question, "answer": answer, "tool_calls": tool_calls}
    )
