import { describe, expect, it } from 'vitest';
import { buildDashboard } from '@/lib/dashboard';
import type { NormalizedTransaction } from '@/types/models';

const tx = (partial: Partial<NormalizedTransaction>): NormalizedTransaction => ({
  id: crypto.randomUUID(), fingerprint: crypto.randomUUID(), source: 'wechat', occurredAt: '2026-04-01T00:00:00.000Z', amount: 100,
  direction: 'expense', merchant: '测试商户', account: '默认账户', currency: 'CNY', remark: '', category: '餐饮', confidence: 1,
  classificationSource: 'manual', classificationReason: 'manual', createdAt: new Date().toISOString(), updatedAt: new Date().toISOString(), ...partial
});

describe('buildDashboard', () => {
  it('should aggregate totals and category share', () => {
    const model = buildDashboard([
      tx({ amount: 100, direction: 'expense', category: '餐饮', account: 'A' }),
      tx({ amount: 400, direction: 'income', category: '工资', account: 'A' }),
      tx({ amount: 50, direction: 'expense', category: '交通', account: 'B' })
    ]);

    expect(model.totals.income).toBe(400);
    expect(model.totals.expense).toBe(150);
    expect(model.accounts).toHaveLength(2);
  });
});
