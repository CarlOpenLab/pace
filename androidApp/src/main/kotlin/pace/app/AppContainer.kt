package pace.app

import android.app.Application
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
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

    /**
     * 把账本读写挪出主线程：LedgerApi 保持同步（与 iOS 共用一套门面），
     * Android 的所有调用点统一包在这里。一次性小查询（打开页面取编辑态）可以不走。
     */
    suspend fun <T> withLedger(block: (LedgerApi) -> T): T =
        withContext(Dispatchers.IO) { block(ledger) }
}

class PaceApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        AppContainer.init(this)
        pace.app.ai.AiSettings.init(this)
    }
}
