import { describe, expect, it } from 'vitest';
import { classifyTransaction } from '@/lib/classifier';
import type { CategoryRule, NormalizedTransaction } from '@/types/models';

function mockTransaction(partial: Partial<NormalizedTransaction>): NormalizedTransaction {
  return {
    id: '1', fingerprint: 'fp', source: 'wechat', occurredAt: new Date().toISOString(), amount: 20,
    direction: 'expense', merchant: '美团外卖', account: '招商银行卡', currency: 'CNY', remark: '',
    category: '其他', confidence: 0, classificationSource: 'rule', classificationReason: '',
    createdAt: new Date().toISOString(), updatedAt: new Date().toISOString(), ...partial
  };
}

describe('classifyTransaction', () => {
  it('should match high priority rule first', () => {
    const rules: CategoryRule[] = [
      { name: '低优先级', enabled: true, priority: 10, targetCategory: '购物', merchantKeywords: ['美团'], createdAt: '', updatedAt: '' },
      { name: '高优先级', enabled: true, priority: 120, targetCategory: '餐饮', merchantKeywords: ['美团'], createdAt: '', updatedAt: '' }
    ];
    const result = classifyTransaction(mockTransaction({}), rules);
    expect(result.category).toBe('餐饮');
  });
});
