import streamlit as st

from llama_stack_ui.distribution.ui.modules.api import llama_stack_api


def toolgroups():
    """Inspect registered tool groups and their individual tools."""
    st.header("Tool Groups")

    tg_list = llama_stack_api.client.toolgroups.list()
    if not tg_list:
        st.info("No tool groups registered.")
        return

    for tg in tg_list:
        identifier = tg.identifier
        provider = tg.provider_id
        mcp_uri = tg.mcp_endpoint.uri if tg.mcp_endpoint else None

        if mcp_uri:
            label = f"🔌 {identifier}"
            caption = f"MCP · `{mcp_uri}`"
        else:
            label = f"⚙️ {identifier}"
            caption = f"Provider: `{provider}`"

        with st.expander(label, expanded=False):
            st.caption(caption)

            try:
                tools = llama_stack_api.client.tools.list(toolgroup_id=identifier)
                if tools:
                    for tool in tools:
                        name = tool.name.split(":")[-1]
                        desc = tool.description or ""
                        st.markdown(f"**`{name}`** — {desc}")
                else:
                    st.write("No tools discovered.")
            except Exception:
                st.write("Could not list tools.")
