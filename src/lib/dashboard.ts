import type { DashboardFilters, DashboardViewModel, NormalizedTransaction } from '@/types/models';

function inRange(tx: NormalizedTransaction, filters: DashboardFilters): boolean {
  if (filters.account && tx.account !== filters.account) return false;
  const time = new Date(tx.occurredAt).getTime();
  if (filters.from && time < new Date(filters.from).getTime()) return false;
  if (filters.to && time > new Date(filters.to).getTime()) return false;
  return true;
}

function monthKey(iso: string): string {
  return iso.slice(0, 7);
}

export function buildDashboard(transactions: NormalizedTransaction[], filters: DashboardFilters = {}): DashboardViewModel {
  const list = transactions.filter((tx) => inRange(tx, filters));

  const income = list.filter((tx) => tx.direction === 'income').reduce((sum, tx) => sum + tx.amount, 0);
  const expense = list.filter((tx) => tx.direction === 'expense').reduce((sum, tx) => sum + tx.amount, 0);

  const byCategory = new Map<string, number>();
  for (const tx of list) {
    if (tx.direction !== 'expense') continue;
    byCategory.set(tx.category, (byCategory.get(tx.category) ?? 0) + tx.amount);
  }

  const totalExpense = Array.from(byCategory.values()).reduce((sum, value) => sum + value, 0);
  const categoryShare = Array.from(byCategory.entries())
    .map(([category, amount]) => ({ category, amount, ratio: totalExpense > 0 ? amount / totalExpense : 0 }))
    .sort((a, b) => b.amount - a.amount);

  const byMonth = new Map<string, { income: number; expense: number }>();
  for (const tx of list) {
    const key = monthKey(tx.occurredAt);
    const current = byMonth.get(key) ?? { income: 0, expense: 0 };
    if (tx.direction === 'income') current.income += tx.amount;
    if (tx.direction === 'expense') current.expense += tx.amount;
    byMonth.set(key, current);
  }

  const trend = Array.from(byMonth.entries())
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([period, val]) => ({
      period,
      income: Number(val.income.toFixed(2)),
      expense: Number(val.expense.toFixed(2)),
      balance: Number((val.income - val.expense).toFixed(2))
    }));

  const byAccount = new Map<string, { income: number; expense: number }>();
  for (const tx of list) {
    const bucket = byAccount.get(tx.account) ?? { income: 0, expense: 0 };
    if (tx.direction === 'income') bucket.income += tx.amount;
    if (tx.direction === 'expense') bucket.expense += tx.amount;
    byAccount.set(tx.account, bucket);
  }

  const accounts = Array.from(byAccount.entries()).map(([account, bucket]) => ({
    account,
    income: Number(bucket.income.toFixed(2)),
    expense: Number(bucket.expense.toFixed(2)),
    balance: Number((bucket.income - bucket.expense).toFixed(2))
  }));

  return {
    categoryShare,
    trend,
    accounts,
    totals: {
      income: Number(income.toFixed(2)),
      expense: Number(expense.toFixed(2)),
      balance: Number((income - expense).toFixed(2))
    }
  };
}
