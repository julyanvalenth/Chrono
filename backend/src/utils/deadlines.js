const norm = value => String(value ?? '').trim().toLowerCase();

export function sameTitle(a, b) {
  const left = norm(a);
  return left !== '' && left === norm(b);
}

export function plannedFromBlocks(deadline, blocks) {
  const key = norm(deadline.title);
  if (!key) return 0;
  let sum = 0;
  for (const block of blocks) {
    if (block.kind === 'lecture') continue;
    const title = norm(block.title);
    if (title === key) {
      sum += Math.max(0, (block.end_min ?? 0) - (block.start_min ?? 0));
    }
  }
  return sum;
}
