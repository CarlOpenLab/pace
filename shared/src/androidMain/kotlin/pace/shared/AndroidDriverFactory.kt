package pace.shared

import android.content.Context
import app.cash.sqldelight.db.SqlDriver
import app.cash.sqldelight.driver.android.AndroidSqliteDriver
import pace.shared.db.PaceDatabase

/** Android 端数据库驱动工厂。 */
object AndroidDriverFactory {
    fun create(context: Context): SqlDriver =
        AndroidSqliteDriver(PaceDatabase.Schema, context, "pace.db")
}
