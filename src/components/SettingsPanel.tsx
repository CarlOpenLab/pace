import { useState } from 'react';
import type { AISettings } from '@/types/models';

interface Props {
  settings: AISettings;
  onSave: (value: AISettings) => Promise<void>;
}

export function SettingsPanel({ settings, onSave }: Props) {
  const [form, setForm] = useState<AISettings>(settings);
  const [msg, setMsg] = useState('');

  async function submit() {
    await onSave(form);
    setMsg('AI设置已保存。');
  }

  return (
    <section className="panel">
      <h2>AI辅助分类设置</h2>
      <div className="mapping-grid">
        <label>启用AI<select value={form.enabled ? '1' : '0'} onChange={(e) => setForm({ ...form, enabled: e.target.value === '1' })}><option value="0">关闭</option><option value="1">开启</option></select></label>
        <label>Endpoint<input value={form.endpoint} onChange={(e) => setForm({ ...form, endpoint: e.target.value })} /></label>
        <label>Model<input value={form.model} onChange={(e) => setForm({ ...form, model: e.target.value })} /></label>
        <label>API Key<input type="password" value={form.apiKey} onChange={(e) => setForm({ ...form, apiKey: e.target.value })} /></label>
        <label>低置信度阈值<input type="number" min={0} max={1} step={0.01} value={form.lowConfidenceThreshold} onChange={(e) => setForm({ ...form, lowConfidenceThreshold: Number(e.target.value) })} /></label>
      </div>
      <button onClick={() => void submit()}>保存设置</button>
      {msg ? <p className="message">{msg}</p> : null}
      <p className="hint">仅会发送 merchant/amount/time/remark，不会上传原始文件。</p>
    </section>
  );
}
