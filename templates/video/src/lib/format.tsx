// The frame the film is composed for: the 16:9 film (wide, the default) or a native 9:16 version for Reels, Shorts
// and TikTok (tall). Shots read it with useFormat() and pick their own staging; a composition wraps its tree in
// <FormatProvider format={TALL}>. One source renders both formats (pauseai-it final-v20 and its vertical, 2026-10-29);
// a boxed 16:9 inside 9:16 was rejected, every shot was restaged for the tall frame instead.
import React, { createContext, useContext } from "react";

export type Format = { W: number; H: number; tall: boolean };

export const WIDE: Format = { W: 1920, H: 1080, tall: false };
export const TALL: Format = { W: 1080, H: 1920, tall: true };

const FormatCtx = createContext<Format>(WIDE);

export const FormatProvider: React.FC<{ format: Format; children: React.ReactNode }> = ({ format, children }) => (
  <FormatCtx.Provider value={format}>{children}</FormatCtx.Provider>
);

export const useFormat = (): Format => useContext(FormatCtx);

/** Pick the wide or the tall value of a layout: `const L = useLayout({ ... }, { ... })`. */
export const useLayout = <T,>(wide: T, tall: T): T => (useFormat().tall ? tall : wide);

/**
 * Where the apps draw their own interface over a 9:16 frame (Reels, TikTok): keep faces, type and props out of the
 * top band, the bottom band and the right-hand button column. Captions sit just above `bottom`.
 */
export const SAFE = { top: 220, bottom: 1500, right: 940, rightFrom: 900 };
