package app.thetahatch.movie

import android.media.AudioAttributes
import android.media.SoundPool
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.exp
import kotlin.math.sin
import kotlin.random.Random

/**
 * シリーズのハブとのやり取り（Series.kt）と、ホイールのクリック音（Theta Music Hatch と同じ作り）。
 * クリック音は SoundPool で鳴らす。音声フォーカスを取らないので、再生中の動画の音は止めない。
 */
class MainActivity : FlutterActivity() {
    private var pool: SoundPool? = null
    private var clickId = 0
    private var clickReady = false
    private var media: MediaBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "theta_movie/series")
            .setMethodCallHandler(Series.handler(this))
        val mediaChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "theta_movie/media")
        media = MediaBridge(this, mediaChannel).also { mediaChannel.setMethodCallHandler(it.handler()) }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "theta_movie/click").setMethodCallHandler { call, result ->
            when (call.method) {
                "click" -> {
                    val v = (call.argument<Double>("volume") ?: 0.8).toFloat()
                    clickPool()
                    val stream = if (clickReady) pool?.play(clickId, v, v, 1, 0, 1f) ?: 0 else 0
                    result.success(stream != 0)
                }
                "prepare" -> {
                    clickPool()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun clickPool() {
        if (pool != null) return
        val p = SoundPool.Builder()
            .setMaxStreams(4)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            .build()
        p.setOnLoadCompleteListener { _, _, status -> clickReady = status == 0 }
        pool = p
        val f = File(cacheDir, "ipod_click_v2.wav")
        if (!f.exists()) writeClick(f)
        clickId = p.load(f.path, 1)
    }

    override fun onDestroy() {
        media?.release()
        pool?.release()
        pool = null
        super.onDestroy()
    }

    companion object {
        private const val RATE = 44100

        /** ホイールの「チッ」：ノイズと高い音を数 ms で減衰させる（頭に無音を置く。Music Hatch と同じ） */
        private fun writeClick(f: File) {
            val lead = RATE * 15 / 1000
            val n = lead + RATE * 30 / 1000
            val rnd = Random(7)
            val pcm = ShortArray(n) { i ->
                if (i < lead) return@ShortArray 0
                val t = (i - lead).toDouble() / RATE
                val env = exp(-t / 0.0025)
                val v = (rnd.nextDouble() * 2 - 1) * 0.5 + sin(2 * PI * 3200 * t) * 0.35 + sin(2 * PI * 1600 * t) * 0.15
                (v * env * 0.95 * Short.MAX_VALUE).toInt().coerceIn(-32767, 32767).toShort()
            }
            val data = n * 2
            val b = ByteBuffer.allocate(44 + data).order(ByteOrder.LITTLE_ENDIAN)
            b.put("RIFF".toByteArray()).putInt(36 + data).put("WAVE".toByteArray())
            b.put("fmt ".toByteArray()).putInt(16).putShort(1).putShort(1).putInt(RATE).putInt(RATE * 2).putShort(2).putShort(16)
            b.put("data".toByteArray()).putInt(data)
            pcm.forEach { b.putShort(it) }
            FileOutputStream(f).use { it.write(b.array()) }
        }
    }
}
