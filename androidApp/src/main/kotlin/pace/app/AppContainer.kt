package pace.app

import android.app.Application
import pace.shared.AndroidDriverFactory
import pace.shared.LedgerApi
import pace.shared.datetime.PaceDates

/** 全局共享的账本入口；账本只存在于本地 SQLite。 */
object AppContainer {
    lateinit var ledger: LedgerApi
        private set

    val timezoneId: String by lazy { PaceDates.currentTimeZoneId() }

    fun todayIso(): String = PaceDates.todayIso(timezoneId) ?: PaceDates.MIN_LOCAL_DATE

    fun init(application: Application) {
        if (!::ledger.isInitialized) {
            ledger = LedgerApi(AndroidDriverFactory.create(application))
        }
    }
}

class PaceApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        AppContainer.init(this)
        pace.app.ai.AiSettings.init(this)
    }
}
