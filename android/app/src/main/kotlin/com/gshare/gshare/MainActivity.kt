package com.gshare.gshare

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var multicastLock: WifiManager.MulticastLock? = null
    private var hotspot: WifiManager.LocalOnlyHotspotReservation? = null
    private var hotspotInfo: Map<String, Any>? = null
    private val pendingFiles = ArrayList<String>()
    private var pendingText: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        ch.setMethodCallHandler { call, result -> onCall(call, result) }
        channel = ch
        collectShared(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        collectShared(intent)
    }

    override fun onDestroy() {
        stopHotspot()
        multicastLock?.let { if (it.isHeld) it.release() }
        multicastLock = null
        super.onDestroy()
    }

    private fun onCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "acquireMulticastLock" -> {
                acquireMulticastLock()
                result.success(null)
            }
            "releaseMulticastLock" -> {
                multicastLock?.let { if (it.isHeld) it.release() }
                multicastLock = null
                result.success(null)
            }
            "setTransferActive" -> {
                setTransferActive(call.argument<Boolean>("active") == true)
                result.success(null)
            }
            "startHotspot" -> startHotspot(result)
            "stopHotspot" -> {
                stopHotspot()
                result.success(null)
            }
            "getHotspot" -> result.success(hotspotInfo)
            "takeSharedItems" -> {
                val out = mapOf("files" to ArrayList(pendingFiles), "text" to pendingText)
                pendingFiles.clear()
                pendingText = null
                result.success(out)
            }
            "saveToDownloads" -> {
                val path = call.argument<String>("path")
                val name = call.argument<String>("name")
                val mime = call.argument<String>("mime") ?: "application/octet-stream"
                if (path == null || name == null) {
                    result.error("ARGS", "path and name are required", null)
                    return
                }
                Thread {
                    val ok = saveToDownloads(File(path), name, mime)
                    runOnUiThread { result.success(ok) }
                }.start()
            }
            else -> result.notImplemented()
        }
    }

    // Android drops multicast packets unless an app holds this lock.
    private fun acquireMulticastLock() {
        if (multicastLock?.isHeld == true) return
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        multicastLock = wifi.createMulticastLock("gshare").apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    private fun setTransferActive(active: Boolean) {
        val intent = Intent(this, TransferService::class.java)
        try {
            if (active) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent) else startService(intent)
            } else {
                stopService(intent)
            }
        } catch (e: Exception) {
            // Android 12+ refuses to start foreground services from the background; the transfer still runs.
        }
    }

    // ---- Hotspot (LocalOnlyHotspot: no internet, random SSID and password) ----

    private fun startHotspot(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.error("UNSUPPORTED", "The in-app hotspot needs Android 8.0 or newer.", null)
            return
        }
        hotspotInfo?.let {
            result.success(it)
            return
        }
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        var replied = false
        try {
            wifi.startLocalOnlyHotspot(object : WifiManager.LocalOnlyHotspotCallback() {
                override fun onStarted(reservation: WifiManager.LocalOnlyHotspotReservation) {
                    hotspot = reservation
                    val info = readHotspot(reservation)
                    hotspotInfo = info
                    if (!replied) {
                        replied = true
                        result.success(info)
                    }
                }

                override fun onStopped() {
                    hotspot = null
                    hotspotInfo = null
                    channel?.invokeMethod("hotspotStopped", null)
                }

                override fun onFailed(reason: Int) {
                    if (!replied) {
                        replied = true
                        result.error("HOTSPOT_FAILED", hotspotError(reason), null)
                    }
                }
            }, Handler(Looper.getMainLooper()))
        } catch (e: SecurityException) {
            result.error("PERMISSION", "gshare needs the Nearby devices (or Location) permission and Location turned on.", null)
        } catch (e: IllegalStateException) {
            result.error("HOTSPOT_FAILED", e.message ?: "The hotspot is not available right now.", null)
        }
    }

    @Suppress("DEPRECATION")
    private fun readHotspot(r: WifiManager.LocalOnlyHotspotReservation): Map<String, Any> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val c = r.softApConfiguration
            mapOf(
                "ssid" to (c.ssid ?: "").trim('"'),
                "password" to (c.passphrase ?: ""),
                "security" to c.securityType,
            )
        } else {
            val c = r.wifiConfiguration
            mapOf(
                "ssid" to (c?.SSID ?: "").trim('"'),
                "password" to (c?.preSharedKey ?: "").trim('"'),
                "security" to 1,
            )
        }
    }

    private fun hotspotError(reason: Int): String = when (reason) {
        WifiManager.LocalOnlyHotspotCallback.ERROR_NO_CHANNEL -> "No free Wi-Fi channel. Try again in a moment."
        WifiManager.LocalOnlyHotspotCallback.ERROR_INCOMPATIBLE_MODE -> "Turn off the phone's regular hotspot or tethering first."
        WifiManager.LocalOnlyHotspotCallback.ERROR_TETHERING_DISALLOWED -> "Hotspots are blocked on this device (for example by a work profile)."
        else -> "The hotspot could not start (code $reason)."
    }

    private fun stopHotspot() {
        try {
            hotspot?.close()
        } catch (e: Exception) {
            // already closed
        }
        hotspot = null
        hotspotInfo = null
    }

    // ---- Share sheet ----

    private fun collectShared(intent: Intent?) {
        if (intent == null) return
        val action = intent.action
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) return
        val uris = ArrayList<Uri>()
        if (action == Intent.ACTION_SEND) {
            streamExtra(intent)?.let { uris.add(it) }
        } else {
            uris.addAll(streamListExtra(intent))
        }
        val text = if (uris.isEmpty()) intent.getStringExtra(Intent.EXTRA_TEXT) else null
        intent.action = null // don't handle again after rotation

        // Copying can take a while for large videos, so it runs off the main thread.
        Thread {
            val paths = uris.mapNotNull { copyToCache(it) }
            runOnUiThread {
                pendingFiles.addAll(paths)
                if (text != null) pendingText = text
                channel?.invokeMethod("sharedReceived", null)
            }
        }.start()
    }

    @Suppress("DEPRECATION")
    private fun streamExtra(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        else intent.getParcelableExtra(Intent.EXTRA_STREAM)

    @Suppress("DEPRECATION")
    private fun streamListExtra(intent: Intent): List<Uri> =
        (if (Build.VERSION.SDK_INT >= 33) intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
        else intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)) ?: emptyList()

    private fun copyToCache(uri: Uri): String? {
        return try {
            val name = (displayName(uri) ?: "shared_${System.currentTimeMillis()}").replace('/', '_')
            val dir = File(cacheDir, "shared/${System.nanoTime()}").apply { mkdirs() }
            val out = File(dir, name)
            val input = contentResolver.openInputStream(uri) ?: return null
            input.use { src -> out.outputStream().use { dst -> src.copyTo(dst) } }
            out.absolutePath
        } catch (e: Exception) {
            null
        }
    }

    private fun displayName(uri: Uri): String? =
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) c.getString(0) else null
        }

    // ---- Public Downloads/gshare ----

    private fun saveToDownloads(src: File, name: String, mime: String): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.Downloads.DISPLAY_NAME, name)
                    put(MediaStore.Downloads.MIME_TYPE, mime)
                    put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/gshare")
                    put(MediaStore.Downloads.IS_PENDING, 1)
                }
                val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: return false
                contentResolver.openOutputStream(uri)?.use { out -> FileInputStream(src).use { it.copyTo(out) } }
                values.clear()
                values.put(MediaStore.Downloads.IS_PENDING, 0)
                contentResolver.update(uri, values, null, null)
                true
            } else {
                @Suppress("DEPRECATION")
                val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "gshare")
                dir.mkdirs()
                var target = File(dir, name)
                var i = 1
                while (target.exists()) {
                    target = File(dir, "${name.substringBeforeLast('.')} ($i)${if (name.contains('.')) "." + name.substringAfterLast('.') else ""}")
                    i++
                }
                src.copyTo(target)
                true
            }
        } catch (e: Exception) {
            false
        }
    }

    companion object {
        private const val CHANNEL = "gshare/native"
    }
}
