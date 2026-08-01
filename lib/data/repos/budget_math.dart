/// Pure pace/forecast math for budget surfaces. Color encodes the future:
/// on-pace (jama) / projected-over (warn) / already-over (seal) — plus
/// `pending` for an expected bill that hasn't landed (the outlined bar).
enum BudgetStatus { onPace, projectedOver, over, pending }

class BudgetPace {
  const BudgetPace({
    required this.spentPaise,
    required this.limitPaise,
    required this.elapsedDays,
    required this.totalDays,
    this.upcomingPaise = 0,
  });

  final int spentPaise;
  final int limitPaise;
  final int elapsedDays;
  final int totalDays;

  /// Committed-but-unposted recurring charges inside this period.
  final int upcomingPaise;

  int get remainingPaise => limitPaise - spentPaise;

  double get fractionSpent =>
      limitPaise <= 0 ? 1 : spentPaise / limitPaise;

  double get fractionElapsed =>
      totalDays <= 0 ? 1 : (elapsedDays / totalDays).clamp(0, 1);

  /// Straight-line projection of where the period ends at today's run rate,
  /// with committed upcoming charges counted in full.
  int get projectedPaise {
    if (elapsedDays <= 0) return spentPaise + upcomingPaise;
    final runRate = spentPaise / elapsedDays;
    return (runRate * totalDays).round() + upcomingPaise;
  }

  BudgetStatus get status {
    if (spentPaise > limitPaise) return BudgetStatus.over;
    if (spentPaise == 0 && upcomingPaise > 0) return BudgetStatus.pending;
    if (projectedPaise > limitPaise) return BudgetStatus.projectedOver;
    return BudgetStatus.onPace;
  }

  /// How far past the line the projection runs (0 when on pace).
  int get projectedOverspendPaise =>
      (projectedPaise - limitPaise).clamp(0, 1 << 62);
}
