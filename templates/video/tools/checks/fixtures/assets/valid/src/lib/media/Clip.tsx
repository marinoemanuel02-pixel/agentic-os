import { OffthreadVideo, staticFile } from "remotion";
import { ASSETS } from "../../data/assets";
export const Clip = ({ asset }: { asset: keyof typeof ASSETS; use: string }) => <OffthreadVideo src={staticFile(ASSETS[asset].src)} muted />;
