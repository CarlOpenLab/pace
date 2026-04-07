import type { AISettings, ClassificationResult, NormalizedTransaction } from '@/types/models';

interface OpenAIChoice {
  message?: {
    content?: string;
  };
}

interface OpenAIResponse {
  choices?: OpenAIChoice[];
}

export async function classifyByAI(transaction: NormalizedTransaction, settings: AISettings): Promise<ClassificationResult | null> {
  if (!settings.enabled || !settings.apiKey || !settings.endpoint) return null;

  const prompt = {
    merchant: transaction.merchant,
    amount: transaction.amount,
    direction: transaction.direction,
    occurredAt: transaction.occurredAt,
    remark: transaction.remark
  };

  const response = await fetch(settings.endpoint, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${settings.apiKey}`
    },
    body: JSON.stringify({
      model: settings.model,
      messages: [
        {
          role: 'system',
          content: '你是记账分类助手。只返回JSON，格式为{"category":"分类","confidence":0-1,"reason":"简短原因"}，不要带markdown。'
        },
        {
          role: 'user',
          content: JSON.stringify(prompt)
        }
      ],
      temperature: 0.1
    })
  });

  if (!response.ok) return null;

  const data = (await response.json()) as OpenAIResponse;
  const content = data.choices?.[0]?.message?.content;
  if (!content) return null;

  try {
    const parsed = JSON.parse(content) as { category?: string; confidence?: number; reason?: string };
    if (!parsed.category) return null;

    return {
      category: parsed.category,
      confidence: Math.max(0, Math.min(1, parsed.confidence ?? 0.6)),
      reason: parsed.reason ?? 'ai_inferred',
      source: 'ai'
    };
  } catch {
    return null;
  }
}
