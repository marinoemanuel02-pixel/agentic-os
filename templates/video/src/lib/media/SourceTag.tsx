// The on-screen source credit of a fair-use or capture use (R35). A forwarding helper: its text comes from the
// ledger through src/data/asset-uses.ts and is covered by the generated label claims in claims.json (R24).
import React from "react";
import { SANS } from "../look";

export const SourceTag: React.FC<{ text: string; ink?: string }> = ({ text, ink = "#ede7db" }) => (
  <div
    style={{
      position: "absolute",
      left: 64,
      bottom: 52,
      padding: "8px 14px",
      background: "rgba(8, 8, 9, 0.62)",
      color: ink,
      font: `500 26px ${SANS}`,
      letterSpacing: 0.3,
      borderRadius: 4,
    }}
  >
    {text}
  </div>
);
