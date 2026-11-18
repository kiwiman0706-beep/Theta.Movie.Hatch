package app.thetahatch.movie

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.session.MediaSession
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * バックグラウンド再生（画面を消しても・ほかのアプリに移っても止まらない）。
 * 再生中だけ前面サービス（種類 mediaPlayback）として動き、通知に操作ボタン（前・再生/一時停止・次）を出す。
 * NAS から読み続けるので、CPU と Wi-Fi が眠らないようにする（WakeLock・WifiLock）。
 * 通知のボタンは MediaBridge に渡す（車・Bluetooth のボタンと同じ道）。
 */
class PlaybackService : Service() {
    private var wake: PowerManager.WakeLock? = null
    private var wifi: WifiManager.WifiLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_PREV -> MediaBridge.instance?.button("previous")
            ACTION_TOGGLE -> MediaBridge.instance?.button(if (playing) "pause" else "play")
            ACTION_NEXT -> MediaBridge.instance?.button("next")
            ACTION_STOP -> {
                MediaBridge.instance?.button("pause")
                stopSelf()
                return START_NOT_STICKY
            }
        }
        show()
        hold(playing)
        return START_NOT_STICKY
    }

    private fun show() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && nm.getNotificationChannel(CHANNEL) == null) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL, "再生中", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "動画の再生（画面を消しても続ける）"
                    setShowBadge(false)
                },
            )
        }
        fun pi(action: String, code: Int) = PendingIntent.getService(
            this, code, Intent(this, PlaybackService::class.java).setAction(action),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val b = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(this, CHANNEL) else
            @Suppress("DEPRECATION") Notification.Builder(this)
        @Suppress("DEPRECATION")
        val n = b.setSmallIcon(if (playing) android.R.drawable.ic_media_play else android.R.drawable.ic_media_pause)
            .setContentTitle(title)
            .setContentText(subtitle)
            .setContentIntent(open)
            .setOngoing(true)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setDeleteIntent(pi(ACTION_STOP, 4))
            .addAction(Notification.Action(android.R.drawable.ic_media_previous, "前", pi(ACTION_PREV, 1)))
            .addAction(
                Notification.Action(
                    if (playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
                    if (playing) "一時停止" else "再生",
                    pi(ACTION_TOGGLE, 2),
                ),
            )
            .addAction(Notification.Action(android.R.drawable.ic_media_next, "次", pi(ACTION_NEXT, 3)))
            .setStyle(Notification.MediaStyle().setMediaSession(token).setShowActionsInCompactView(0, 1, 2))
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        } else {
            startForeground(ID, n)
        }
    }

    private fun hold(on: Boolean) {
        if (on) {
            if (wake == null) {
                wake = (getSystemService(Context.POWER_SERVICE) as PowerManager)
                    .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "ThetaMovieHatch:play").apply { setReferenceCounted(false) }
            }
            if (wifi == null) {
                @Suppress("DEPRECATION")
                wifi = (applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager)
                    .createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "ThetaMovieHatch:play").apply { setReferenceCounted(false) }
            }
            // 長くても 6 時間で外す（止め忘れの電池切れを防ぐ）
            wake?.acquire(6 * 60 * 60 * 1000L)
            wifi?.acquire()
        } else {
            if (wake?.isHeld == true) wake?.release()
            if (wifi?.isHeld == true) wifi?.release()
        }
    }

    override fun onDestroy() {
        hold(false)
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL = "playback"
        private const val ID = 7301
        const val ACTION_PREV = "app.thetahatch.movie.PREV"
        const val ACTION_TOGGLE = "app.thetahatch.movie.TOGGLE"
        const val ACTION_NEXT = "app.thetahatch.movie.NEXT"
        const val ACTION_STOP = "app.thetahatch.movie.STOP"

        var title = ""
        var subtitle = ""
        var playing = false
        var token: MediaSession.Token? = null

        /** 再生・一時停止・題名が変わったら呼ぶ（無ければ始める） */
        fun update(c: Context, title: String, subtitle: String, playing: Boolean, token: MediaSession.Token?) {
            this.title = title
            this.subtitle = subtitle
            this.playing = playing
            this.token = token
            val i = Intent(c, PlaybackService::class.java)
            try {
                if (playing && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) c.startForegroundService(i) else c.startService(i)
            } catch (_: Exception) {
                // 裏から始められない場合（Android 12 以降の制限）は、次に前に出たときに
            }
        }

        fun stop(c: Context) {
            playing = false
            c.stopService(Intent(c, PlaybackService::class.java))
        }
    }
}
