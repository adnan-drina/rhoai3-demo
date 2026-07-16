# Copyright (c) Meta Platforms, Inc. and affiliates.
# All rights reserved.
#
# This source code is licensed under the terms described in the LICENSE file in
# the root directory of this source tree.

import base64
import io
import json
import logging
import os
import re

import pandas as pd
import streamlit as st

logger = logging.getLogger(__name__)

# When a shield call errors (guardrails service unreachable, protocol
# mismatch, etc.), fail closed by default: block the turn with a visible
# message rather than letting unscreened content through. Set
# RAG_SHIELD_FAIL_MODE=open to keep the demo answering when guardrails are
# down. A silent fail-open once hid a broken client call for a whole session.
SHIELD_FAIL_CLOSED = os.environ.get("RAG_SHIELD_FAIL_MODE", "closed").strip().lower() != "open"
SHIELD_ERROR_MESSAGE = (
    "Guardrail check unavailable, so this message was blocked for safety. "
    "Retry shortly or contact an administrator if this persists."
)

"""
Utility functions for file processing and data conversion in the UI.
"""


def process_dataset(file):
    """
    Read an uploaded file into a Pandas DataFrame or return error messages.
    Supports CSV and Excel formats.
    """
    if file is None:
        return "No file uploaded", None

    try:
        # Determine file type and read accordingly
        file_ext = os.path.splitext(file.name)[1].lower()
        if file_ext == ".csv":
            df = pd.read_csv(file)
        elif file_ext in [".xlsx", ".xls"]:
            df = pd.read_excel(file)
        else:
            # Unsupported extension
            return "Unsupported file format. Please upload a CSV or Excel file.", None

        return df

    except Exception as e:
        st.error(f"Error processing file: {str(e)}")
        return None


def data_url_from_file(file) -> str:
    """
    Convert uploaded file content to a base64-encoded data URL.
    Used for embedding documents for vector DB ingestion.
    """
    file_content = file.getvalue()
    base64_content = base64.b64encode(file_content).decode("utf-8")
    mime_type = file.type

    data_url = f"data:{mime_type};base64,{base64_content}"

    return data_url


def clean_text(text):
    """Collapse consecutive whitespace into a single space."""
    return re.sub(r'\s+', ' ', text).strip()


def strip_file_citations(text):
    """
    Remove file citation markers injected by the Responses API file_search tool.
    Strips bare file ID references and bracket-style annotation markers.

    Args:
        text: Raw response text potentially containing citation markers

    Returns:
        str: Text with citation markers removed
    """
    text = re.sub(r'file<[^>]+>', '', text)
    text = re.sub(r'<\|file-[^|]*\|>', '', text)
    text = re.sub(r'<\|[0-9a-fA-F-]{8,}\|>', '', text)
    text = re.sub(r'【[^】]*†[^】]*】', '', text)
    text = re.sub(r'  +', ' ', text)
    return text


def strip_file_citations_streaming(text):
    """
    Strip citations for streaming display. Removes complete citation markers
    and also trims trailing partial patterns that haven't fully arrived yet,
    preventing citation fragments from briefly flashing in the UI.
    """
    text = strip_file_citations(text)
    text = re.sub(r'<\|(?:f(?:i(?:l(?:e(?:-[^|]*)?)?)?)?)?\s*$', '', text)
    text = re.sub(r'<\|[0-9a-fA-F-]*$', '', text)
    text = re.sub(r'\bfile<[^>]*$', '', text)
    text = re.sub(r'【[^】]*$', '', text)
    return text


def get_vector_db_name(vector_db):
    """
    Get the display name for a vector database.
    Falls back to id if name attribute is not present.

    Args:
        vector_db: Vector database object from API

    Returns:
        str: The vector database name
    """
    return getattr(vector_db, 'name', vector_db.id)


def get_question_suggestions():
    """
    Load question suggestions from environment variable.
    Returns a dictionary mapping vector DB names to lists of suggested questions.
    """
    try:
        suggestions_json = os.environ.get("RAG_QUESTION_SUGGESTIONS", "{}")
        suggestions = json.loads(suggestions_json)
        return suggestions
    except json.JSONDecodeError:
        st.warning("Failed to parse question suggestions from environment variable.")
        return {}
    except Exception as e:
        st.warning(f"Error loading question suggestions: {str(e)}")
        return {}


_SLUG_WORD_FIXES = {
    "rag": "RAG",
    "autorag": "AutoRAG",
    "ai": "AI",
    "genai": "Gen AI",
    "kfp": "KFP",
    "llm": "LLM",
    "llama": "Llama",
    "evalhub": "EvalHub",
    "mcp": "MCP",
    "openshift": "OpenShift",
    "rhoai": "RHOAI",
}

_SLUG_SMALL_WORDS = {"with", "and", "for", "in", "of", "to", "the", "a", "an", "on"}


def guide_title_from_slug(slug):
    """Turn a guide slug like 'working-with-autorag' into a display title."""
    words = [w for w in str(slug).replace("_", "-").split("-") if w]
    parts = []
    for index, word in enumerate(words):
        if word in _SLUG_WORD_FIXES:
            parts.append(_SLUG_WORD_FIXES[word])
        elif index > 0 and word in _SLUG_SMALL_WORDS:
            parts.append(word)
        else:
            parts.append(word.capitalize())
    return " ".join(parts)


def _result_attributes(result):
    if isinstance(result, dict):
        return result.get("attributes") or {}
    return getattr(result, "attributes", None) or {}


def _result_score(result):
    if isinstance(result, dict):
        score = result.get("score")
    else:
        score = getattr(result, "score", None)
    try:
        return float(score)
    except (TypeError, ValueError):
        return 0.0


def summarize_search_sources(search_results):
    """
    Aggregate vector search / file_search results into per-document sources.

    Stage 230 chunks carry corpus metadata (guide_slug, topic, source_url,
    product, version); group retrieved chunks by guide so the answer can be
    attributed to the official documents that grounded it.

    Returns:
        List of source dicts sorted by best relevance score (descending).
    """
    docs = {}
    for result in search_results or []:
        attrs = _result_attributes(result)
        slug = attrs.get("guide_slug") or attrs.get("filename") or "unknown"
        entry = docs.setdefault(slug, {
            "slug": slug,
            "title": guide_title_from_slug(slug),
            "url": attrs.get("source_url"),
            "product": attrs.get("product"),
            "version": attrs.get("version"),
            "topics": set(),
            "chunks": 0,
            "best_score": 0.0,
        })
        entry["chunks"] += 1
        entry["best_score"] = max(entry["best_score"], _result_score(result))
        if attrs.get("topic"):
            entry["topics"].add(str(attrs["topic"]))
        if not entry["url"] and attrs.get("source_url"):
            entry["url"] = attrs["source_url"]
    sources = sorted(docs.values(), key=lambda d: d["best_score"], reverse=True)
    for source in sources:
        source["topics"] = sorted(source["topics"])
    return sources


def format_sources_markdown(sources):
    """Render aggregated sources as a markdown reference list."""
    lines = []
    for index, source in enumerate(sources, start=1):
        title = source["title"]
        link = f"[{title}]({source['url']})" if source.get("url") else title
        details = []
        if source.get("topics"):
            details.append("topics: " + ", ".join(f"`{t}`" for t in source["topics"]))
        if source.get("best_score"):
            details.append(f"relevance {source['best_score']:.2f}")
        details.append(f"{source['chunks']} chunk{'s' if source['chunks'] != 1 else ''}")
        if source.get("product"):
            product = source["product"]
            if source.get("version"):
                product += f" ({source['version']})"
            details.append(product)
        lines.append(f"{index}. **{link}** — " + " · ".join(details))
    return "\n".join(lines)


def fetch_mcp_connectors(client):
    """
    Fetch registered MCP connectors from the LlamaStack server.

    llama-stack 0.7.x replaced MCP toolgroups with connectors; the client
    library does not expose them yet, so query the endpoint directly.

    Args:
        client: LlamaStack client instance

    Returns:
        List of connector dicts ({"connector_id", "url", "server_label", ...})
    """
    try:
        import httpx

        base_url = str(client.base_url).rstrip("/")
        response = httpx.get(f"{base_url}/v1beta/connectors", timeout=10)
        response.raise_for_status()
        return response.json().get("data", [])
    except Exception as e:
        logger.debug("Failed to fetch MCP connectors: %s", e)
        return []


def fetch_available_shields(client):
    """
    Fetch available safety shields from the LlamaStack server.

    Args:
        client: LlamaStack client instance

    Returns:
        List of shield identifier strings
    """
    try:
        shields_list = client.shields.list()
        if shields_list:
            return [s.identifier for s in shields_list]
    except Exception as e:
        logger.debug("Failed to fetch shields: %s", e)
    return []


def _describe_violation(violation, default_message):
    """Build a user-facing violation message that names the triggered rails.

    NeMo shield responses carry per-rail statuses in violation.metadata
    (e.g. {'detect sensitive data on output': {'status': 'blocked'}, ...});
    the bare user_message ("Sorry I cannot do this.") gives operators no
    clue which rail fired, so append the blocked rail names.
    """
    message = getattr(violation, "user_message", None) or default_message
    metadata = getattr(violation, "metadata", None) or {}
    try:
        triggered = [
            rail for rail, result in metadata.items()
            if isinstance(result, dict) and result.get("status") == "blocked"
        ]
    except Exception:  # pylint: disable=broad-exception-caught
        triggered = []
    if triggered:
        message = f"{message} — triggered rail: {', '.join(triggered)}"
    return message


def run_input_shields(client, shield_ids, user_message):
    """
    Run input safety shields on the user's message before processing.

    Args:
        client: LlamaStack client instance
        shield_ids: List of shield identifiers to run
        user_message: The user's input text

    Returns:
        Tuple of (is_blocked: bool, violation_message: str or None, shield_id: str or None)
    """
    if not shield_ids:
        return False, None, None

    for shield_id in shield_ids:
        try:
            logger.debug("Running input shield: %s", shield_id)
            # llama_stack_client 0.7.x run_shield() has no params argument;
            # passing one raises TypeError and the shield silently fails open.
            shield_response = client.safety.run_shield(
                shield_id=shield_id,
                messages=[{"role": "user", "content": user_message}],
            )
            logger.debug("Input shield %s response: %s", shield_id, shield_response)
            if hasattr(shield_response, "violation") and shield_response.violation:
                violation_msg = _describe_violation(
                    shield_response.violation, "Content blocked by safety guardrail"
                )
                logger.warning("Input blocked by shield %s: %s", shield_id, violation_msg)
                return True, violation_msg, shield_id
            logger.debug("Input shield %s passed (no violation)", shield_id)
        except Exception as e:
            logger.warning("Error running input shield %s: %s", shield_id, e)
            if SHIELD_FAIL_CLOSED:
                return True, SHIELD_ERROR_MESSAGE, shield_id
    return False, None, None


def run_output_shields(client, shield_ids, user_message, assistant_response):
    """
    Run output safety shields on the assistant's response after generation.

    Args:
        client: LlamaStack client instance
        shield_ids: List of shield identifiers to run
        user_message: The original user prompt
        assistant_response: The generated assistant response text

    Returns:
        Tuple of (is_blocked: bool, violation_message: str or None, shield_id: str or None)
    """
    if not shield_ids:
        return False, None, None

    for shield_id in shield_ids:
        try:
            logger.debug("Running output shield: %s", shield_id)
            # llama_stack_client 0.7.x run_shield() has no params argument;
            # passing one raises TypeError and the shield silently fails open.
            shield_response = client.safety.run_shield(
                shield_id=shield_id,
                messages=[
                    {"role": "user", "content": user_message},
                    {"role": "assistant", "content": assistant_response},
                ],
            )
            logger.debug("Output shield %s response: %s", shield_id, shield_response)
            if hasattr(shield_response, "violation") and shield_response.violation:
                violation_msg = _describe_violation(
                    shield_response.violation, "Response blocked by safety guardrail"
                )
                logger.warning("Output blocked by shield %s: %s", shield_id, violation_msg)
                return True, violation_msg, shield_id
            logger.debug("Output shield %s passed (no violation)", shield_id)
        except Exception as e:
            logger.warning("Error running output shield %s: %s", shield_id, e)
            if SHIELD_FAIL_CLOSED:
                return True, SHIELD_ERROR_MESSAGE, shield_id
    return False, None, None


def get_suggestions_for_databases(selected_dbs, all_vector_dbs):
    """
    Get combined question suggestions for selected databases.

    Args:
        selected_dbs: List of selected vector DB names
        all_vector_dbs: List of all vector DB objects from API

    Returns:
        List of tuples (question, source_db_name)
    """
    suggestions_map = get_question_suggestions()
    combined_suggestions = []

    if not suggestions_map:
        return []

    # Create a mapping from vector_db_name to id
    db_name_to_id = {
        get_vector_db_name(vdb): vdb.id
        for vdb in all_vector_dbs
    }

    for db_name in selected_dbs:
        # Get the id for this database name
        db_id = db_name_to_id.get(db_name)

        # Try both the id and the db_name as keys in the suggestions map
        questions = None
        if db_id and db_id in suggestions_map:
            questions = suggestions_map[db_id]
        elif db_name in suggestions_map:
            questions = suggestions_map[db_name]

        if questions:
            for question in questions:
                combined_suggestions.append((question, db_name))

    return combined_suggestions
