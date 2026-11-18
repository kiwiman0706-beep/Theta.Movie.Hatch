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
    init {
        instance = this
    }

    private var title = ""
    private var subtitle = ""
    private var playing = false

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

    /** 通知（再生中の操作ボタン）の許可を、初めて再生したときに 1 回だけ聞く（Android 13 以降） */
    private fun askNotificationOnce() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val p = android.Manifest.permission.POST_NOTIFICATIONS
        if (activity.checkSelfPermission(p) == android.content.pm.PackageManager.PERMISSION_GRANTED) return
        val prefs = activity.getSharedPreferences("media", Context.MODE_PRIVATE)
        if (prefs.getBoolean("askedNotification", false)) return
        prefs.edit().putBoolean("askedNotification", true).apply()
        activity.requestPermissions(arrayOf(p), 4201)
    }

    /** 通知のボタンから（PlaybackService） */
    fun button(b: String) = send(b)

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
                title = call.argument<String>("title") ?: ""
                subtitle = call.argument<String>("subtitle") ?: ""
                if (playing) PlaybackService.update(activity, title, subtitle, true, session?.sessionToken)
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
                this.playing = playing
                // バックグラウンド再生：再生を始めたら前面サービスと通知。一時停止は通知のボタンを切り替えるだけ
                if (playing) askNotificationOnce()
                if (playing || PlaybackServiceRunning.running) {
                    PlaybackService.update(activity, title, subtitle, playing, s.sessionToken)
                    PlaybackServiceRunning.running = true
                }
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
            // 全画面のジェスチャー：画面の明るさ（このアプリの画面だけ。0〜1、-1 で端末の設定に戻す）
            "getBrightness" -> {
                val w = activity.window.attributes.screenBrightness
                val v = if (w >= 0) w else runCatching {
                    android.provider.Settings.System.getInt(activity.contentResolver, android.provider.Settings.System.SCREEN_BRIGHTNESS) / 255f
                }.getOrDefault(0.5f)
                result.success(v.toDouble())
            }
            "setBrightness" -> {
                val v = (call.argument<Number>("value") ?: -1).toFloat()
                activity.runOnUiThread {
                    val a = activity.window.attributes
                    a.screenBrightness = if (v < 0) -1f else v.coerceIn(0.01f, 1f)
                    activity.window.attributes = a
                }
                result.success(null)
            }
            // 全画面のジェスチャー：端末のメディア音量（0〜1）
            "getVolume" -> {
                val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                result.success(if (max == 0) 0.5 else am.getStreamVolume(AudioManager.STREAM_MUSIC).toDouble() / max)
            }
            "setVolume" -> {
                val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                val v = (call.argument<Number>("value") ?: 0.5).toDouble()
                am.setStreamVolume(AudioManager.STREAM_MUSIC, Math.round(v * max).toInt().coerceIn(0, max), 0)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    fun release() {
        PlaybackService.stop(activity)
        PlaybackServiceRunning.running = false
        playing = false
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

    companion object {
        var instance: MediaBridge? = null
    }
}

/** 前面サービスを動かしているか（一時停止で通知を更新するため） */
object PlaybackServiceRunning {
    var running = false
}
