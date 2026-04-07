import { useEffect, useMemo, useState } from 'react';
import { ImportPanel } from '@/components/ImportPanel';
import { TransactionsPanel } from '@/components/TransactionsPanel';
import { DashboardPanel } from '@/components/DashboardPanel';
import { SettingsPanel } from '@/components/SettingsPanel';
import { buildDashboard } from '@/lib/dashboard';
import { createLearningRule } from '@/lib/classifier';
import { DEFAULT_RULES } from '@/lib/rules';
import { addRule, ensureRuleSeeds, getRules, listTransactions, saveTransactions, updateTransactionCategory } from '@/lib/repositories';
import { getAISettings, saveAISettings } from '@/lib/storage';
import type { AISettings, CategoryRule, NormalizedTransaction } from '@/types/models';

const TABS = ['导入', '明细', '看板', '设置'] as const;
type Tab = (typeof TABS)[number];

export function App() {
  const [tab, setTab] = useState<Tab>('导入');
  const [transactions, setTransactions] = useState<NormalizedTransaction[]>([]);
  const [rules, setRules] = useState<CategoryRule[]>([]);
  const [aiSettings, setAISettings] = useState<AISettings>({
    enabled: false,
    endpoint: 'https://api.openai.com/v1/chat/completions',
    model: 'gpt-5-mini',
    apiKey: '',
    lowConfidenceThreshold: 0.68
  });
  const [banner, setBanner] = useState('');

  async function reloadAll() {
    const [ruleList, txList, ai] = await Promise.all([getRules(), listTransactions(), getAISettings()]);
    setRules(ruleList.sort((a, b) => b.priority - a.priority));
    setTransactions(txList);
    setAISettings(ai);
  }

  useEffect(() => {
    void (async () => {
      await ensureRuleSeeds(DEFAULT_RULES);
      await reloadAll();
    })();
  }, []);

  const dashboard = useMemo(() => buildDashboard(transactions), [transactions]);

  async function handleImported(rows: NormalizedTransaction[]) {
    const result = await saveTransactions(rows);
    await reloadAll();
    setBanner(`导入完成：新增 ${result.inserted} 条，跳过重复 ${result.skipped} 条。`);
  }

  async function handleChangeCategory(tx: NormalizedTransaction, category: string) {
    await updateTransactionCategory({ id: tx.id, category, source: 'manual', reason: 'manual_adjustment' });
    if (tx.merchant && tx.merchant !== '未识别商户') {
      await addRule(createLearningRule({ merchant: tx.merchant, category, direction: tx.direction }));
    }
    await reloadAll();
    setBanner(`已调整分类并写入学习规则：${tx.merchant} -> ${category}`);
  }

  async function handleSaveSettings(value: AISettings) {
    await saveAISettings(value);
    setAISettings(value);
    setBanner('AI设置已更新。');
  }

  return (
    <div className="app-shell">
      <header className="topbar">
        <div><h1>LedgerMind 2.0</h1><p>微信 / 支付宝 / 银行CSV 离线解析与消费看板</p></div>
        <nav>{TABS.map((item) => <button key={item} className={tab === item ? 'active' : ''} onClick={() => setTab(item)}>{item}</button>)}</nav>
      </header>

      {banner ? <div className="banner">{banner}</div> : null}

      <main>
        {tab === '导入' ? <ImportPanel rules={rules} aiSettings={aiSettings} onImported={handleImported} /> : null}
        {tab === '明细' ? <TransactionsPanel items={transactions} onChangeCategory={handleChangeCategory} /> : null}
        {tab === '看板' ? <DashboardPanel model={dashboard} /> : null}
        {tab === '设置' ? <SettingsPanel settings={aiSettings} onSave={handleSaveSettings} /> : null}
      </main>
    </div>
  );
}
