# Temporary exact binomial check for the N/R red line.
# Read-only; no names or GUIDs.
import math


def binom_cdf(k, n, p):
    return sum(math.comb(n, i) * p ** i * (1 - p) ** (n - i) for i in range(0, k + 1))


def cp_lower(k, n, alpha=0.05):
    """One-sided Clopper-Pearson lower bound: solve P(X >= k | p) = alpha."""
    lo, hi = 0.0, 1.0
    for _ in range(200):
        mid = (lo + hi) / 2.0
        tail = 1.0 - binom_cdf(k - 1, n, mid)
        if tail > alpha:
            hi = mid
        else:
            lo = mid
    return lo


for line in (0.50, 0.60, 0.70):
    print("line %.0f%%" % (100 * line))
    for n in (20, 30, 50, 100):
        k = int(round(line * n))
        print("  R=%3d  k=%3d  CP95 lower=%5.1f%%  tail at true=50%%: %.3f%%" % (
            n, k, 100 * cp_lower(k, n), 100 * (1 - binom_cdf(k - 1, n, 0.5))))
    print("")

# Smallest R at which a 60% observed line has CP lower >= 50%.
for line in (0.50, 0.60, 0.70):
    found = None
    for n in range(10, 400):
        k = int(round(line * n))
        if abs(k / n - line) < 1e-9 and cp_lower(k, n) >= 0.50:
            found = n
            break
    print("smallest R with CP95 lower >= 50%% at %.0f%%: %s" % (100 * line, found))
