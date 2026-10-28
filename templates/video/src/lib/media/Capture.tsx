// A live capture of a public page or product (basis "capture", R35) inside a plain browser frame, so the viewer
// reads it as the real page. The address bar shows the host from the ledger's source tag, not authored words.
import React from "react";
import { AbsoluteFill } from "remotion";
import { ASSETS } from "../../data/assets";
import { USES } from "../../data/asset-uses";
import { SANS, type Look } from "../look";
import { Clip } from "./Clip";
import { Photo } from "./Photo";

type Props = { asset: keyof typeof ASSETS & string; use: string; look: Look };

const FRAME = { left: 140, top: 96, width: 1640, height: 888 };
const BAR = 44;

export const Capture: React.FC<Props> = ({ asset, use, look }) => {
  const credit = USES[asset][use].credit || "";
  const host = credit.replace(/^Source:\s*/, "").split(",")[0];
  const still = ASSETS[asset].kind === "photo";
  return (
    <AbsoluteFill style={{ background: look.bg }}>
      <div style={{ position: "absolute", ...FRAME, borderRadius: 12, overflow: "hidden", boxShadow: "0 30px 80px rgba(0,0,0,0.45)", background: "#1b1b1d" }}>
        <div style={{ height: BAR, display: "flex", alignItems: "center", gap: 10, padding: "0 18px", background: "#2a2a2d", color: look.inkSoft, font: `500 20px ${SANS}` }}>
          <span style={{ width: 12, height: 12, borderRadius: 6, background: "#5a5a5e" }} />
          <span style={{ width: 12, height: 12, borderRadius: 6, background: "#5a5a5e" }} />
          <span style={{ width: 12, height: 12, borderRadius: 6, background: "#5a5a5e" }} />
          <span style={{ marginLeft: 16 }}>{host}</span>
        </div>
        <div style={{ position: "absolute", top: BAR, left: 0, right: 0, bottom: 0 }}>
          {still ? <Photo asset={asset} use={use} look={look} /> : <Clip asset={asset} use={use} look={look} />}
        </div>
      </div>
    </AbsoluteFill>
  );
};
