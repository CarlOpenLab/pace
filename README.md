# Pace

**Know what you can spend today.**

![License](https://img.shields.io/badge/license-MIT-blue)
![Version](https://img.shields.io/badge/version-0.1.3-blue)
![Android CI](https://github.com/CarlOpenLab/pace/actions/workflows/android.yml/badge.svg)
![iOS CI](https://github.com/CarlOpenLab/pace/actions/workflows/ios.yml/badge.svg)

English · [中文](README.zh-CN.md)

Pace is a daily-budget expense tracker with a native Android client and a native iOS client. One number tells you what today still allows. The ledger is stored only on your device; AI is an optional assistant and is off by default.

Product landing page: <https://carlopenlab.github.io/pace/>

- **Daily budget, honestly computed.** Today's remaining = budget − the net spend you chose to count today. No rollover unless you opt in; editing a budget never rewrites history; the budget engine needs no network and no AI.
- **Logging that takes seconds.** A floating *Add* button, optional one-sentence AI drafts that you always confirm before anything is written, refunds linked to the bill they reverse, transfers and card repayments kept out of spend.
- **Local-first and private.** No account, no cloud ledger, no analytics. Full-fidelity, versioned JSON export at any time. See [docs/AI_PRIVACY.md](docs/AI_PRIVACY.md).
- **One shared core.** Both clients share the budget engine, money rules, date attribution, import/export, and duplicate detection from a single Kotlin Multiplatform module, so the two platforms never disagree. Its fixed acceptance suite (60 tests) lives in `shared/src/commonTest` and [docs/EDGE_CASES.md](docs/EDGE_CASES.md).

Product and technical planning: [PLAN.md](PLAN.md). Cross-platform contracts: [docs/](docs/).

> Pace is in active development (v0.1.3). There is no store listing yet — installable builds come straight from CI.

## Repository structure

```text
├── shared/          # Kotlin Multiplatform shared core (budget / money / stats / import-export / dedupe)
├── androidApp/      # Kotlin + Jetpack Compose native Android client
├── iosApp/          # Swift + SwiftUI native iOS client (XcodeGen project)
├── docs/            # Cross-platform contracts: budget rules / data model / export format / AI privacy / edge cases
├── src/ etc.        # Existing web/PWA prototype (React + Vite), reference only during migration
└── PLAN.md          # Product & technical plan
```

## Install builds (CI)

Every push builds installable artifacts on the repo's [Actions](https://github.com/CarlOpenLab/pace/actions) page (open a run, download from Artifacts):

| Workflow | Artifact | Install with |
| --- | --- | --- |
| `android` | `pace-android-debug-apk` (debug APK) | Download and install directly on an Android device |
| `ios` | `pace-ios-unsigned-ipa` (unsigned IPA) | Self-sign with AltStore / Sideloadly, then install |
| `ios` | `pace-ios-simulator-app` | Unzip and drag into the iOS Simulator |
| `web` | — | Web prototype type-check / test / build |

## Native development

Android (JDK 17 + Android SDK 34):

```bash
./gradlew :androidApp:assembleDebug
```

iOS (macOS + Xcode 15+, see [iosApp/README.md](iosApp/README.md)):

```bash
./gradlew :shared:assembleXCFramework
cd iosApp && xcodegen generate && open iosApp.xcodeproj
```

Shared core tests (JVM is enough):

```bash
./gradlew :shared:testDebugUnitTest
```

## Web prototype (reference implementation)

An offline-first import / categorization / stats prototype whose business rules have been extracted into `shared`:

```bash
npm install
npm run dev      # develop
npm test         # test
npm run build    # build
```

## Documentation

- [PLAN.md](PLAN.md) — product positioning, roadmap, platform and collaboration decisions
- [docs/BUDGET_RULES.md](docs/BUDGET_RULES.md) — the exact budget arithmetic
- [docs/DATA_MODEL.md](docs/DATA_MODEL.md) — fields, enums, and money/date rules
- [docs/EXPORT_FORMAT.md](docs/EXPORT_FORMAT.md) — versioned JSON export format
- [docs/AI_PRIVACY.md](docs/AI_PRIVACY.md) — what AI may and may not do
- [docs/DESIGN.md](docs/DESIGN.md) — visual & interaction specification

## License

[MIT](LICENSE)
