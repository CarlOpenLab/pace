export type StatementSource = 'wechat' | 'alipay' | 'bank_csv' | 'unknown';

export type TransactionDirection = 'expense' | 'income';

export type ClassificationSource = 'rule' | 'ai' | 'manual';

export interface RawRecord {
  rowIndex: number;
  source: StatementSource;
  raw: Record<string, unknown>;
}

export interface NormalizedTransaction {
  id: string;
  fingerprint: string;
  source: StatementSource;
  occurredAt: string;
  amount: number;
  direction: TransactionDirection;
  merchant: string;
  account: string;
  currency: string;
  remark: string;
  category: string;
  confidence: number;
  classificationSource: ClassificationSource;
  classificationReason: string;
  createdAt: string;
  updatedAt: string;
}

export interface CategoryRule {
  id?: number;
  name: string;
  enabled: boolean;
  priority: number;
  targetCategory: string;
  merchantKeywords?: string[];
  remarkKeywords?: string[];
  accountIncludes?: string[];
  direction?: TransactionDirection;
  minAmount?: number;
  maxAmount?: number;
  createdAt: string;
  updatedAt: string;
}

export interface ClassificationResult {
  category: string;
  confidence: number;
  reason: string;
  source: ClassificationSource;
}

export interface DashboardFilters {
  from?: string;
  to?: string;
  account?: string;
}

export interface CategoryShareItem {
  category: string;
  amount: number;
  ratio: number;
}

export interface TrendPoint {
  period: string;
  income: number;
  expense: number;
  balance: number;
}

export interface AccountSummary {
  account: string;
  income: number;
  expense: number;
  balance: number;
}

export interface DashboardViewModel {
  categoryShare: CategoryShareItem[];
  trend: TrendPoint[];
  accounts: AccountSummary[];
  totals: {
    income: number;
    expense: number;
    balance: number;
  };
}

export interface FieldMapping {
  occurredAt: string;
  amount: string;
  merchant: string;
  direction?: string;
  account?: string;
  remark?: string;
}

export interface ParseResult {
  rows: RawRecord[];
  headers: string[];
  source: StatementSource;
}

export interface ParseStatementOptions {
  sourceHint?: StatementSource;
  fieldMapping?: FieldMapping;
  defaultAccount?: string;
}

export interface AISettings {
  enabled: boolean;
  endpoint: string;
  model: string;
  apiKey: string;
  lowConfidenceThreshold: number;
}
