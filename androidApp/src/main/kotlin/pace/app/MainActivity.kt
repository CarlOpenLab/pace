package pace.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import pace.app.ui.AddScreen
import pace.app.ui.BillsScreen
import pace.app.ui.HomeScreen
import pace.app.ui.SettingsScreen
import pace.app.ui.StatsScreen

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            pace.app.ui.PaceTheme {
                PaceApp()
            }
        }
    }
}

private data class Tab(val route: String, val label: String, val icon: ImageVector)

private val tabs = listOf(
    Tab("home", "首页", Icons.Filled.Home),
    Tab("bills", "账单", Icons.AutoMirrored.Filled.List),
    Tab("stats", "统计", Icons.Filled.DateRange),
    Tab("settings", "设置", Icons.Filled.Settings)
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PaceApp() {
    val navController: NavHostController = rememberNavController()
    val backStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = backStackEntry?.destination?.route
    val showChrome = currentRoute in tabs.map { it.route }
    val showFab = currentRoute == "home"

    Scaffold(
        bottomBar = {
            if (showChrome) {
                NavigationBar {
                    tabs.forEach { tab ->
                        NavigationBarItem(
                            selected = currentRoute == tab.route,
                            onClick = {
                                navController.navigate(tab.route) {
                                    popUpTo(navController.graph.startDestinationId) { saveState = true }
                                    launchSingleTop = true
                                    restoreState = true
                                }
                            },
                            icon = { Icon(tab.icon, contentDescription = tab.label) },
                            label = { Text(tab.label) }
                        )
                    }
                }
            }
        },
        floatingActionButton = {
            if (showFab) {
                FloatingActionButton(onClick = { navController.navigate("add") }) {
                    Icon(Icons.Filled.Add, contentDescription = "记一笔")
                }
            }
        }
    ) { padding ->
        NavHost(
            navController = navController,
            startDestination = "home",
            modifier = Modifier.padding(padding)
        ) {
            composable("home") { HomeScreen(onAdd = { navController.navigate("add") }, onOpenTxn = { id -> navController.navigate("add?txnId=$id") }) }
            composable("bills") {
                BillsScreen(
                    onOpenTxn = { id -> navController.navigate("add?txnId=$id") },
                    onAdd = { navController.navigate("add") }
                )
            }
            composable("stats") { StatsScreen() }
            composable("settings") { SettingsScreen() }
            composable(
                route = "add?txnId={txnId}",
                arguments = listOf(
                    androidx.navigation.navArgument("txnId") {
                        nullable = true
                        defaultValue = null
                    }
                )
            ) { entry ->
                AddScreen(
                    txnId = entry.arguments?.getString("txnId"),
                    onDone = { navController.popBackStack() }
                )
            }
        }
    }
}
