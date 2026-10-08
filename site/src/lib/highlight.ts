/** A stretch of Swift source and what it is, for colouring. */
export type Token = [text: string, kind: 'comment' | 'string' | 'number' | 'keyword' | 'type' | 'call' | 'plain'];

const KEYWORDS = new Set([
  'private', 'func', 'let', 'var', 'case', 'switch', 'if', 'else', 'for', 'in', 'return', 'struct', 'enum', 'static',
  'inout', 'self', 'true', 'false', 'nil', 'init', 'guard', 'default',
]);

// Comments and strings first, so that nothing inside them is taken for code.
const PARTS = /(\/\/.*$)|("(?:[^"\\]|\\.)*")|(\b\d+(?:\.\d+)?\b)|(\.?[A-Za-z_]\w*)|(\s+|.)/gm;

/** Splits one line of Swift into tokens. Enough for a backdrop, not a parser. */
export function highlightSwift(line: string): Token[] {
  const tokens: Token[] = [];
  for (const match of line.matchAll(PARTS)) {
    const [text, comment, string, number, word] = match;
    if (comment) tokens.push([text, 'comment']);
    else if (string) tokens.push([text, 'string']);
    else if (number) tokens.push([text, 'number']);
    else if (word) {
      const name = word.replace(/^\./, '');
      const isCall = line[match.index! + text.length] === '(';
      tokens.push([text, KEYWORDS.has(name) ? 'keyword' : /^[A-Z]/.test(name) ? 'type' : isCall ? 'call' : 'plain']);
    } else tokens.push([text, 'plain']);
  }
  return tokens;
}
