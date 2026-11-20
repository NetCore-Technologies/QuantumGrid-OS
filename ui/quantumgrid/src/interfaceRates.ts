export function calculateCounterRateMbps(
  currentBytes: number | undefined,
  previousBytes: number | undefined,
  elapsedSeconds: number,
): number | null {
  if (
    currentBytes === undefined ||
    previousBytes === undefined ||
    !Number.isFinite(currentBytes) ||
    !Number.isFinite(previousBytes) ||
    currentBytes < 0 ||
    previousBytes < 0 ||
    currentBytes < previousBytes ||
    !Number.isFinite(elapsedSeconds) ||
    elapsedSeconds <= 0 ||
    elapsedSeconds > 60
  ) {
    return null;
  }

  const rate = ((currentBytes - previousBytes) * 8) / elapsedSeconds / 1_000_000;
  return Number.isFinite(rate) ? rate : null;
}
