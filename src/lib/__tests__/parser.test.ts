import { describe, expect, it } from 'vitest';
import { normalizeRecords, parseStatement } from '@/lib/parser';
import type { ParseResult } from '@/types/models';

describe('normalizeRecords', () => {
  it('should normalize source rows into transactions', () => {
    const parsed: ParseResult = {
      source: 'wechat',
      headers: ['交易时间', '交易对方', '金额(元)', '收/支'],
      rows: [{ rowIndex: 1, source: 'wechat', raw: { 交易时间: '2026-04-01 10:00:00', 交易对方: '星巴克', '金额(元)': '38.50', '收/支': '支出' } }]
    };

    const result = normalizeRecords(parsed, { occurredAt: '交易时间', merchant: '交易对方', amount: '金额(元)', direction: '收/支' });
    expect(result).toHaveLength(1);
    expect(result[0].merchant).toBe('星巴克');
    expect(result[0].direction).toBe('expense');
  });

  it('should handle numeric/date-like cell values without string methods crash', () => {
    const parsed: ParseResult = {
      source: 'bank_csv',
      headers: ['交易日期', '摘要', '金额'],
      rows: [
        {
          rowIndex: 1,
          source: 'bank_csv',
          raw: {
            交易日期: 1712448000000 as unknown as string,
            摘要: '测试商户',
            金额: 120.5 as unknown as string
          }
        }
      ]
    };

    const result = normalizeRecords(parsed, {
      occurredAt: '交易日期',
      merchant: '摘要',
      amount: '金额'
    });

    expect(result).toHaveLength(1);
    expect(result[0].amount).toBe(120.5);
    expect(result[0].merchant).toBe('测试商户');
  });

  it('should parse alipay csv with preface rows and header in middle', async () => {
    const csv = [
      '说明行,',
      '更多说明,',
      '交易时间,交易分类,交易对方,对方账号,商品说明,收/支,金额(元),收/付款方式,交易状态,交易订单号,商家订单号,备注',
      '2026-04-07 14:56:50,日用百货,某商户,a@b.com,商品A,支出,6.42,余额,交易成功,NO1,M1,',
      '2026-04-06 10:10:10,转账,张三,a@b.com,转账,收入,100.00,余额,交易成功,NO2,M2,'
    ].join('\n');

    const bytes = new TextEncoder().encode(csv);
    const file = {
      name: '支付宝交易明细(20260301-20260407).csv',
      arrayBuffer: async () => bytes.buffer
    } as unknown as File;
    const parsed = await parseStatement(file, {});
    const normalized = normalizeRecords(parsed);

    expect(parsed.source).toBe('alipay');
    expect(normalized).toHaveLength(2);
    expect(normalized[0].direction).toBe('expense');
    expect(normalized[1].direction).toBe('income');
  });
});
