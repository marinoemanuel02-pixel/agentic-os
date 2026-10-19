import { expect, mock, test } from 'claude-code/testing';

const PANE = { plugin: 'aos-status', component: 'Pane', requestId: 'aos-status',
  viewport: { columns: 100, rows: 30 }, props: { title: 'Agent status', isFocused: true,
    bodyColumns: 60, placement: 'inline', scroll: { offset: 0, bodyRows: 10 }, view: {} } } as const;

test('registers an immediate command without reading records at startup', async ($, on) => {
  let registered: any = null;
  on('command.register', ($, e) => { registered = e; return { value: undefined }; });
  on('session.start', () => ({ cwd: '/fixture' }));
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/fixture' });
  expect(registered.name).toBe('aos-status');
  expect(registered.immediate).toBe(true);
});

test('shows bounded coordination and context in terminal and desktop test surfaces', async ($, on) => {
  mock.clock(on, { now: Date.parse('2026-10-19T19:00:00Z') });
  mock.env(on, { AOS_COORD: '/fixture/coord' });
  let reads = 0;
  on('fs.stat', () => ({ value: { size: 100 } }));
  on('fs.list', () => ({ value: [] }));
  on('fs.read', ($, e) => {
    reads += 1;
    return { value: e.path.endsWith('actors.json') ? JSON.stringify({ actors: {
      a: { id: 'worker-a', vendor: 'codex', state: 'running', text: 'private task' },
    } }) : '' };
  });
  on('session.usage', () => ({ value: { context: { percent: 23.4 } } }));
  on('ui.open', () => ({ value: undefined }));
  await $.command.run({ command: 'aos-status', args: '' });
  expect(reads).toBe(2);
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...PANE, surface });
    expect(await ui.find({ type: 'Text', text: /worker-a/ })).toBeDefined();
    expect(await ui.find({ type: 'Text', text: /23.4%/ })).toBeDefined();
    expect(await ui.find({ type: 'Text', text: /private task/ })).toBeUndefined();
    await ui.unmount();
  }
});

test('oversized or missing records remain unknown without a file read', async ($, on) => {
  mock.clock(on);
  mock.env(on, { AOS_COORD: '/fixture/coord' });
  on('fs.stat', () => ({ value: { size: 9000000 } }));
  on('fs.list', () => { throw Error('missing'); });
  on('session.usage', () => { throw Error('unavailable'); });
  on('ui.open', () => ({ value: undefined }));
  await $.command.run({ command: 'aos-status', args: '' });
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' });
  expect(await ui.find({ type: 'Text', text: /Context: unknown/ })).toBeDefined();
  expect(await ui.find({ type: 'Text', text: /records unavailable/ })).toBeDefined();
});

test('leaves unrelated panes untouched', async ($, on) => {
  on('ui.render', () => ({ type: 'Text', props: {}, children: ['other pane'] }));
  const ui = await $.ui.mount({ ...PANE, requestId: 'other', surface: 'terminal' });
  expect(await ui.find({ type: 'Text', text: 'other pane' })).toBeDefined();
});
