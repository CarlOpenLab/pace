import { DEFAULT_CATEGORIES } from '@/lib/categories';
import type { NormalizedTransaction } from '@/types/models';

interface Props {
  items: NormalizedTransaction[];
  onChangeCategory: (tx: NormalizedTransaction, category: string) => Promise<void>;
}

export function TransactionsPanel({ items, onChangeCategory }: Props) {
  return (
    <section className="panel">
      <h2>交易明细</h2>
      <div className="table-wrap">
        <table>
          <thead>
            <tr><th>日期</th><th>商户</th><th>账户</th><th>收支</th><th>金额</th><th>分类</th><th>来源</th></tr>
          </thead>
          <tbody>
            {items.map((tx) => (
              <tr key={tx.id}>
                <td>{tx.occurredAt.slice(0, 10)}</td>
                <td>{tx.merchant}</td>
                <td>{tx.account}</td>
                <td>{tx.direction === 'income' ? '收入' : '支出'}</td>
                <td>{tx.amount.toFixed(2)}</td>
                <td>
                  <select value={tx.category} onChange={(e) => void onChangeCategory(tx, e.target.value)}>
                    {DEFAULT_CATEGORIES.map((category) => <option key={category} value={category}>{category}</option>)}
                  </select>
                </td>
                <td>{tx.classificationSource}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}
