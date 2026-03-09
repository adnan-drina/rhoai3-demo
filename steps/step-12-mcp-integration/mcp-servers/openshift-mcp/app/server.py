#!/usr/bin/env python3
"""
OpenShift MCP Server — read-only cluster inspection tools.
Returns summarized data optimized for LLM context windows.
"""
import json
import logging
import os
from kubernetes import client, config
from mcp.server.fastmcp import FastMCP

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

try:
    config.load_incluster_config()
    logger.info("Loaded in-cluster config")
except Exception:
    config.load_kube_config()
    logger.info("Loaded local kubeconfig")

v1 = client.CoreV1Api()

mcp = FastMCP("OpenShift MCP")


@mcp.tool()
def get_pod_status(name: str, namespace: str = "default") -> str:
    """Get summarized status of a pod"""
    try:
        pod = v1.read_namespaced_pod(name, namespace)
        containers = pod.status.container_statuses or []
        ready = sum(1 for c in containers if c.ready)
        restarts = sum(c.restart_count for c in containers)
        return (
            f"Pod {pod.metadata.name} in {pod.metadata.namespace}\n"
            f"  Phase: {pod.status.phase}\n"
            f"  Ready: {ready}/{len(containers)}\n"
            f"  Restarts: {restarts}\n"
            f"  IP: {pod.status.pod_ip}"
        )
    except client.exceptions.ApiException:
        return f"Error: Pod '{name}' not found in namespace '{namespace}'"


@mcp.tool()
def get_pod_logs(name: str, namespace: str = "default", tail_lines: int = 50) -> str:
    """Get pod logs (last N lines)"""
    try:
        return v1.read_namespaced_pod_log(name, namespace, tail_lines=tail_lines)
    except client.exceptions.ApiException:
        return f"Error: Could not get logs for pod '{name}' in namespace '{namespace}'"


@mcp.tool()
def list_pods_summary(namespace: str = "default") -> str:
    """List pods with summary info (name, status, ready)"""
    try:
        pods = v1.list_namespaced_pod(namespace)
        lines = []
        for pod in pods.items:
            containers = pod.status.container_statuses or []
            ready = sum(1 for c in containers if c.ready)
            lines.append(f"  {pod.metadata.name}: {pod.status.phase} ({ready}/{len(containers)} ready)")
        return f"Pods in {namespace} ({len(lines)} total):\n" + "\n".join(lines)
    except client.exceptions.ApiException:
        return f"Error: Could not list pods in namespace '{namespace}'"


@mcp.tool()
def get_recent_events(namespace: str = "default", limit: int = 10) -> str:
    """Get recent events in namespace"""
    try:
        events = v1.list_namespaced_event(namespace)
        sorted_events = sorted(
            events.items,
            key=lambda e: e.last_timestamp or e.event_time,
            reverse=True,
        )[:limit]

        lines = []
        for event in sorted_events:
            obj = f"{event.involved_object.kind}/{event.involved_object.name}"
            lines.append(f"  {obj}: {event.reason} — {event.message} (x{event.count})")
        return f"Recent events in {namespace} ({len(lines)}):\n" + "\n".join(lines)
    except client.exceptions.ApiException:
        return f"Error: Could not get events in namespace '{namespace}'"


if __name__ == "__main__":
    transport = os.getenv("MCP_TRANSPORT", "sse")
    mcp.run(transport=transport)
