package app.thetahatch.movie

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import io.flutter.plugin.common.MethodChannel

/**
 * 再生中であることを Android に知らせる（オーディオフォーカスとメディアセッション）。
 * これが無いと、Android Auto は車に音を流さず、Bluetooth の機器のボタンも効かない
 * （Theta Music Hatch は audio_service で同じことをしている）。
 * - 再生を始めたらフォーカスを取り（ほかのアプリの音楽は止まる）、セッションを有効に
 * - 車・Bluetooth・イヤホンのボタン（再生・一時停止・次・前・シーク）を Dart へ
 * - 電話などでフォーカスを失ったら一時停止、戻ったら再開。Bluetooth が切れた・イヤホンが抜けたら一時停止
 */
class MediaBridge(private val activity: Activity, private val channel: MethodChannel) {
    private val am = activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var session: MediaSession? = null
    private var focus: AudioFocusRequest? = null
    private var resumeOnGain = false
    private var noisyRegistered = false

    private val attrs = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
        .build()

    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        when (change) {
            AudioManager.AUDIOFOCUS_LOSS -> {
                resumeOnGain = false
                send("pause")
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT, AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                resumeOnGain = true
                send("pause")
            }
            AudioManager.AUDIOFOCUS_GAIN -> {
                if (resumeOnGain) send("play")
                resumeOnGain = false
            }
        }
    }

    private val noisy = object : BroadcastReceiver() {
        override fun onReceive(c: Context, i: Intent) {
            if (i.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) send("pause")
        }
    }

    private fun send(button: String, pos: Long? = null) {
        activity.runOnUiThread {
            channel.invokeMethod("button", if (pos == null) mapOf("b" to button) else mapOf("b" to button, "pos" to pos))
        }
    }

    private fun ensureSession(): MediaSession {
        session?.let { return it }
        val s = MediaSession(activity, "ThetaMovieHatch")
        s.setCallback(object : MediaSession.Callback() {
            override fun onPlay() = send("play")
            override fun onPause() = send("pause")
            override fun onStop() = send("pause")
            override fun onSkipToNext() = send("next")
            override fun onSkipToPrevious() = send("previous")
            override fun onFastForward() = send("forward")
            override fun onRewind() = send("rewind")
            override fun onSeekTo(pos: Long) = send("seek", pos)
        })
        session = s
        return s
    }

    private fun requestFocus(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val r = focus ?: AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(attrs)
                .setOnAudioFocusChangeListener(focusListener)
                .setWillPauseWhenDucked(true)
                .build().also { focus = it }
            return am.requestAudioFocus(r) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        }
        @Suppress("DEPRECATION")
        return am.requestAudioFocus(focusListener, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN) ==
            AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    }

    private fun abandonFocus() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focus?.let { am.abandonAudioFocusRequest(it) }
        } else {
            @Suppress("DEPRECATION")
            am.abandonAudioFocus(focusListener)
        }
    }

    fun handler() = MethodChannel.MethodCallHandler { call, result ->
        when (call.method) {
            // 作品が変わった・再生を始めた：題名と長さ
            "meta" -> {
                val s = ensureSession()
                s.setMetadata(
                    MediaMetadata.Builder()
                        .putString(MediaMetadata.METADATA_KEY_TITLE, call.argument<String>("title") ?: "")
                        .putString(MediaMetadata.METADATA_KEY_ARTIST, call.argument<String>("subtitle") ?: "")
                        .putString(MediaMetadata.METADATA_KEY_ALBUM, "Theta Movie Hatch")
                        .putLong(MediaMetadata.METADATA_KEY_DURATION, (call.argument<Number>("duration") ?: 0).toLong())
                        .build(),
                )
                result.success(null)
            }
            // 再生・一時停止・位置が変わった
            "state" -> {
                val playing = call.argument<Boolean>("playing") ?: false
                val pos = (call.argument<Number>("pos") ?: 0).toLong()
                val s = ensureSession()
                if (playing) {
                    val granted = requestFocus()
                    if (!s.isActive) s.isActive = true
                    if (!noisyRegistered) {
                        val f = IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
                        // Android 13 以降は登録の種類を書く（システムの通知は NOT_EXPORTED でも届く）
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            activity.registerReceiver(noisy, f, Context.RECEIVER_NOT_EXPORTED)
                        } else {
                            activity.registerReceiver(noisy, f)
                        }
                        noisyRegistered = true
                    }
                    result.success(granted)
                } else {
                    result.success(true)
                }
                s.setPlaybackState(
                    PlaybackState.Builder()
                        .setActions(
                            PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or PlaybackState.ACTION_PLAY_PAUSE or
                                PlaybackState.ACTION_SKIP_TO_NEXT or PlaybackState.ACTION_SKIP_TO_PREVIOUS or
                                PlaybackState.ACTION_SEEK_TO or PlaybackState.ACTION_FAST_FORWARD or
                                PlaybackState.ACTION_REWIND or PlaybackState.ACTION_STOP,
                        )
                        .setState(if (playing) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED, pos, if (playing) 1f else 0f)
                        .build(),
                )
            }
            // 再生を止めた：フォーカスとセッションを返す
            "stop" -> {
                release()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    fun release() {
        abandonFocus()
        resumeOnGain = false
        if (noisyRegistered) {
            runCatching { activity.unregisterReceiver(noisy) }
            noisyRegistered = false
        }
        session?.let {
            it.isActive = false
            it.release()
        }
        session = null
    }
}
