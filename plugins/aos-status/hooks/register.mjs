import { summarize } from './summary.mjs';

const PANE = 'aos-status';
const MAX_BYTES = 524288;
let snapshot = null;

async function readRecord($, path) {
  const info = await $.fs.stat(path);
  if (!Number.isFinite(info?.size) || info.size < 0 || info.size > MAX_BYTES) throw Error('record size unavailable');
  const value = await $.fs.read(path);
  if (typeof value !== 'string' || value.length > MAX_BYTES) throw Error('record too large');
  return value.replace(/^\uFEFF/, '');
}

export function register(on) {
  on('session.start', async ($, e, next) => {
    await $.command.register({ name: 'aos-status', description: 'Show local agent status without a model request', immediate: true });
    return next(e);
  });

  on('command.run', { command: 'aos-status' }, async ($) => {
    const now = await $.clock.now();
    let root = await $.env.get('AOS_COORD');
    if (!root) {
      const home = await $.env.get('USERPROFILE') || await $.env.get('HOME');
      if (home) root = home.replace(/[\\/]$/, '') + '/.aos/coord';
    }
    const notices = [];
    let actors = null, claims = null, ledger = [], usage = null;
    if (root) {
      root = root.replace(/\\/g, '/').replace(/\/$/, '');
      try { actors = JSON.parse(await readRecord($, root + '/actors.json')); }
      catch { notices.push('Actor records unavailable'); }
      try {
        const text = await readRecord($, root + '/ledger.jsonl');
        for (const line of text.split(/\r?\n/)) {
          if (!line.trim()) continue;
          ledger.push(JSON.parse(line));
        }
      } catch { ledger = []; notices.push('Capacity records unavailable'); }
      try {
        const entries = await $.fs.list(root + '/claims');
        if (!Array.isArray(entries) || entries.length > 100) throw Error('too many claims');
        claims = [];
        for (const entry of entries) {
          if (entry.isLink || !/^[a-zA-Z0-9_-]+\.json$/.test(entry.name)) throw Error('unrecognized claim entry');
          claims.push(JSON.parse(await readRecord($, root + '/claims/' + entry.name)));
        }
      } catch { claims = null; notices.push('Claim records unavailable'); }
    } else notices.push('Coordination records unavailable');
    try { usage = await $.session.usage(); }
    catch { notices.push('Session context unavailable'); }
    snapshot = { ...summarize({ now, actors, claims, ledger, usage, notices }), checked: new Date(now).toISOString() };
    await $.ui.open({ id: PANE, title: 'Agent status', focus: true, closeOnEscape: true });
    $.ui.invalidate('ui.render');
    return {};
  });

  on('ui.render', { component: 'Pane' }, async ($, e, next) => {
    if (e.requestId !== PANE) return next(e);
    const { Box, Text, Button } = $.ui.resolve(e);
    const view = snapshot;
    const lines = view ? [
      'Checked: ' + view.checked,
      'Context: ' + (view.context === null ? 'unknown' : view.context + '%'),
      'Live checkout claims: ' + (view.claims === null ? 'unknown' : view.claims),
      'Active work: ' + (view.actors === null ? 'unknown' : view.actors.length + ' (up to 20 shown)'),
      ...(view.actors || []).map(row => row.vendor + ' / ' + row.id + ' / ' + row.state),
      ...view.capacity.map(row => row.vendor + ': ' + row.state + (row.remaining === null ? '' : ' / ' + row.remaining + '% recorded left') +
        (row.observed ? ' / observed ' + row.observed : '') + (row.resets ? ' / reset ' + row.resets : '')),
      ...view.notices,
      'Recorded capacity is not a live subscription guarantee.',
    ] : ['Run /aos-status to read the current records.'];
    return Box({ flexDirection: 'column', children: [
      ...lines.map(line => Text({ children: [line] })),
      Button({ key: 'refresh', label: 'Refresh', onPress: async () => {
        await $.command.run({ command: 'aos-status', args: '' });
      } }),
    ] });
  });
}
