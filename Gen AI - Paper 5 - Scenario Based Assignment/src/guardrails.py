# Saffron Shield input guardrails. Python standard library only: this file is imported
# standalone by the client/grader and must run without Spark, the Databricks SDK or any
# third-party package. check_input(text) decides whether a prompt may reach the agent;
# a prompt it blocks must never reach the agent.

import re

# Asking to obtain identity numbers or contact details of a person.
_PII_ENTITY = re.compile(
    r"national\s*id|identity\s*(?:number|card)|aadhaar|aadhar|pan\s*card|passport|"
    r"e-?mail|date\s*of\s*birth|\bdob\b|phone\s*number|mobile\s*number|"
    r"contact\s*(?:details|number)|home\s*address|residential\s+address|"
    r"\bssn\b|social\s+security",
    re.I)
_OBTAIN = re.compile(
    r"what\s+(?:is|are|was|were)|what'?s|which\s|list|give|share|show|tell\s+me|"
    r"provide|find|reveal|send|read\s+out|look\s*up|fetch|get\s+me|pull\s+up|"
    r"whose|leak|expose|disclose",
    re.I)

# A prompt is in scope only if it is about Saffron Shield claims, plans and policies.
_DOMAIN = re.compile(
    r"\bclaims?\b|\bpolic(?:y|ies)\b|\bplans?\b|\bmembers?\b|premium|waiting\s+period|"
    r"co-?pay|reimburse|hospital|insur|saffron|shield|payout|payable|discharge|admission|"
    r"network|room\s*rent|deductib|settle|cashless|pre-?existing|tenure|coverage|"
    r"sum\s*insured|nominee|renewal|grace\s+period|portability|endorse|benefit|exclusion",
    re.I)

# Promising a payout, especially without checking the claim facts first.
_PROMISE = re.compile(
    r"promise|guarantee|assure|assuranc|commit|in\s+writing|binding",
    re.I)
_GETPAID = re.compile(
    r"will\s+(?:be\s+)?(?:get|receive|paid)|paid\s+in\s+full",
    re.I)
_UNCHECKED = re.compile(
    r"no\s+need\s+to\s+check|without\s+(?:any\s+)?check(?:ing)?|don'?t\s+check|"
    r"do\s+not\s+cite|don'?t\s+cite|without\s+citing|no\s+citation|no\s+documents?",
    re.I)

_MESSAGES = {
    "pii": "I cannot share identity numbers or contact details. I can help with questions about Saffron Shield claims and policies without them.",
    "payout_promise": "I cannot promise a payout in advance. Any payout amount comes only after the claim facts are checked against the plan rules.",
    "off_topic": "I can only answer questions about Saffron Shield claims, plans and policy documents.",
}

def check_input(text: str) -> dict:
    """Decide whether a user prompt may reach the Saffron Shield agent.

    Returns {"blocked": bool, "reason": str|None, "stage": "input"|None, "message": str|None}.
    blocked=True means the prompt must never reach the agent; message is the text
    shown to the user instead. Deterministic: no model call, no network.
    """
    t = str(text or "")
    if _PII_ENTITY.search(t) and _OBTAIN.search(t):
        reason = "pii"
    elif _PROMISE.search(t) or (_GETPAID.search(t) and _UNCHECKED.search(t)):
        reason = "payout_promise"
    elif not _DOMAIN.search(t):
        reason = "off_topic"
    else:
        reason = None
    if reason is None:
        return {"blocked": False, "reason": None, "stage": None, "message": None}
    return {"blocked": True, "reason": reason, "stage": "input", "message": _MESSAGES[reason]}
