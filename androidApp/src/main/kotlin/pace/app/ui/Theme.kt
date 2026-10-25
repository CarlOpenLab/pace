package pace.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.isSystemInDarkTheme

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

// ---------- 玻璃质感设计系统 ----------

object PaceGradients {
    val mint = Color(0xFF0D8570)
    val mintLight = Color(0xFF4DC79E)
    val danger = Color(0xFFE64D51)
    val dangerLight = Color(0xFFFA8078)

    /** 主色渐变（青绿 → 薄荷） */
    @Composable
    fun accent(): Brush = Brush.linearGradient(listOf(mint, mintLight))

    @Composable
    fun dangerBrush(): Brush = Brush.linearGradient(listOf(danger, dangerLight))

    /** 玻璃卡顶部高光 */
    private val sheenTop = Color.White.copy(alpha = 0.30f)
    private val sheenMid = Color.White.copy(alpha = 0.06f)
    private val sheenEnd = Color.White.copy(alpha = 0f)
    val sheen: Brush = Brush.verticalGradient(listOf(sheenTop, sheenMid, sheenEnd))

    /** 全局环境背景（亮色） */
    val backgroundLight: Brush = Brush.linearGradient(
        0f to Color(0xFFE8F6F1),
        0.45f to Color(0xFFEDF3EE),
        1f to Color(0xFFEEF0FA)
    )

    /** 全局环境背景（暗色） */
    val backgroundDark: Brush = Brush.linearGradient(
        0f to Color(0xFF081A18),
        0.6f to Color(0xFF0A1424),
        1f to Color(0xFF120F24)
    )
}

/** 玻璃卡片：半透明底 + 顶部高光 + 细白描边（padding 由调用方自行控制） */
@Composable
fun Modifier.glassCard(shape: Shape = RoundedCornerShape(28.dp)): Modifier {
    val dark = isSystemInDarkTheme()
    val base = if (dark) Color(0xFF152422).copy(alpha = 0.55f) else Color.White.copy(alpha = 0.52f)
    return this
        .background(base, shape)
        .background(PaceGradients.sheen, shape)
        .border(
            width = 1.dp,
            brush = Brush.linearGradient(
                listOf(Color.White.copy(alpha = 0.45f), Color.White.copy(alpha = 0.08f))
            ),
            shape = shape
        )
}

/** 渐变数字文本 */
@Composable
fun GradientText(text: String, brush: Brush, style: TextStyle) {
    Text(text = text, style = style.copy(brush = brush))
}

/** 玻璃进度条 */
@Composable
fun GlassProgress(ratio: Float, danger: Boolean, modifier: Modifier = Modifier) {
    val dark = isSystemInDarkTheme()
    val track = if (dark) Color.White.copy(alpha = 0.12f) else Color.White.copy(alpha = 0.6f)
    val fill = if (danger) PaceGradients.dangerBrush() else PaceGradients.accent()
    Box(
        modifier = modifier
            .height(8.dp)
            .background(track, RoundedCornerShape(50))
    ) {
        Box(
            modifier = Modifier
                .fillMaxHeight()
                .fillMaxWidth(ratio.coerceIn(0f, 1f))
                .background(fill, RoundedCornerShape(50))
        )
    }
}
