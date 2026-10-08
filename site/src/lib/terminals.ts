import type { StateKind } from './marks';

/** How a stretch of terminal text is coloured. */
export type Tone = 'dim' | 'user' | 'tool' | 'add' | 'del' | 'ok' | 'err' | 'busy' | 'pick';
export type Span = string | [text: string, tone: Tone];
export type Line = Span[];

/** A Claude Code session in its terminal, as it looks at one moment. */
export interface Terminal {
  title: string;
  kind: StateKind;
  lines: Line[];
  /** The permission dialog the session is stopped at. */
  asks?: Line[];
}

const tool = (name: string, argument: string): Line => [['⏺ ', 'ok'], [name, 'tool'], ['(' + argument + ')', 'dim']];
const result = (text: string): Line => [['  ⎿  ' + text, 'dim']];

export const TERMINALS: Record<'widget' | 'migration' | 'tests' | 'docs' | 'sandbox', Terminal> = {
  widget: {
    title: 'cashier-lite — claude',
    kind: 'working',
    lines: [
      [['> ', 'dim'], ['disable the deposit button until the amount is valid', 'user']],
      tool('Read', 'src/components/quick-deposit-view/QuickDepositView.tsx'),
      result('Read 142 lines'),
      tool('Update', 'QuickDepositView.tsx'),
      result('Updated with 3 additions and 1 removal'),
      [['     38 ', 'dim'], ['-  <button class={styles.cta}>', 'del']],
      [['     38 ', 'dim'], ['+  <button class={styles.cta} disabled={!isValid}>', 'add']],
      [['     39 ', 'dim'], ["+    {isLoading ? <Spinner /> : t('deposit')}", 'add']],
      [['     40 ', 'dim'], ['+  </button>', 'add']],
      [['✻ ', 'busy'], ['Running the type check… ', 'busy'], ['(14s · esc to interrupt)', 'dim']],
    ],
  },
  migration: {
    title: 'payments-api — claude',
    kind: 'waiting',
    lines: [
      [['> ', 'dim'], ['add the refunded_at column and migrate staging', 'user']],
      tool('Write', 'migrations/0042_orders_refunded_at.sql'),
      result('Wrote 18 lines'),
      tool('Bash', 'npm run migrate -- --env staging'),
    ],
    asks: [
      [['Bash command', 'tool']],
      ['  npm run migrate -- --env staging'],
      [['  Runs pending migrations against staging', 'dim']],
      ['Do you want to proceed?'],
      [['❯ 1. Yes', 'pick']],
      ['  2. No, and tell Claude what to do differently'],
    ],
  },
  tests: {
    title: 'frontoffice — claude',
    kind: 'working',
    lines: [
      tool('Bash', 'swift test --filter SessionCoreTests'),
      result("Test Suite 'SessionCoreTests' started"),
      [['     ✓ ', 'ok'], ['testWaitingWinsOverWorking ', 'dim'], ['(0.003s)', 'dim']],
      [['     ✓ ', 'ok'], ['testFinishedGivesWayToOthers ', 'dim'], ['(0.002s)', 'dim']],
      [['     ✗ ', 'err'], ['testStaleReadingIsDrawnBroken ', 'err'], ['(0.011s)', 'dim']],
      tool('Read', 'Sources/SessionCore/Limits.swift'),
      [['✻ ', 'busy'], ['Chasing the flaky one… ', 'busy'], ['(2m 08s)', 'dim']],
    ],
  },
  docs: {
    title: 'notch-orchestrator — claude',
    kind: 'finished',
    lines: [
      tool('Update', 'README.md'),
      result('Updated with 6 additions and 1 removal'),
      tool('Bash', 'git push'),
      result('main -> main'),
      [['⏺ ', 'ok'], 'The install section now says why curl is the way in.'],
      [['> ', 'dim'], ['▍', 'user']],
    ],
  },
  sandbox: {
    title: 'sandbox — claude',
    kind: 'working',
    lines: [
      [['> ', 'dim'], ['why is slow.sh slow', 'user']],
      tool('Bash', 'time ./slow.sh'),
      result('real 0m12.4s'),
      tool('Grep', '"sleep", glob: "*.sh"'),
      [['✻ ', 'busy'], ['Reading… ', 'busy'], ['(6s)', 'dim']],
    ],
  },
};
