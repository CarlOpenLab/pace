import type { CategoryRule, ClassificationResult, NormalizedTransaction } from '@/types/models';
import { UNCATEGORIZED } from './categories';

function includesAny(text: string, keywords?: string[]): boolean {
  if (!keywords || keywords.length === 0) return true;
  return keywords.some((keyword) => text.includes(keyword.toLowerCase()));
}

function ruleMatch(tx: NormalizedTransaction, rule: CategoryRule): boolean {
  if (!rule.enabled) return false;
  if (rule.direction && rule.direction !== tx.direction) return false;
  if (rule.minAmount !== undefined && tx.amount < rule.minAmount) return false;
  if (rule.maxAmount !== undefined && tx.amount > rule.maxAmount) return false;

  const merchant = tx.merchant.toLowerCase();
  const remark = tx.remark.toLowerCase();
  const account = tx.account.toLowerCase();

  if (!includesAny(merchant, rule.merchantKeywords)) return false;
  if (!includesAny(remark, rule.remarkKeywords)) return false;
  if (!includesAny(account, rule.accountIncludes)) return false;

  return true;
}

export function classifyTransaction(tx: NormalizedTransaction, rules: CategoryRule[]): ClassificationResult {
  const sorted = [...rules].sort((a, b) => b.priority - a.priority);
  const matched = sorted.find((rule) => ruleMatch(tx, rule));

  if (!matched) {
    return {
      category: UNCATEGORIZED,
      confidence: 0.4,
      reason: 'no_rule_matched',
      source: 'rule'
    };
  }

  const confidence = Math.min(0.95, 0.65 + matched.priority / 500);
  return {
    category: matched.targetCategory,
    confidence,
    reason: `matched:${matched.name}`,
    source: 'rule'
  };
}

export function classifyTransactions(transactions: NormalizedTransaction[], rules: CategoryRule[]): NormalizedTransaction[] {
  return transactions.map((tx) => {
    const result = classifyTransaction(tx, rules);
    return {
      ...tx,
      category: result.category,
      confidence: result.confidence,
      classificationSource: result.source,
      classificationReason: result.reason,
      updatedAt: new Date().toISOString()
    };
  });
}

export function createLearningRule(input: {
  merchant: string;
  category: string;
  direction: NormalizedTransaction['direction'];
}): CategoryRule {
  const now = new Date().toISOString();
  return {
    name: `学习规则:${input.merchant.slice(0, 16)}`,
    enabled: true,
    priority: 140,
    targetCategory: input.category,
    merchantKeywords: [input.merchant],
    direction: input.direction,
    createdAt: now,
    updatedAt: now
  };
}
