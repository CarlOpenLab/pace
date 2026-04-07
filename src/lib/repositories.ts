import { db } from './storage';
import type { CategoryRule, NormalizedTransaction } from '@/types/models';

export async function ensureRuleSeeds(defaultRules: CategoryRule[]): Promise<void> {
  const count = await db.rules.count();
  if (count === 0) await db.rules.bulkAdd(defaultRules);
}

export async function getRules(): Promise<CategoryRule[]> {
  return db.rules.toArray();
}

export async function addRule(rule: CategoryRule): Promise<number> {
  return db.rules.add(rule);
}

export async function saveTransactions(transactions: NormalizedTransaction[]): Promise<{ inserted: number; skipped: number }> {
  const existing = new Set(await db.transactions.orderBy('fingerprint').keys());
  const toInsert = transactions.filter((tx) => !existing.has(tx.fingerprint));
  if (toInsert.length > 0) await db.transactions.bulkPut(toInsert);
  return { inserted: toInsert.length, skipped: transactions.length - toInsert.length };
}

export async function listTransactions(limit = 2000): Promise<NormalizedTransaction[]> {
  return db.transactions.orderBy('occurredAt').reverse().limit(limit).toArray();
}

export async function updateTransactionCategory(input: {
  id: string;
  category: string;
  source?: NormalizedTransaction['classificationSource'];
  reason?: string;
}): Promise<void> {
  await db.transactions.update(input.id, {
    category: input.category,
    classificationSource: input.source ?? 'manual',
    classificationReason: input.reason ?? 'manual_adjustment',
    confidence: 1,
    updatedAt: new Date().toISOString()
  });
}
