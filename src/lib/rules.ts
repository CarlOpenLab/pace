import type { CategoryRule } from '@/types/models';

const now = () => new Date().toISOString();

export const DEFAULT_RULES: CategoryRule[] = [
  {
    name: '餐饮关键词',
    enabled: true,
    priority: 100,
    targetCategory: '餐饮',
    merchantKeywords: ['美团', '饿了么', '肯德基', '麦当劳', '星巴克', '餐饮'],
    createdAt: now(),
    updatedAt: now()
  },
  {
    name: '交通关键词',
    enabled: true,
    priority: 90,
    targetCategory: '交通',
    merchantKeywords: ['滴滴', '地铁', '公交', '火车', '机票', '加油'],
    createdAt: now(),
    updatedAt: now()
  },
  {
    name: '工资收入',
    enabled: true,
    priority: 120,
    targetCategory: '工资',
    remarkKeywords: ['工资', '薪资', '奖金'],
    direction: 'income',
    createdAt: now(),
    updatedAt: now()
  },
  {
    name: '转账类',
    enabled: true,
    priority: 70,
    targetCategory: '转账',
    merchantKeywords: ['转账', '还款', '信用卡'],
    createdAt: now(),
    updatedAt: now()
  }
];
