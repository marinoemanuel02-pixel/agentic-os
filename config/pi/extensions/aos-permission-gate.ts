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

// The reason is what the model reads as the tool's result. A 4B model read "Denied by the user" as the
// command's output and reported success (measured 2026-09-29), so the wording leaves no room for that.
const DENIED = "NOT RUN: the user denied permission for this tool call. Nothing was executed and nothing changed. Tell the user it did not run.";
const NO_UI = "NOT RUN: nobody is available to approve this tool call. Nothing was executed and nothing changed.";

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", async (event, ctx) => {
    if (READ_ONLY.has(event.toolName)) return undefined;
    if (!ctx.hasUI) return { block: true, reason: NO_UI };
    const input = (event.input ?? {}) as Record<string, unknown>;
    const choice = await ctx.ui.select(`Allow ${describe(event.toolName, input)}?`, ["Allow", "Deny"]);
    if (choice !== "Allow") return { block: true, reason: DENIED };
    return undefined;
  });
}
