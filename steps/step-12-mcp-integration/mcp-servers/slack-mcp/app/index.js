import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema
} from "@modelcontextprotocol/sdk/types.js";

const {
  SLACK_WEBHOOK_URL = "",
  DEFAULT_CHANNEL = "#acme-litho",
  DEFAULT_USERNAME = "ACME LithoOps Agent",
  DEFAULT_ICON = ":factory:"
} = process.env;

const tools = [
  {
    name: "send_slack_message",
    description: "Send a custom message to a Slack channel via webhook",
    inputSchema: {
      type: "object",
      properties: {
        message: { type: "string", description: "Message text to send" },
        channel: { type: "string", description: "Slack channel (default: #acme-litho)" }
      },
      required: ["message"]
    }
  },
  {
    name: "send_equipment_alert",
    description: "Send formatted equipment alert with telemetry data",
    inputSchema: {
      type: "object",
      properties: {
        equipment_id: { type: "string", description: "Equipment identifier" },
        status: { type: "string", description: "Alert severity: PASS, WARNING, FAIL, CRITICAL" },
        alert_message: { type: "string", description: "Alert details" },
        actions: { type: "array", items: { type: "string" }, description: "Recommended actions" }
      },
      required: ["equipment_id", "status"]
    }
  },
  {
    name: "send_maintenance_plan",
    description: "Send a maintenance remediation plan to Slack",
    inputSchema: {
      type: "object",
      properties: {
        equipment_id: { type: "string", description: "Equipment identifier" },
        plan: { type: "string", description: "Maintenance plan details" },
        priority: { type: "string", description: "Priority level: Low, Normal, High, Urgent" }
      },
      required: ["equipment_id", "plan"]
    }
  }
];

function now() {
  return new Date().toISOString();
}

async function postToSlack(payload) {
  if (!SLACK_WEBHOOK_URL) {
    console.error(`[DEMO MODE] Slack message: ${JSON.stringify(payload, null, 2)}`);
    return { demo_mode: true, payload };
  }

  const response = await fetch(SLACK_WEBHOOK_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload)
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Slack webhook failed (${response.status}): ${text}`);
  }

  return { demo_mode: false };
}

async function sendSimpleMessage(args = {}) {
  const message = args.message;
  if (!message) throw new Error("message is required");
  const channel = args.channel || DEFAULT_CHANNEL;

  const meta = await postToSlack({
    channel,
    text: message,
    username: DEFAULT_USERNAME,
    icon_emoji: DEFAULT_ICON
  });

  return {
    content: [{
      type: "text",
      text: `Message sent to ${channel}${meta.demo_mode ? " (demo mode — logged only)" : ""}. Timestamp: ${now()}`
    }]
  };
}

async function sendEquipmentAlert(args = {}) {
  const equipmentId = args.equipment_id || args.equipmentId;
  const status = (args.status || "UNKNOWN").toUpperCase();
  if (!equipmentId) throw new Error("equipment_id is required");

  const alertMessage = args.alert_message || args.alertMessage || "";
  const actions = Array.isArray(args.actions) ? args.actions : [];
  const emoji = (status === "FAIL" || status === "CRITICAL") ? "RED ALERT" : status === "WARNING" ? "WARNING" : "OK";

  let text = `[${emoji}] Equipment Alert: ${equipmentId} — Status: ${status}`;
  if (alertMessage) text += `\n${alertMessage}`;
  if (actions.length) text += `\nRecommended actions:\n${actions.map(a => `  - ${a}`).join("\n")}`;

  const meta = await postToSlack({
    channel: DEFAULT_CHANNEL,
    text,
    username: DEFAULT_USERNAME,
    icon_emoji: ":warning:"
  });

  return {
    content: [{
      type: "text",
      text: `Equipment alert sent for ${equipmentId} (${status})${meta.demo_mode ? " — demo mode, logged only" : ""}. Timestamp: ${now()}`
    }]
  };
}

async function sendMaintenancePlan(args = {}) {
  const equipmentId = args.equipment_id || args.equipmentId;
  const plan = args.plan;
  if (!equipmentId || !plan) throw new Error("equipment_id and plan are required");

  const priority = args.priority || "Normal";

  const meta = await postToSlack({
    channel: DEFAULT_CHANNEL,
    text: `[MAINTENANCE PLAN] Equipment: ${equipmentId} | Priority: ${priority}\n${plan}`,
    username: "Maintenance Planning Agent",
    icon_emoji: ":wrench:"
  });

  return {
    content: [{
      type: "text",
      text: `Maintenance plan sent for ${equipmentId} (priority: ${priority})${meta.demo_mode ? " — demo mode, logged only" : ""}. Timestamp: ${now()}`
    }]
  };
}

const server = new Server(
  { name: "slack-mcp", version: "1.0.0" },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({ tools }));

server.setRequestHandler(CallToolRequestSchema, async (req) => {
  const { name, arguments: args = {} } = req.params;
  try {
    switch (name) {
      case "send_slack_message": return await sendSimpleMessage(args);
      case "send_equipment_alert": return await sendEquipmentAlert(args);
      case "send_maintenance_plan": return await sendMaintenancePlan(args);
      default: throw new Error(`Unknown tool: ${name}`);
    }
  } catch (error) {
    return {
      content: [{ type: "text", text: `Error: ${error instanceof Error ? error.message : String(error)}` }]
    };
  }
});

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("slack-mcp server running on stdio");
}

main().catch((error) => {
  console.error("Fatal error in slack-mcp:", error);
  process.exit(1);
});
