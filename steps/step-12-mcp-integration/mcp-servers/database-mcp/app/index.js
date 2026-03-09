import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema
} from "@modelcontextprotocol/sdk/types.js";
import pg from "pg";

const {
  POSTGRES_HOST = "postgresql.private-ai.svc.cluster.local",
  POSTGRES_PORT = "5432",
  POSTGRES_DB = "acme_equipment",
  POSTGRES_USER = "acmeadmin",
  POSTGRES_PASSWORD = "",
  PGSSLMODE
} = process.env;

const pool = new pg.Pool({
  host: POSTGRES_HOST,
  port: Number(POSTGRES_PORT),
  database: POSTGRES_DB,
  user: POSTGRES_USER,
  password: POSTGRES_PASSWORD,
  ssl: PGSSLMODE ? { rejectUnauthorized: PGSSLMODE !== "allow" } : false,
  max: 5,
  idleTimeoutMillis: 30_000
});

async function query(text, params = []) {
  const client = await pool.connect();
  try {
    const result = await client.query(text, params);
    return result.rows;
  } finally {
    client.release();
  }
}

const tools = [
  {
    name: "query_pod_equipment",
    description: "Look up equipment details for a pod name from acme-corp namespace. Use this to find which equipment a pod monitors.",
    inputSchema: {
      type: "object",
      properties: {
        pod_name: {
          type: "string",
          description: "Pod name from acme-corp namespace (e.g. acme-equipment-0007)"
        }
      },
      required: ["pod_name"]
    }
  },
  {
    name: "query_equipment",
    description: "Query equipment information by equipment ID (not pod name). Use query_pod_equipment first to get the equipment_id from a pod name.",
    inputSchema: {
      type: "object",
      properties: {
        equipment_id: {
          type: "string",
          description: "Equipment identifier (e.g. LITHO-001, L-900-08)"
        }
      },
      required: ["equipment_id"]
    }
  },
  {
    name: "query_service_history",
    description: "Retrieve recent service history for an equipment ID",
    inputSchema: {
      type: "object",
      properties: {
        equipment_id: { type: "string" },
        limit: {
          type: "integer",
          description: "Maximum number of rows (default 10)"
        }
      },
      required: ["equipment_id"]
    }
  },
  {
    name: "query_parts_inventory",
    description: "Look up a spare part by part number",
    inputSchema: {
      type: "object",
      properties: {
        part_number: {
          type: "string",
          description: "Part number, e.g. P12345"
        }
      },
      required: ["part_number"]
    }
  }
];

async function handleQueryPodEquipment(args = {}) {
  const podName = args.pod_name || args.podName;
  if (!podName) throw new Error("pod_name is required");

  const rows = await query(
    `SELECT pod_name, equipment_id, equipment_name, product_name, effective_from::text
     FROM acme_pod_equipment_map WHERE pod_name = $1`,
    [podName]
  );

  if (!rows.length) {
    return { content: [{ type: "text", text: `No equipment mapping found for pod: ${podName}` }] };
  }

  const r = rows[0];
  return {
    content: [{
      type: "text",
      text: `Pod ${r.pod_name} monitors equipment ${r.equipment_id} (${r.equipment_name}), product: ${r.product_name}, effective since ${r.effective_from}.`
    }]
  };
}

async function handleQueryEquipment(args = {}) {
  const equipmentId = args.equipment_id || args.equipmentId;
  if (!equipmentId) throw new Error("equipment_id is required");

  const rows = await query(
    `SELECT equipment_id, equipment_type, model, status, location, customer,
            serial_number, install_date::text, last_pm::text, next_pm::text,
            wafers_processed, last_calibration::text, next_calibration_due::text
     FROM equipment WHERE equipment_id = $1`,
    [equipmentId]
  );

  if (!rows.length) {
    return { content: [{ type: "text", text: `Equipment not found: ${equipmentId}` }] };
  }

  const e = rows[0];
  return {
    content: [{
      type: "text",
      text: `Equipment ${e.equipment_id} (${e.model})\n` +
            `  Type: ${e.equipment_type}\n` +
            `  Status: ${e.status}\n` +
            `  Location: ${e.location}\n` +
            `  Customer: ${e.customer}\n` +
            `  Serial: ${e.serial_number}\n` +
            `  Installed: ${e.install_date}\n` +
            `  Last PM: ${e.last_pm}, Next PM: ${e.next_pm}\n` +
            `  Wafers processed: ${e.wafers_processed}\n` +
            `  Last calibration: ${e.last_calibration}, Next due: ${e.next_calibration_due}`
    }]
  };
}

async function handleQueryServiceHistory(args = {}) {
  const equipmentId = args.equipment_id || args.equipmentId;
  if (!equipmentId) throw new Error("equipment_id is required");
  const limit = Number(args.limit || 10);

  const rows = await query(
    `SELECT service_date::text AS date, service_type AS type, technician AS tech,
            notes, parts_used, duration_hours, cost_usd
     FROM service_history WHERE equipment_id = $1
     ORDER BY service_date DESC LIMIT $2`,
    [equipmentId, limit]
  );

  if (!rows.length) {
    return { content: [{ type: "text", text: `No service history found for ${equipmentId}` }] };
  }

  const lines = rows.map((r, i) =>
    `${i + 1}. ${r.date} — ${r.type} by ${r.tech} (${r.duration_hours}h, $${r.cost_usd})\n   ${r.notes}`
  );
  return {
    content: [{
      type: "text",
      text: `Service history for ${equipmentId} (${rows.length} records):\n${lines.join("\n")}`
    }]
  };
}

async function handleQueryPartsInventory(args = {}) {
  const partNumber = args.part_number || args.partNumber;
  if (!partNumber) throw new Error("part_number is required");

  const rows = await query(
    `SELECT part_number, part_name, description, stock_level, min_stock_level,
            lead_time_days, price_usd, supplier, category
     FROM parts_inventory WHERE part_number = $1`,
    [partNumber]
  );

  if (!rows.length) {
    return { content: [{ type: "text", text: `Part not found: ${partNumber}` }] };
  }

  const p = rows[0];
  return {
    content: [{
      type: "text",
      text: `Part ${p.part_number}: ${p.part_name}\n` +
            `  ${p.description}\n` +
            `  Stock: ${p.stock_level} (min: ${p.min_stock_level})\n` +
            `  Lead time: ${p.lead_time_days} days, Price: $${p.price_usd}\n` +
            `  Supplier: ${p.supplier}, Category: ${p.category}`
    }]
  };
}

const server = new Server(
  { name: "database-mcp", version: "1.0.0" },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({ tools }));

server.setRequestHandler(CallToolRequestSchema, async (req) => {
  const { name, arguments: args = {} } = req.params;
  try {
    switch (name) {
      case "query_pod_equipment": return await handleQueryPodEquipment(args);
      case "query_equipment": return await handleQueryEquipment(args);
      case "query_service_history": return await handleQueryServiceHistory(args);
      case "query_parts_inventory": return await handleQueryPartsInventory(args);
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
  console.error("database-mcp server running on stdio");
}

main().catch((error) => {
  console.error("Fatal error in database-mcp:", error);
  process.exit(1);
});
