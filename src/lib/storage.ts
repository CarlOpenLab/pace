import Dexie, { type Table } from 'dexie';
import type { AISettings, CategoryRule, NormalizedTransaction } from '@/types/models';

interface AppSetting {
  key: string;
  value: unknown;
}

class LedgerMindDB extends Dexie {
  transactions!: Table<NormalizedTransaction, string>;
  rules!: Table<CategoryRule, number>;
  settings!: Table<AppSetting, string>;

  constructor() {
    super('LedgerMindDB');
    this.version(1).stores({
      transactions: '&id,fingerprint,occurredAt,direction,category,account,merchant,source',
      rules: '++id,priority,targetCategory,enabled',
      settings: '&key'
    });
  }
}

export const db = new LedgerMindDB();

export async function getAISettings(): Promise<AISettings> {
  const record = await db.settings.get('ai-settings');
  if (!record) {
    return {
      enabled: false,
      endpoint: 'https://api.openai.com/v1/chat/completions',
      model: 'gpt-5-mini',
      apiKey: '',
      lowConfidenceThreshold: 0.68
    };
  }
  return record.value as AISettings;
}

export async function saveAISettings(value: AISettings): Promise<void> {
  await db.settings.put({ key: 'ai-settings', value });
}
