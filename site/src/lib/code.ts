/** Lines of make-believe code: each a few tokens, given as widths in percent of the line. */
export function codeLines(seed: number, count: number): { indent: number; tokens: number[] }[] {
  // A small generator with a seed, so that the page is the same on every build.
  let state = seed;
  const next = () => {
    state = (state * 1664525 + 1013904223) % 4294967296;
    return state / 4294967296;
  };
  return Array.from({ length: count }, () => {
    const indent = Math.floor(next() * 4) * 6;
    const tokens = Array.from({ length: 1 + Math.floor(next() * 4) }, () => 6 + Math.floor(next() * 20));
    return { indent, tokens };
  });
}
