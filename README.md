# LedgerMind 2.0

Offline-first personal finance app for parsing WeChat / Alipay / bank CSV statements, local intelligent categorization, and spending analytics dashboard.

## Tech Stack

- React 18 + TypeScript + Vite
- PWA (`vite-plugin-pwa`)
- IndexedDB (`Dexie`)
- CSV/XLSX parser (`papaparse` + `xlsx`)
- Dashboard (`echarts`)

## Core Features

- Statement import: `.csv`, `.xlsx`, `.xls`
- Source support: WeChat, Alipay, generic bank CSV mapping
- Local normalization + deduplication
- Rule-based categorization with priority
- Optional AI fallback for low-confidence transactions
- Manual category correction with learning-rule feedback
- Dashboard: category share, trend, account summary

## Development

```bash
npm install
npm run dev
```

## Tests

```bash
npm run test
```

## Build

```bash
npm run build
```
