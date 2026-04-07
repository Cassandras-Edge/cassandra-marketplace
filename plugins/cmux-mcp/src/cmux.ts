import { execFile } from "node:child_process";

// Default cmux binary path (can be overridden per-host)
const DEFAULT_CMUX_PATH =
  process.env.CMUX_PATH ||
  "/Applications/cmux.app/Contents/Resources/bin/cmux";

export interface HostConfig {
  /** SSH target, e.g. "andrew@100.68.179.35". Omit for local. */
  ssh?: string;
  /** Path to cmux binary on this host */
  cmuxPath?: string;
  /** Socket password for cmux on this host */
  password?: string;
}

export interface Workspace {
  id: string;
  name: string;
  cwd: string;
  panes: Pane[];
}

export interface Pane {
  id: string;
  type: string;
}

export interface Surface {
  id: string;
  type: string;
}

// Host registry — loaded from CMUX_HOSTS env var or defaults to local-only
let hosts: Record<string, HostConfig> = { local: {} };

export function loadHosts(): void {
  const raw = process.env.CMUX_HOSTS;
  if (raw) {
    try {
      const parsed = JSON.parse(raw) as Record<string, HostConfig>;
      // Always ensure "local" exists
      if (!parsed.local) parsed.local = {};
      hosts = parsed;
    } catch (e) {
      console.error("Failed to parse CMUX_HOSTS:", e);
    }
  }
}

export function getHosts(): Record<string, HostConfig> {
  return { ...hosts };
}

export function getHostNames(): string[] {
  return Object.keys(hosts);
}

function resolveHost(hostName?: string): { name: string; config: HostConfig } {
  const name = hostName || "local";
  const config = hosts[name];
  if (!config) {
    throw new Error(
      `Unknown host "${name}". Available: ${Object.keys(hosts).join(", ")}`
    );
  }
  return { name, config };
}

function exec(args: string[], hostName?: string): Promise<string> {
  const { config } = resolveHost(hostName);
  const cmuxPath = config.cmuxPath || DEFAULT_CMUX_PATH;
  const password = config.password || process.env.CMUX_SOCKET_PASSWORD;

  const cmuxArgs = password ? ["--password", password, ...args] : args;

  if (config.ssh) {
    // Remote execution via SSH
    // Quote the cmux command for remote shell
    const remoteCmd = [cmuxPath, ...cmuxArgs]
      .map((a) => `'${a.replace(/'/g, "'\\''")}'`)
      .join(" ");
    return new Promise((resolve, reject) => {
      execFile(
        "ssh",
        [
          "-o", "ConnectTimeout=5",
          "-o", "StrictHostKeyChecking=accept-new",
          config.ssh!,
          remoteCmd,
        ],
        { timeout: 30000 },
        (err, stdout, stderr) => {
          if (err) {
            reject(
              new Error(
                `cmux ${args[0]} on ${config.ssh} failed: ${stderr || err.message}`
              )
            );
            return;
          }
          resolve(stdout.trim());
        }
      );
    });
  }

  // Local execution
  return new Promise((resolve, reject) => {
    execFile(cmuxPath, cmuxArgs, { timeout: 30000 }, (err, stdout, stderr) => {
      if (err) {
        reject(new Error(`cmux ${args[0]} failed: ${stderr || err.message}`));
        return;
      }
      resolve(stdout.trim());
    });
  });
}

function tryParseJson(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
}

// --- Fan-out helpers ---

/** Run a command on all hosts in parallel, return results keyed by host name */
export async function execAll(
  fn: (host: string) => Promise<unknown>
): Promise<Record<string, unknown>> {
  const results: Record<string, unknown> = {};
  const entries = Object.keys(hosts);
  await Promise.allSettled(
    entries.map(async (name) => {
      try {
        results[name] = await fn(name);
      } catch (e) {
        results[name] = { error: (e as Error).message };
      }
    })
  );
  return results;
}

// --- Identity ---

let _myWorkspaceRef: string | null = null;

/** Resolve this process's workspace UUID to a short ref via cmux identify */
export async function getMyWorkspaceRef(): Promise<string> {
  if (_myWorkspaceRef) return _myWorkspaceRef;
  try {
    const out = await exec(["identify"]);
    const match = out.match(/"workspace_ref"\s*:\s*"(workspace:\d+)"/);
    if (match) {
      _myWorkspaceRef = match[1];
      return _myWorkspaceRef;
    }
  } catch {}
  return process.env.CMUX_WORKSPACE_ID || "unknown";
}

// --- Commands ---

export async function listWorkspaces(host?: string): Promise<string> {
  // Use tree --all for full cross-window visibility with surface titles
  return exec(["tree", "--all"], host);
}

export async function listAllWorkspaces(): Promise<Record<string, unknown>> {
  return execAll((h) => listWorkspaces(h));
}

export async function listPanes(
  workspaceRef?: string,
  host?: string
): Promise<unknown> {
  const args = ["list-panes"];
  if (workspaceRef) args.push("--workspace", workspaceRef);
  const out = await exec(args, host);
  return tryParseJson(out);
}

export async function listPaneSurfaces(
  workspaceRef?: string,
  paneRef?: string,
  host?: string
): Promise<unknown> {
  const args = ["list-pane-surfaces"];
  if (workspaceRef) args.push("--workspace", workspaceRef);
  if (paneRef) args.push("--pane", paneRef);
  const out = await exec(args, host);
  return tryParseJson(out);
}

export async function tree(
  workspaceRef?: string,
  host?: string
): Promise<string> {
  const args = ["tree"];
  if (workspaceRef) args.push("--workspace", workspaceRef);
  return exec(args, host);
}

export async function newWorkspace(
  cwd?: string,
  command?: string,
  host?: string
): Promise<unknown> {
  const args = ["new-workspace"];
  if (cwd) args.push("--cwd", cwd);
  if (command) args.push("--command", command);
  const out = await exec(args, host);
  return tryParseJson(out);
}

export async function send(
  text: string,
  surfaceRef?: string,
  workspaceRef?: string,
  host?: string
): Promise<string> {
  const args = ["send"];
  if (workspaceRef) args.push("--workspace", workspaceRef);
  if (surfaceRef) args.push("--surface", surfaceRef);
  args.push(text);
  return exec(args, host);
}

export async function sendKey(
  key: string,
  surfaceRef?: string,
  workspaceRef?: string,
  host?: string
): Promise<string> {
  const args = ["send-key"];
  if (workspaceRef) args.push("--workspace", workspaceRef);
  if (surfaceRef) args.push("--surface", surfaceRef);
  args.push(key);
  return exec(args, host);
}

export async function readScreen(
  surfaceRef?: string,
  workspaceRef?: string,
  scrollback = false,
  lines?: number,
  host?: string
): Promise<string> {
  const args = ["read-screen"];
  if (workspaceRef) args.push("--workspace", workspaceRef);
  if (surfaceRef) args.push("--surface", surfaceRef);
  if (scrollback) args.push("--scrollback");
  if (lines) args.push("--lines", String(lines));
  return exec(args, host);
}

export async function capturePane(
  surfaceRef?: string,
  workspaceRef?: string,
  scrollback = false,
  lines?: number,
  host?: string
): Promise<string> {
  const args = ["capture-pane"];
  if (workspaceRef) args.push("--workspace", workspaceRef);
  if (surfaceRef) args.push("--surface", surfaceRef);
  if (scrollback) args.push("--scrollback");
  if (lines) args.push("--lines", String(lines));
  return exec(args, host);
}

export async function newSplit(
  direction: "left" | "right" | "up" | "down",
  workspaceRef?: string,
  surfaceRef?: string,
  host?: string
): Promise<unknown> {
  const args = ["new-split", direction];
  if (workspaceRef) args.push("--workspace", workspaceRef);
  if (surfaceRef) args.push("--surface", surfaceRef);
  const out = await exec(args, host);
  return tryParseJson(out);
}

export async function newPane(
  type?: "terminal" | "browser",
  direction?: "left" | "right" | "up" | "down",
  workspaceRef?: string,
  host?: string
): Promise<unknown> {
  const args = ["new-pane"];
  if (type) args.push("--type", type);
  if (direction) args.push("--direction", direction);
  if (workspaceRef) args.push("--workspace", workspaceRef);
  const out = await exec(args, host);
  return tryParseJson(out);
}

export async function focusPane(
  paneRef: string,
  workspaceRef?: string,
  host?: string
): Promise<string> {
  const args = ["focus-pane", "--pane", paneRef];
  if (workspaceRef) args.push("--workspace", workspaceRef);
  return exec(args, host);
}

export async function findWindow(
  query: string,
  content = false,
  host?: string
): Promise<unknown> {
  const args = ["find-window"];
  if (content) args.push("--content");
  args.push(query);
  const out = await exec(args, host);
  return tryParseJson(out);
}

export async function findWindowAll(
  query: string,
  content = false
): Promise<Record<string, unknown>> {
  return execAll((h) => findWindow(query, content, h));
}

export async function newSurface(
  workspaceRef?: string,
  paneRef?: string,
  host?: string
): Promise<string> {
  const args = ["new-surface", "--type", "terminal"];
  if (workspaceRef) args.push("--workspace", workspaceRef);
  if (paneRef) args.push("--pane", paneRef);
  return exec(args, host);
}

export async function renameWorkspace(
  title: string,
  workspaceRef?: string,
  host?: string
): Promise<string> {
  const args = ["rename-workspace"];
  if (workspaceRef) args.push("--workspace", workspaceRef);
  args.push(title);
  return exec(args, host);
}
