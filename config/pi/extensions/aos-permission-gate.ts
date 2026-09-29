/**
 * aos permission gate for Pi. Installed by agentic-os (`aos sync`) into <pi agent dir>/extensions;
 * edit the copy in the agentic-os repo (config/pi/extensions), not the installed one.
 *
 * Pi on the local model runs its tools on this PC with no permission prompts of its own. Before any
 * tool that is not read-only (a shell command, a file write or edit, or a tool an extension adds),
 * this asks the person: Paseo shows the dialog on the phone. With no UI to ask, the tool is blocked.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const READ_ONLY = new Set(["read", "grep", "find", "ls"]);

function describe(toolName: string, input: Record<string, unknown>): string {
  if (typeof input.command === "string") return `${toolName}: ${input.command}`;
  if (typeof input.path === "string") return `${toolName}: ${input.path}`;
  const json = JSON.stringify(input);
  return `${toolName}: ${json.length > 300 ? json.slice(0, 300) + "..." : json}`;
}

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", async (event, ctx) => {
    if (READ_ONLY.has(event.toolName)) return undefined;
    if (!ctx.hasUI) return { block: true, reason: "aos permission gate: no UI to ask for approval" };
    const input = (event.input ?? {}) as Record<string, unknown>;
    const choice = await ctx.ui.select(`Allow ${describe(event.toolName, input)}?`, ["Allow", "Deny"]);
    if (choice !== "Allow") return { block: true, reason: "Denied by the user" };
    return undefined;
  });
}
