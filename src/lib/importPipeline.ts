import { classifyByAI } from './ai';
import { classifyTransaction, classifyTransactions } from './classifier';
import { normalizeRecords, parseStatement } from './parser';
import type { AISettings, CategoryRule, NormalizedTransaction, ParseStatementOptions } from '@/types/models';

export async function parseAndNormalize(file: File, options: ParseStatementOptions): Promise<{
  headers: string[];
  source: string;
  transactions: NormalizedTransaction[];
}> {
  const parsed = await parseStatement(file, options);
  const normalized = normalizeRecords(parsed, options.fieldMapping, options.defaultAccount);
  return { headers: parsed.headers, source: parsed.source, transactions: normalized };
}

export async function classifyWithFallback(input: {
  transactions: NormalizedTransaction[];
  rules: CategoryRule[];
  ai: AISettings;
}): Promise<NormalizedTransaction[]> {
  const ruleResult = classifyTransactions(input.transactions, input.rules);

  return Promise.all(
    ruleResult.map(async (tx) => {
      if (!input.ai.enabled || tx.confidence >= input.ai.lowConfidenceThreshold) return tx;
      try {
        const aiResult = await classifyByAI(tx, input.ai);
        if (!aiResult) return tx;
        return {
          ...tx,
          category: aiResult.category,
          confidence: aiResult.confidence,
          classificationSource: aiResult.source,
          classificationReason: aiResult.reason,
          updatedAt: new Date().toISOString()
        };
      } catch {
        return tx;
      }
    })
  );
}

export function reclassifyOne(tx: NormalizedTransaction, rules: CategoryRule[]): NormalizedTransaction {
  const result = classifyTransaction(tx, rules);
  return {
    ...tx,
    category: result.category,
    confidence: result.confidence,
    classificationSource: result.source,
    classificationReason: result.reason,
    updatedAt: new Date().toISOString()
  };
}
