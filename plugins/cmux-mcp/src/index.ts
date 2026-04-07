import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import * as cmux from "./cmux.js";

cmux.loadHosts();

const server = new McpServer({
  name: "cmux-mcp",
  version: "0.3.0",
});

// --- list_hosts ---
server.tool(
  "list_hosts",
  "List configured cmux hosts",
  {},
  async () => {
    const hosts = cmux.getHosts();
    const summary = Object.entries(hosts).map(([name, cfg]) => ({
      name,
      type: cfg.ssh ? "remote" : "local",
      ssh: cfg.ssh || null,
    }));
    return {
      content: [{ type: "text" as const, text: JSON.stringify(summary, null, 2) }],
    };
  }
);

// --- list_sessions ---
server.tool(
  "list_sessions",
  "List all cmux workspaces across all windows with their surfaces, refs, and active task titles. Omit host to list across all hosts.",
  {
    host: z.string().optional().describe("Host name. Omit to list all hosts."),
  },
  async ({ host }) => {
    if (host) {
      const workspaces = await cmux.listWorkspaces(host);
      return {
        content: [{
          type: "text" as const,
          text: typeof workspaces === "string" ? workspaces : JSON.stringify(workspaces, null, 2),
        }],
      };
    }
    const all = await cmux.listAllWorkspaces();
    return {
      content: [{ type: "text" as const, text: JSON.stringify(all, null, 2) }],
    };
  }
);

// --- session_tree ---
server.tool(
  "session_tree",
  "Show the pane/surface tree for a workspace",
  {
    host: z.string().optional().describe("Host name. Defaults to 'local'."),
    workspace: z.string().optional().describe("Workspace ref (e.g. workspace:1)"),
  },
  async ({ host, workspace }) => {
    const tree = await cmux.tree(workspace, host);
    return {
      content: [{ type: "text" as const, text: tree }],
    };
  }
);

// --- spawn_claude (local only) ---
server.tool(
  "spawn_claude",
  `Spawn a Claude Code session. Choose where it goes:
  - "here": run claude in an existing surface (no split, no new workspace)
  - "tab": new terminal tab in the same pane
  - "split": split the current pane (default)
  - "workspace": new workspace`,
  {
    cwd: z.string().describe("Working directory for the Claude Code session"),
    mode: z.enum(["here", "tab", "split", "workspace"]).default("split").describe("Where to spawn: here (existing surface), tab (new tab in pane), split (split pane), workspace (new workspace)"),
    workspace: z.string().optional().describe("Target workspace ref. Defaults to current."),
    surface: z.string().optional().describe("Target surface ref (for 'here' mode)."),
    name: z.string().optional().describe("Name for new workspace (workspace mode only)."),
    direction: z.enum(["left", "right", "up", "down"]).default("right").describe("Split direction (split mode only)."),
    prompt: z.string().optional().describe("Initial prompt to send after Claude starts."),
  },
  async ({ cwd, mode, workspace, surface, name, direction, prompt }) => {
    let workspaceRef = workspace;
    let surfaceRef = surface;
    const messages: string[] = [];

    switch (mode) {
      case "here": {
        // Launch claude in an existing surface — no new surface created
        await cmux.send(`cd ${cwd} && claude`, surfaceRef, workspaceRef);
        await cmux.sendKey("Enter", surfaceRef, workspaceRef);
        messages.push(`Launched claude in ${surfaceRef || workspaceRef || "current surface"}`);
        break;
      }
      case "tab": {
        // New terminal tab in the same pane
        const result = await cmux.newSurface(workspaceRef);
        const surfMatch = result.match(/surface:\d+/);
        const wsMatch = result.match(/workspace:\d+/);
        surfaceRef = surfMatch ? surfMatch[0] : undefined;
        workspaceRef = wsMatch ? wsMatch[0] : workspaceRef;
        messages.push(`New tab: ${result}`);
        if (surfaceRef) {
          await cmux.send(`cd ${cwd} && claude`, surfaceRef, workspaceRef);
          await cmux.sendKey("Enter", surfaceRef, workspaceRef);
        }
        break;
      }
      case "split": {
        const splitResult = await cmux.newSplit(direction, workspaceRef);
        const splitStr = typeof splitResult === "string" ? splitResult : JSON.stringify(splitResult, null, 2);
        const surfMatch = splitStr.match(/surface:\d+/);
        const wsMatch = splitStr.match(/workspace:\d+/);
        surfaceRef = surfMatch ? surfMatch[0] : undefined;
        workspaceRef = wsMatch ? wsMatch[0] : workspaceRef;
        messages.push(`Split: ${splitStr}`);
        if (surfaceRef) {
          await cmux.send(`cd ${cwd} && claude`, surfaceRef, workspaceRef);
          await cmux.sendKey("Enter", surfaceRef, workspaceRef);
        }
        break;
      }
      case "workspace": {
        const result = await cmux.newWorkspace(cwd, "claude");
        const resultStr = typeof result === "string" ? result : JSON.stringify(result, null, 2);
        const wsMatch = resultStr.match(/workspace:\d+/);
        workspaceRef = wsMatch ? wsMatch[0] : workspaceRef;
        messages.push(resultStr);
        if (name && workspaceRef) {
          await cmux.renameWorkspace(name, workspaceRef);
          messages.push(`Renamed to "${name}"`);
        }
        break;
      }
    }

    if (prompt && workspaceRef) {
      await new Promise((r) => setTimeout(r, 5000));
      await cmux.send(prompt, surfaceRef, workspaceRef);
      await cmux.sendKey("Enter", surfaceRef, workspaceRef);
      messages.push(`Sent prompt to ${surfaceRef || workspaceRef}`);
    }

    return {
      content: [{ type: "text" as const, text: messages.join("\n") }],
    };
  }
);

// --- send_to_session ---
server.tool(
  "send_to_session",
  "Send a message to another agent's cmux workspace. Automatically prefixes with sender identity so the receiver knows who sent it and where to reply.",
  {
    to: z.string().describe("Target workspace ref to send the message to"),
    host: z.string().optional().describe("Host name. Defaults to 'local'."),
    surface: z.string().optional().describe("Surface ref if targeting a specific surface"),
    text: z.string().describe("Message to send"),
  },
  async ({ to, host, surface, text }) => {
    const from = await cmux.getMyWorkspaceRef();
    const message = `[from ${from}] ${text}`;
    await cmux.send(message, surface, to, host);
    await cmux.sendKey("Enter", surface, to, host);
    return {
      content: [{ type: "text" as const, text: `Sent to ${to}.` }],
    };
  }
);

// --- send_key ---
server.tool(
  "send_key",
  "Send a key press to a cmux surface (e.g. Enter, Escape, ctrl-c)",
  {
    host: z.string().optional().describe("Host name. Defaults to 'local'."),
    workspace: z.string().describe("Workspace ref"),
    surface: z.string().optional().describe("Surface ref"),
    key: z.string().describe("Key to send"),
  },
  async ({ host, workspace, surface, key }) => {
    await cmux.sendKey(key, surface, workspace, host);
    return {
      content: [{ type: "text" as const, text: `Sent key: ${key}` }],
    };
  }
);

// --- read_screen ---
server.tool(
  "read_screen",
  "Read terminal screen content from a cmux surface",
  {
    host: z.string().optional().describe("Host name. Defaults to 'local'."),
    workspace: z.string().describe("Workspace ref"),
    surface: z.string().optional().describe("Surface ref"),
    scrollback: z.boolean().default(false).describe("Include scrollback buffer"),
    lines: z.number().int().optional().describe("Number of lines to read"),
  },
  async ({ host, workspace, surface, scrollback, lines }) => {
    const content = await cmux.readScreen(surface, workspace, scrollback, lines, host);
    return {
      content: [{ type: "text" as const, text: content }],
    };
  }
);

// --- find_session ---
server.tool(
  "find_session",
  "Search cmux workspaces by name or content. Omit host to search all hosts.",
  {
    host: z.string().optional().describe("Host name. Omit to search all."),
    query: z.string().describe("Search query"),
    search_content: z.boolean().default(false).describe("Search terminal content too"),
  },
  async ({ host, query, search_content }) => {
    if (host) {
      const result = await cmux.findWindow(query, search_content, host);
      return {
        content: [{
          type: "text" as const,
          text: typeof result === "string" ? result : JSON.stringify(result, null, 2),
        }],
      };
    }
    const all = await cmux.findWindowAll(query, search_content);
    return {
      content: [{ type: "text" as const, text: JSON.stringify(all, null, 2) }],
    };
  }
);

const transport = new StdioServerTransport();
await server.connect(transport);
