// Read-only comparison of fixed evaluation reports and their current host receipts.
// Usage: node tools/coordination-compare.mjs <report.json> <report.json> [...]
import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { basename, dirname, resolve } from 'node:path';

const numeric = value => typeof value === 'number' && Number.isFinite(value) && value >= 0;
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const parse = bytes => JSON.parse(bytes.toString('utf8').replace(/^\uFEFF/, ''));
const identityKeys = ['baseline_tree', 'task_sha256', 'grader_sha256'];

function identity(trial) {
  const fields = trial.input_identity;
  if (!fields || !/^(?:[a-f0-9]{40}|[a-f0-9]{64})$/i.test(fields.baseline_tree ?? '') ||
      identityKeys.slice(1).some(key => !/^[a-f0-9]{64}$/i.test(fields[key] ?? ''))) return null;
  return identityKeys.map(key => fields[key].toLowerCase()).join(':');
}

async function readAttempt(trial, reportPath, mode) {
  const reasons = [];
  if (mode !== 'execute') reasons.push('report was not executed');
  const input = identity(trial);
  if (!input) reasons.push('missing or invalid input fingerprints');
  const attempt = {
    trial_id: trial.id, report: reportPath, input_identity: trial.input_identity ?? null,
    requested_route: trial.requested_route ?? null, receipt_id: null, receipt_sha256: null,
    vendor: null, tier: null, transport: null, observed_model: null, observed_effort: null,
    accepted: null, outcome: null, delegate_seconds: null, corrections: null,
    integration_seconds: null, review_seconds: null, known_total_seconds: null,
    reasons,
  };
  try {
    if (typeof trial.receipt_ref !== 'string' || !trial.receipt_ref) throw Error('missing host receipt reference');
    const path = resolve(dirname(reportPath), trial.receipt_ref);
    const bytes = await readFile(path);
    const receipt = parse(bytes);
    attempt.receipt_id = receipt.id;
    attempt.receipt_sha256 = digest(bytes);
    if (receipt.id !== basename(dirname(path)) || receipt.task_id !== trial.id ||
        receipt.task_class !== trial.task_class) reasons.push('host receipt identity does not match trial');
    if (!trial.requested_route || receipt.vendor !== trial.requested_route.vendor ||
        receipt.transport !== trial.requested_route.transport) reasons.push('host receipt route does not match trial');
    if (receipt.accepted !== trial.accepted || receipt.outcome !== trial.outcome) {
      reasons.push('host outcome differs from report snapshot');
    }
    if (receipt.accepted === true && (receipt.outcome !== 'accepted' || receipt.verify?.exit_code !== 0)) {
      reasons.push('host acceptance lacks a successful verification');
    }
    attempt.vendor = receipt.vendor ?? null;
    attempt.tier = receipt.tier ?? null;
    attempt.transport = receipt.transport ?? null;
    attempt.observed_model = receipt.observed_model ?? null;
    attempt.observed_effort = receipt.observed_effort ?? null;
    attempt.accepted = receipt.accepted === true && receipt.outcome === 'accepted' && receipt.verify?.exit_code === 0;
    attempt.outcome = receipt.outcome ?? null;
    attempt.delegate_seconds = numeric(receipt.seconds) ? receipt.seconds : null;
    attempt.corrections = Number.isInteger(receipt.corrections) && receipt.corrections >= 0 ? receipt.corrections : null;
    attempt.integration_seconds = numeric(receipt.phase_seconds?.integration) ? receipt.phase_seconds.integration : null;
    attempt.review_seconds = numeric(receipt.phase_seconds?.review) ? receipt.phase_seconds.review : null;
    // Waiting is already inside delegate execution. Never sum all phase fields.
    const measured = [attempt.delegate_seconds, attempt.integration_seconds, attempt.review_seconds];
    if (measured.every(numeric)) attempt.known_total_seconds = measured.reduce((sum, value) => sum + value, 0);
  } catch (error) {
    reasons.push(`host receipt unavailable: ${error.code ?? error.message}`);
  }
  return { input, attempt };
}

async function main() {
  const reports = process.argv.slice(2).map(path => resolve(path));
  if (reports.length < 2 || new Set(reports).size !== reports.length) {
    throw Error('Supply at least two distinct evaluation report files.');
  }
  const groups = new Map();
  for (const path of reports) {
    const report = parse(await readFile(path));
    if (report.version !== 1 || !Array.isArray(report.trials)) throw Error('Unsupported evaluation report.');
    for (const trial of report.trials) {
      if (typeof trial.case_id !== 'string' || !trial.case_id || trial.task_class !== trial.case_id) {
        throw Error('Evaluation case identity is missing or inconsistent.');
      }
      if (!groups.has(trial.case_id)) groups.set(trial.case_id, []);
      groups.get(trial.case_id).push(await readAttempt(trial, path, report.mode));
    }
  }
  const comparisons = [...groups].map(([case_id, rows]) => {
    const attempts = rows.map(row => row.attempt);
    const reasons = attempts.flatMap(attempt => attempt.reasons);
    const inputs = new Set(rows.map(row => row.input));
    if (inputs.size !== 1) reasons.push('different input fingerprints');
    if (rows.length < 2) reasons.push('fewer than two attempts');
    const routes = new Set(attempts.map(attempt =>
      [attempt.vendor, attempt.tier, attempt.transport, attempt.requested_route?.workers].join('|')));
    if (routes.size < 2) reasons.push('fewer than two distinct routes');
    const comparable_inputs = reasons.length === 0 && !inputs.has(null);
    const complete_effort = comparable_inputs && attempts.every(attempt =>
      attempt.accepted && numeric(attempt.known_total_seconds) && attempt.corrections !== null);
    return { case_id, comparable_inputs, complete_effort, reasons: [...new Set(reasons)], attempts };
  });
  process.stdout.write(JSON.stringify({
    version: 1, comparisons, subscription_savings: null, routing_change: null,
    limitations: [
      'Input fingerprints identify declared fixed fixtures, not representative task distributions.',
      'Check contract write scopes, budgets and environment separately; input matches do not establish causal comparability.',
      'Host acceptance is not user acceptance; totals include only explicitly measured effort.',
      'Repeated and failed attempts remain separate; this report makes no statistical route ranking.',
      'Model, authentication and active surface require their own observations; unknown values stay unknown.',
    ],
  }, null, 2) + '\n');
}

main().catch(error => {
  process.stderr.write(JSON.stringify({ error: error.message }) + '\n');
  process.exitCode = 1;
});
