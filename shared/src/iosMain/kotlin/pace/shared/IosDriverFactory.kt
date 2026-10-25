package pace.shared

import app.cash.sqldelight.db.SqlDriver
import app.cash.sqldelight.driver.native.NativeSqliteDriver
import pace.shared.db.PaceDatabase

/** iOS 端数据库驱动工厂（数据库文件保存在应用沙盒）。 */
object IosDriverFactory {
    fun create(): SqlDriver = NativeSqliteDriver(PaceDatabase.Schema, "pace.db")
}

/** Swift 入口：PaceLibrary.shared.createLedger(driver:) */
object PaceLibrary {
    fun createLedger(driver: SqlDriver): LedgerApi = LedgerApi(driver)
}
