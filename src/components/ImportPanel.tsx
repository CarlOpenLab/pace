import { useMemo, useState } from 'react';
import { classifyWithFallback, parseAndNormalize } from '@/lib/importPipeline';
import { suggestFieldMapping } from '@/lib/parser';
import type { AISettings, CategoryRule, FieldMapping, NormalizedTransaction, StatementSource } from '@/types/models';

interface Props {
  rules: CategoryRule[];
  aiSettings: AISettings;
  onImported: (transactions: NormalizedTransaction[]) => Promise<void>;
}

const SOURCES: StatementSource[] = ['unknown', 'wechat', 'alipay', 'bank_csv'];

export function ImportPanel({ rules, aiSettings, onImported }: Props) {
  const [file, setFile] = useState<File | null>(null);
  const [sourceHint, setSourceHint] = useState<StatementSource>('unknown');
  const [headers, setHeaders] = useState<string[]>([]);
  const [mapping, setMapping] = useState<FieldMapping | null>(null);
  const [preview, setPreview] = useState<NormalizedTransaction[]>([]);
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState('');
  const [summary, setSummary] = useState<{
    count: number;
    minDate: string;
    maxDate: string;
    income: number;
    expense: number;
  } | null>(null);

  const headerOptions = useMemo(() => headers.map((h) => <option key={h} value={h}>{h}</option>), [headers]);

  async function runPreview() {
    if (!file) return;
    setLoading(true);
    setMessage('');
    try {
      const result = await parseAndNormalize(file, {
        sourceHint,
        fieldMapping: sourceHint === 'bank_csv' ? mapping ?? undefined : undefined,
        defaultAccount: '默认账户'
      });
      setHeaders(result.headers);
      setMapping((prev) => prev ?? suggestFieldMapping(result.headers));
      setPreview(result.transactions);
      const sortedDates = result.transactions
        .map((item) => item.occurredAt)
        .sort((a, b) => new Date(a).getTime() - new Date(b).getTime());
      const income = result.transactions.filter((item) => item.direction === 'income').reduce((sum, item) => sum + item.amount, 0);
      const expense = result.transactions.filter((item) => item.direction === 'expense').reduce((sum, item) => sum + item.amount, 0);
      setSummary({
        count: result.transactions.length,
        minDate: sortedDates[0] ?? '',
        maxDate: sortedDates[sortedDates.length - 1] ?? '',
        income,
        expense
      });
      setMessage(`解析完成，共预览 ${result.transactions.length} 条。`);
    } catch (err) {
      setMessage(`解析失败: ${(err as Error).message}`);
    } finally {
      setLoading(false);
    }
  }

  async function runImport() {
    if (!file) return;
    setLoading(true);
    setMessage('');
    try {
      const parsed = await parseAndNormalize(file, {
        sourceHint,
        fieldMapping: sourceHint === 'bank_csv' ? mapping ?? undefined : undefined,
        defaultAccount: '默认账户'
      });
      const classified = await classifyWithFallback({
        transactions: parsed.transactions,
        rules,
        ai: aiSettings
      });
      await onImported(classified);
      setMessage(`导入完成，处理 ${classified.length} 条。`);
    } catch (err) {
      setMessage(`导入失败: ${(err as Error).message}`);
    } finally {
      setLoading(false);
    }
  }

  return (
    <section className="panel">
      <h2>导入流水</h2>
      <div className="row">
        <input type="file" accept=".csv,.xlsx,.xls" onChange={(e) => setFile(e.target.files?.[0] ?? null)} />
        <select value={sourceHint} onChange={(e) => setSourceHint(e.target.value as StatementSource)}>
          {SOURCES.map((source) => <option key={source} value={source}>{source}</option>)}
        </select>
        <button onClick={runPreview} disabled={!file || loading}>预览解析</button>
        <button onClick={runImport} disabled={!file || loading || rules.length === 0}>导入并分类</button>
      </div>

      {sourceHint === 'bank_csv' && mapping && headers.length > 0 ? (
        <div className="mapping-grid">
          <label>交易时间<select value={mapping.occurredAt} onChange={(e) => setMapping({ ...mapping, occurredAt: e.target.value })}>{headerOptions}</select></label>
          <label>金额<select value={mapping.amount} onChange={(e) => setMapping({ ...mapping, amount: e.target.value })}>{headerOptions}</select></label>
          <label>商户/摘要<select value={mapping.merchant} onChange={(e) => setMapping({ ...mapping, merchant: e.target.value })}>{headerOptions}</select></label>
          <label>收支方向<select value={mapping.direction ?? ''} onChange={(e) => setMapping({ ...mapping, direction: e.target.value })}><option value="">(自动推断)</option>{headerOptions}</select></label>
          <label>账户<select value={mapping.account ?? ''} onChange={(e) => setMapping({ ...mapping, account: e.target.value })}><option value="">(默认账户)</option>{headerOptions}</select></label>
          <label>备注<select value={mapping.remark ?? ''} onChange={(e) => setMapping({ ...mapping, remark: e.target.value })}><option value="">(空)</option>{headerOptions}</select></label>
        </div>
      ) : null}

      {message ? <p className="message">{message}</p> : null}
      {summary ? (
        <div className="stats-grid" style={{ marginTop: 10 }}>
          <article>
            <span>解析总条数</span>
            <strong>{summary.count}</strong>
          </article>
          <article>
            <span>日期范围</span>
            <strong style={{ fontSize: 14 }}>{summary.minDate.slice(0, 10)} ~ {summary.maxDate.slice(0, 10)}</strong>
          </article>
          <article>
            <span>收入/支出占比</span>
            <strong style={{ fontSize: 14 }}>
              {(() => {
                const total = summary.income + summary.expense;
                const incomePct = total > 0 ? (summary.income / total) * 100 : 0;
                const expensePct = total > 0 ? (summary.expense / total) * 100 : 0;
                return `收入 ${summary.income.toFixed(2)} (${incomePct.toFixed(2)}%) / 支出 ${summary.expense.toFixed(2)} (${expensePct.toFixed(2)}%)`;
              })()}
            </strong>
          </article>
        </div>
      ) : null}

      {preview.length > 0 ? (
        <div className="table-wrap">
          <table>
            <thead><tr><th>时间</th><th>商户</th><th>金额</th><th>方向</th><th>账户</th></tr></thead>
            <tbody>
              {preview.map((row) => (
                <tr key={row.id}>
                  <td>{row.occurredAt.slice(0, 10)}</td><td>{row.merchant}</td><td>{row.amount.toFixed(2)}</td><td>{row.direction}</td><td>{row.account}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : null}
    </section>
  );
}
