# Copyright (c) Meta Platforms, Inc. and affiliates.
# All rights reserved.
#
# This source code is licensed under the terms described in the LICENSE file in
# the root directory of this source tree.
import logging
import os

import streamlit as st


def configure_otel():
    if os.getenv("RAG_CHATBOT_OTEL_ENABLED", "false").lower() != "true":
        return None

    try:
        from opentelemetry import trace
        from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
        from opentelemetry.sdk.resources import Resource
        from opentelemetry.sdk.trace import TracerProvider
        from opentelemetry.sdk.trace.export import BatchSpanProcessor
    except Exception as exc:
        logging.getLogger(__name__).warning("OpenTelemetry disabled: %s", exc)
        return None

    current_provider = trace.get_tracer_provider()
    if current_provider.__class__.__name__ != "ProxyTracerProvider":
        return trace.get_tracer("rag-chatbot.streamlit")

    provider = TracerProvider(
        resource=Resource.create({
            "service.name": os.getenv("OTEL_SERVICE_NAME", "rag-chatbot"),
            "service.namespace": os.getenv("OTEL_SERVICE_NAMESPACE", "enterprise-rag"),
        })
    )
    provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))
    trace.set_tracer_provider(provider)
    return trace.get_tracer("rag-chatbot.streamlit")


def main():
    log_level_name = os.getenv("LOG_LEVEL", "INFO").upper()
    log_level = getattr(logging, log_level_name, logging.INFO)
    logging.basicConfig(
        level=log_level,
        format='[%(levelname)s] %(name)s: %(message)s'
    )
    for noisy_logger in ("httpcore", "httpx", "watchdog", "urllib3"):
        logging.getLogger(noisy_logger).setLevel(logging.WARNING)

    tracer = configure_otel()

    # Define available pages: path and icon
    pages = {
        "Chat": ("page/playground/chat.py", "💬"),
        "Upload Documents": ("page/upload/upload.py", "📄"),
        "Inspect": ("page/distribution/inspect.py", "🔍"),
    }

    # Build navigation items dynamically
    nav_items = [
        st.Page(path, title=name, icon=icon, default=name == "Chat")
        for name, (path, icon) in pages.items()
    ]
    # Render navigation
    pg = st.navigation({"Playground": nav_items}, expanded=False)
    if tracer is None:
        pg.run()
    else:
        with tracer.start_as_current_span("streamlit.page.run"):
            pg.run()


if __name__ == "__main__":
    main()
