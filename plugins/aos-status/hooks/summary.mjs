const percentage = value => typeof value === 'number' && Number.isFinite(value) && value >= 0 && value <= 100;
const stamp = value => typeof value === 'string' ? Date.parse(value) : NaN;
const label = value => String(value ?? '').replace(/[\x00-\x1f\x7f]/g, '').slice(0, 100);

export function summarize({ now, actors, claims, ledger = [], usage, notices = [] } = {}) {
  const rows = actors?.actors;
  const active = rows && typeof rows === 'object' && !Array.isArray(rows)
    ? Object.values(rows).filter(row => row && ['reserved', 'running', 'waiting-input', 'suspect'].includes(row.state))
      .slice(0, 20).map(row => ({ id: label(row.id), vendor: label(row.vendor), state: label(row.state) }))
    : null;
  const capacity = ['claude', 'codex'].map(vendor => {
    const observed = ledger.filter(row => row?.type === 'capacity' && row.vendor === vendor).at(-1);
    const result = { vendor, state: 'unknown', remaining: null, observed: null, resets: null };
    const reported = stamp(observed?.ts);
    if (!observed || !percentage(observed.remaining) || !Number.isFinite(reported) || reported > now) return result;
    result.observed = observed.ts;
    const reset = stamp(observed.resets);
    if (Number.isFinite(reset)) result.resets = observed.resets;
    if (Number.isFinite(reset) && reset <= now) result.state = 'reset';
    else if (observed.remaining === 0 && reset > now) { result.state = 'limited'; result.remaining = 0; }
    else if (now - reported >= 5 * 3600000) result.state = 'stale';
    else { result.state = observed.remaining <= 30 ? 'low' : 'ok'; result.remaining = observed.remaining; }
    return result;
  });
  return {
    actors: active,
    claims: Array.isArray(claims) ? claims.filter(row => stamp(row?.expires) > now).length : null,
    capacity, context: percentage(usage?.context?.percent) ? usage.context.percent : null,
    notices: notices.map(label).slice(0, 8),
  };
}
