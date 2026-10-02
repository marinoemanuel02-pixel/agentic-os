// QA renders (tools/qa.sh renders a proxy with inputProps {qa: true}) must be free of texture that changes every
// frame (film grain, line boil, noise), or the motion check reads it as motion. Every such effect reads this flag.
import { getInputProps } from "remotion";

export const QA = Boolean((getInputProps() as { qa?: boolean }).qa);
