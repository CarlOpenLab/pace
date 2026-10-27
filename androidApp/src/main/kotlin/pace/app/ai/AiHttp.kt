package pace.app.ai

import android.util.Log
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.net.UnknownHostException
import javax.net.ssl.SSLException

/**
 * OpenAI 兼容接口的 HTTP 通道（HttpURLConnection，零新依赖）。
 * 只在 Dispatchers.IO 上调用。失败分类对齐 iOS 的 URLError 判法：
 * 没网、地址错、证书不认要做的事不一样，分不出来的才归兜底。
 */
object AiHttp {

    private const val TAG = "PaceAi"

    enum class NetworkKind { OFFLINE, BAD_ADDRESS, CERTIFICATE, TIMEOUT, UNREACHABLE }

    sealed class Outcome {
        data class Status(val code: Int, val body: String) : Outcome()
        data class Network(val kind: NetworkKind) : Outcome()
    }

    fun get(url: String, authorization: String, connectTimeoutMs: Int, readTimeoutMs: Int): Outcome =
        send(url, method = "GET", authorization = authorization, bodyJson = null,
            connectTimeoutMs = connectTimeoutMs, readTimeoutMs = readTimeoutMs)

    fun postJson(url: String, authorization: String, bodyJson: String, connectTimeoutMs: Int, readTimeoutMs: Int): Outcome =
        send(url, method = "POST", authorization = authorization, bodyJson = bodyJson,
            connectTimeoutMs = connectTimeoutMs, readTimeoutMs = readTimeoutMs)

    private fun send(
        url: String,
        method: String,
        authorization: String,
        bodyJson: String?,
        connectTimeoutMs: Int,
        readTimeoutMs: Int
    ): Outcome {
        val connection = try {
            (URL(url).openConnection() as HttpURLConnection).apply {
                requestMethod = method
                connectTimeout = connectTimeoutMs
                readTimeout = readTimeoutMs
                setRequestProperty("Accept", "application/json")
                setRequestProperty("Authorization", authorization)
                if (bodyJson != null) {
                    setRequestProperty("Content-Type", "application/json")
                    doOutput = true
                    outputStream.use { it.write(bodyJson.toByteArray(Charsets.UTF_8)) }
                }
            }
        } catch (e: IOException) {
            return Outcome.Network(classify(e))
        }

        val code = try {
            connection.responseCode
        } catch (e: IOException) {
            connection.disconnect()
            return Outcome.Network(classify(e))
        }
        val body = try {
            val stream = if (code in 200..299) connection.inputStream else connection.errorStream
            stream?.bufferedReader()?.use { it.readText() } ?: ""
        } catch (_: IOException) {
            ""
        } finally {
            connection.disconnect()
        }
        return Outcome.Status(code, body)
    }

    /** Java 异常比 URLError 粗：能分开的分开，分不开的归 UNREACHABLE，不上屏状态码原文。 */
    fun classify(e: IOException): NetworkKind {
        Log.w(TAG, "network failure: ${e.javaClass.simpleName}: ${e.message}")
        return when (e) {
            is javax.net.ssl.SSLHandshakeException -> NetworkKind.CERTIFICATE
            is SSLException -> NetworkKind.CERTIFICATE
            is UnknownHostException -> NetworkKind.BAD_ADDRESS
            is java.net.SocketTimeoutException ->
                // iOS 同款：超时单独成类，对话路径报「那边没回话」，模型列表路径归兜底。
                NetworkKind.TIMEOUT
            is java.net.ConnectException -> NetworkKind.UNREACHABLE
            else -> when {
                e.message?.contains("Network is unreachable", ignoreCase = true) == true -> NetworkKind.OFFLINE
                e.message?.contains("No route to host", ignoreCase = true) == true -> NetworkKind.OFFLINE
                else -> NetworkKind.UNREACHABLE
            }
        }
    }
}
