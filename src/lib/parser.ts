import Papa from 'papaparse';
import * as XLSX from 'xlsx';
import type {
  FieldMapping,
  NormalizedTransaction,
  ParseResult,
  ParseStatementOptions,
  RawRecord,
  StatementSource,
  TransactionDirection
} from '@/types/models';

function detectSourceByHeaders(headers: string[]): StatementSource {
  const joined = headers.join('|');
  if (/(交易创建时间|交易对方|收支类型|金额\(元\)|交易分类)/.test(joined)) return 'alipay';
  if (/(交易时间|交易类型|交易对方|商品|收\/支)/.test(joined)) return 'wechat';
  if (/(交易日期|摘要|借方金额|贷方金额|账户|户名)/.test(joined)) return 'bank_csv';
  return 'unknown';
}

function detectSourceByFileName(fileName: string): StatementSource {
  const name = fileName.toLowerCase();
  if (name.includes('微信')) return 'wechat';
  if (name.includes('支付宝') || name.includes('alipay')) return 'alipay';
  if (name.includes('银行') || name.includes('bank')) return 'bank_csv';
  return 'unknown';
}

function normalizeHeader(value: string): string {
  return value.trim().replace(/\s+/g, '');
}

function asString(value: unknown): string {
  if (value === null || value === undefined) return '';
  if (typeof value === 'string') return value;
  if (typeof value === 'number' || typeof value === 'boolean') return String(value);
  if (value instanceof Date) return value.toISOString();
  return String(value);
}

function isLikelyTradeDateCell(value: unknown): boolean {
  const text = asString(value).trim();
  if (!text) return false;
  const normalized = text.replace(/[.年/]/g, '-').replace(/月/g, '-').replace(/日/g, '');
  const date = new Date(normalized);
  return !Number.isNaN(date.getTime()) && date.getFullYear() >= 2000 && date.getFullYear() <= 2100;
}

function normalizeHeaders(row: unknown[]): string[] {
  return row.map((cell, index) => {
    const text = asString(cell).trim();
    return text || `__col_${index}`;
  });
}

function guessFieldMapping(headers: string[], sourceHint: StatementSource = 'unknown'): FieldMapping {
  const source = sourceHint !== 'unknown' ? sourceHint : detectSourceByHeaders(headers);
  const defaultMap: FieldMapping = {
    occurredAt: headers[0] ?? '',
    amount: headers[1] ?? '',
    merchant: headers[2] ?? '',
    remark: headers[3],
    account: headers[4]
  };

  const find = (...names: string[]): string => headers.find((h) => names.some((n) => normalizeHeader(h).includes(n))) ?? '';

  if (source === 'wechat') {
    return {
      occurredAt: find('交易时间', '时间') || headers[0] || '',
      amount: find('金额') || headers[5] || '',
      merchant: find('交易对方', '商户', '商品') || headers[2] || '',
      direction: find('收/支', '收支') || headers[4] || '',
      remark: find('商品', '备注', '交易状态') || headers[3] || '',
      account: find('支付方式', '当前状态') || headers[6] || ''
    };
  }

  if (source === 'alipay') {
    return {
      occurredAt: find('交易创建时间', '付款时间', '交易时间') || headers[0] || '',
      amount: find('金额') || headers[6] || '',
      merchant: find('交易对方', '商品名称', '商品说明') || headers[2] || '',
      direction: find('收支类型', '收/支') || headers[5] || '',
      remark: find('备注', '交易分类', '商品说明') || headers[4] || '',
      account: find('收/付款方式', '资金状态') || headers[7] || ''
    };
  }

  const guessed: FieldMapping = {
    occurredAt: find('交易日期', '日期', '时间'),
    amount: find('金额', '借方金额', '贷方金额'),
    merchant: find('摘要', '对方户名', '商户', '交易对方'),
    direction: find('收支', '借贷标志', '借贷方向'),
    remark: find('备注', '附言', '用途'),
    account: find('账户', '卡号', '账号')
  };

  if (!guessed.occurredAt || !guessed.amount || !guessed.merchant) {
    return defaultMap;
  }

  return guessed;
}

async function readFileContent(file: File): Promise<string | ArrayBuffer> {
  const canArrayBuffer = typeof file.arrayBuffer === 'function';
  if (file.name.endsWith('.xlsx') || file.name.endsWith('.xls')) {
    if (canArrayBuffer) return await file.arrayBuffer();
    return await file.text();
  }

  if (!canArrayBuffer) return await file.text();
  const buffer = await file.arrayBuffer();
  const utf8Text = new TextDecoder('utf-8').decode(buffer);
  const replacementCount = (utf8Text.match(/�/g) ?? []).length;
  if (replacementCount >= 8) {
    try {
      return new TextDecoder('gb18030').decode(buffer);
    } catch {
      return utf8Text;
    }
  }
  return utf8Text;
}

function parseXlsxRows(sheet: XLSX.WorkSheet): { headers: string[]; rows: Record<string, unknown>[] } {
  const matrix = XLSX.utils.sheet_to_json<unknown[]>(sheet, { header: 1, defval: '' });
  const headerRowIndex = matrix.findIndex((row) => {
    const cells = row.map((cell) => asString(cell).trim());
    const hasTimeColumn = cells.some((cell) => /(交易时间|交易创建时间|交易日期|时间)/.test(cell));
    const hasAmountColumn = cells.some((cell) => /金额/.test(cell));
    return hasTimeColumn && hasAmountColumn;
  });

  if (headerRowIndex === -1) {
    const objectRows = XLSX.utils.sheet_to_json<Record<string, unknown>>(sheet, { defval: '' });
    return {
      headers: Object.keys(objectRows[0] ?? {}),
      rows: objectRows
    };
  }

  const headers = normalizeHeaders(matrix[headerRowIndex]);
  const rows: Record<string, unknown>[] = [];

  for (let i = headerRowIndex + 1; i < matrix.length; i += 1) {
    const row = matrix[i];
    if (!row) continue;
    const values = row.map((cell) => asString(cell).trim());
    if (values.every((cell) => cell === '')) continue;
    if (values[0]?.startsWith('----------------')) continue;

    const item: Record<string, unknown> = {};
    for (let j = 0; j < headers.length; j += 1) {
      item[headers[j]] = row[j] ?? '';
    }
    rows.push(item);
  }

  return { headers, rows };
}

function parseCsvRows(content: string): { headers: string[]; rows: Record<string, unknown>[] } {
  const lines = content
    .split(/\r?\n/)
    .map((line) => line.replace(/\uFEFF/g, ''))
    .filter((line) => line !== '');

  const table = lines.map((line) => {
    const parsed = Papa.parse<unknown[]>(line, { header: false, skipEmptyLines: false });
    const row = parsed.data[0];
    return Array.isArray(row) ? row : [];
  });

  const headerRowIndex = table.findIndex((row, index) => {
    if (row.length < 8 || index >= table.length - 1) return false;
    const nextRow = table[index + 1];
    const nonEmptyCount = row.filter((cell) => asString(cell).trim() !== '').length;
    if (nonEmptyCount < 5) return false;
    return isLikelyTradeDateCell(nextRow[0]);
  });

  const safeHeaderRowIndex = headerRowIndex >= 0 ? headerRowIndex : 0;
  const headers = normalizeHeaders(table[safeHeaderRowIndex] ?? []);
  const rows: Record<string, unknown>[] = [];

  for (let i = safeHeaderRowIndex + 1; i < table.length; i += 1) {
    const row = table[i];
    if (!row || row.length === 0) continue;
    const values = row.map((cell) => asString(cell).trim());
    if (values.every((cell) => cell === '')) continue;
    if (values[0]?.startsWith('----------------')) continue;
    if (!isLikelyTradeDateCell(row[0])) continue;

    const item: Record<string, unknown> = {};
    for (let j = 0; j < headers.length; j += 1) {
      item[headers[j]] = row[j] ?? '';
    }
    rows.push(item);
  }

  return { headers, rows };
}

export async function parseStatement(file: File, options: ParseStatementOptions = {}): Promise<ParseResult> {
  const content = await readFileContent(file);
  let headers: string[] = [];
  let rows: Record<string, unknown>[] = [];

  if (content instanceof ArrayBuffer) {
    const workbook = XLSX.read(content, { type: 'array' });
    const firstSheet = workbook.Sheets[workbook.SheetNames[0]];
    const parsed = parseXlsxRows(firstSheet);
    rows = parsed.rows;
    headers = parsed.headers;
  } else {
    const parsed = parseCsvRows(content);
    rows = parsed.rows;
    headers = parsed.headers;
  }

  const filenameSource = detectSourceByFileName(file.name);
  const sourceByHeader = detectSourceByHeaders(headers);
  const source = options.sourceHint && options.sourceHint !== 'unknown' ? options.sourceHint : sourceByHeader !== 'unknown' ? sourceByHeader : filenameSource;

  const mappedRows: RawRecord[] = rows.map((row, idx) => ({ rowIndex: idx + 1, source, raw: row }));
  return { headers, rows: mappedRows, source };
}

function toDirection(value: unknown, amount: number): TransactionDirection {
  const text = asString(value).toLowerCase();
  if (/支出|付款|消费|debit|借/.test(text)) return 'expense';
  if (/收入|收款|credit|贷/.test(text)) return 'income';
  return amount >= 0 ? 'income' : 'expense';
}

function toDateISO(input: unknown): string {
  if (input instanceof Date) return input.toISOString();
  if (typeof input === 'number') {
    const parts = XLSX.SSF.parse_date_code(input);
    if (parts) {
      const date = new Date(parts.y, parts.m - 1, parts.d, parts.H, parts.M, Math.floor(parts.S));
      if (!Number.isNaN(date.getTime())) return date.toISOString();
    }
  }
  const raw = asString(input);
  const normalized = raw.replace(/[.年\/]/g, '-').replace(/月/g, '-').replace(/日/g, '').trim();
  const date = new Date(normalized);
  if (Number.isNaN(date.getTime())) return new Date().toISOString();
  return date.toISOString();
}

function toAmount(value: unknown): number {
  if (typeof value === 'number') return value;
  const cleaned = asString(value).replace(/[￥,\s]/g, '');
  const parsed = Number.parseFloat(cleaned);
  if (Number.isNaN(parsed)) return 0;
  return parsed;
}

function fingerprintOf(tx: Omit<NormalizedTransaction, 'id' | 'createdAt' | 'updatedAt'>): string {
  return [tx.occurredAt.slice(0, 19), tx.amount.toFixed(2), tx.merchant.trim(), tx.account.trim(), tx.source].join('|').toLowerCase();
}

export function normalizeRecords(parseResult: ParseResult, mappingInput?: FieldMapping, defaultAccount = '默认账户'): NormalizedTransaction[] {
  const mapping = mappingInput ?? guessFieldMapping(parseResult.headers, parseResult.source);

  return parseResult.rows.map((entry) => {
    const now = new Date().toISOString();
    const amountRaw = entry.raw[mapping.amount] ?? '0';
    const amountParsed = toAmount(amountRaw);
    const directionRaw = mapping.direction ? entry.raw[mapping.direction] ?? '' : '';
    const direction = toDirection(directionRaw, amountParsed);

    const base: Omit<NormalizedTransaction, 'id' | 'createdAt' | 'updatedAt'> = {
      source: entry.source,
      fingerprint: '',
      occurredAt: toDateISO(entry.raw[mapping.occurredAt] ?? now),
      amount: Math.abs(amountParsed),
      direction,
      merchant: asString(entry.raw[mapping.merchant] ?? '未识别商户').trim() || '未识别商户',
      account: asString(mapping.account ? entry.raw[mapping.account] : '').trim() || defaultAccount,
      currency: 'CNY',
      remark: asString(mapping.remark ? entry.raw[mapping.remark] : '').trim(),
      category: '其他',
      confidence: 0,
      classificationSource: 'rule',
      classificationReason: '待分类'
    };

    const id = crypto.randomUUID();
    const fingerprint = fingerprintOf(base);

    return {
      ...base,
      id,
      fingerprint,
      createdAt: now,
      updatedAt: now
    };
  });
}

export function suggestFieldMapping(headers: string[], sourceHint: StatementSource = 'unknown'): FieldMapping {
  return guessFieldMapping(headers, sourceHint);
}
