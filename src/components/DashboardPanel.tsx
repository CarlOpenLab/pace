import { useMemo } from 'react';
import type { EChartsOption } from 'echarts';
import { EChart } from './EChart';
import type { DashboardViewModel } from '@/types/models';

interface Props {
  model: DashboardViewModel;
}

export function DashboardPanel({ model }: Props) {
  const totalFlow = model.totals.income + model.totals.expense;
  const incomeRatio = totalFlow > 0 ? (model.totals.income / totalFlow) * 100 : 0;
  const expenseRatio = totalFlow > 0 ? (model.totals.expense / totalFlow) * 100 : 0;

  const pieOption = useMemo<EChartsOption>(() => ({
    tooltip: { trigger: 'item' },
    legend: { top: 'bottom' },
    series: [{ type: 'pie', radius: ['38%', '70%'], data: model.categoryShare.map((item) => ({ name: item.category, value: item.amount })) }]
  }), [model.categoryShare]);

  const trendOption = useMemo<EChartsOption>(() => ({
    tooltip: { trigger: 'axis' },
    legend: { data: ['收入', '支出', '结余'] },
    xAxis: { type: 'category', data: model.trend.map((item) => item.period) },
    yAxis: { type: 'value' },
    series: [
      { name: '收入', type: 'line', smooth: true, data: model.trend.map((item) => item.income) },
      { name: '支出', type: 'line', smooth: true, data: model.trend.map((item) => item.expense) },
      { name: '结余', type: 'bar', data: model.trend.map((item) => item.balance) }
    ]
  }), [model.trend]);

  return (
    <section className="panel">
      <h2>消费看板</h2>
      <div className="stats-grid">
        <article><span>总收入</span><strong>{model.totals.income.toFixed(2)}</strong></article>
        <article><span>总支出</span><strong>{model.totals.expense.toFixed(2)}</strong></article>
        <article><span>结余</span><strong>{model.totals.balance.toFixed(2)}</strong></article>
      </div>
      <p className="hint" style={{ marginTop: 8 }}>
        收入 {model.totals.income.toFixed(2)}（{incomeRatio.toFixed(2)}%），
        支出 {model.totals.expense.toFixed(2)}（{expenseRatio.toFixed(2)}%）
      </p>
      <div className="dashboard-grid">
        <div className="card"><h3>分类占比</h3><EChart option={pieOption} height={300} /></div>
        <div className="card"><h3>收支趋势</h3><EChart option={trendOption} height={300} /></div>
      </div>
      <div className="table-wrap">
        <table>
          <thead><tr><th>账户</th><th>收入</th><th>支出</th><th>结余</th></tr></thead>
          <tbody>
            {model.accounts.map((item) => (
              <tr key={item.account}><td>{item.account}</td><td>{item.income.toFixed(2)}</td><td>{item.expense.toFixed(2)}</td><td>{item.balance.toFixed(2)}</td></tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}
