// The ## Credits block for description.md: every non-empty credit once, plus the line Poly Haven's API asks for.
const isPolyHaven = url => {
  try { return /(^|\.)polyhaven\.com$/.test(new URL(url).hostname); } catch { return false; }
};

export function creditsBlock(rows) {
  const lines = [];
  for (const r of rows) {
    const credit = (r.credit || '').trim();
    if (credit && !lines.includes(credit)) lines.push(credit);
  }
  if (rows.some(r => r.url && isPolyHaven(r.url))) lines.push('Powered by Poly Haven');
  return `## Credits\n\n${lines.map(l => `- ${l}`).join('\n')}\n`;
}
