import streamlit as st

from llama_stack_ui.distribution.ui.modules.api import llama_stack_api


def toolgroups():
    """Inspect registered tools and MCP connectors."""
    st.header("Tools and Connectors")

    tools = llama_stack_api.list_tools()
    connectors = llama_stack_api.list_connectors()

    if tools:
        st.subheader("Built-in Tools")
        grouped = {}
        for tool in tools:
            if not isinstance(tool, dict):
                continue
            grouped.setdefault(tool.get("toolgroup_id", "unknown"), []).append(tool)

        for group_id, group_tools in grouped.items():
            with st.expander(f"⚙️ {group_id}", expanded=False):
                for tool in group_tools:
                    name = tool.get("name", "unknown")
                    desc = tool.get("description") or ""
                    st.markdown(f"**`{name}`** — {desc}")
    else:
        st.info("No built-in tools registered.")

    if connectors:
        st.subheader("MCP Connectors")
        for connector in connectors:
            if not isinstance(connector, dict):
                continue
            connector_id = connector.get("connector_id", "unknown")
            endpoint = connector.get("url", "endpoint unavailable")
            label = connector.get("server_label") or connector_id
            with st.expander(f"🔌 {connector_id}", expanded=False):
                st.caption(f"MCP · `{endpoint}`")
                st.markdown(f"Server label: `{label}`")
    else:
        st.info("No MCP connectors registered.")
