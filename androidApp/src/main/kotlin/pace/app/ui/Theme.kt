package pace.app.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val GreenPrimary = Color(0xFF0F6B5C)
private val GreenContainer = Color(0xFFB8E8DD)

private val LightColors = lightColorScheme(
    primary = GreenPrimary,
    primaryContainer = GreenContainer,
    onPrimaryContainer = Color(0xFF00201A)
)

private val DarkColors = darkColorScheme(
    primary = Color(0xFF7FD5C4),
    primaryContainer = Color(0xFF005044),
    onPrimaryContainer = Color(0xFFB8E8DD)
)

@Composable
fun PaceTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = if (isSystemInDarkTheme()) DarkColors else LightColors,
        content = content
    )
}
