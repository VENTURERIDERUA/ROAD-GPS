package io.github.ventureriderua.road_gps

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        // Вібрація біля позначки: дві помітні хвилі — не сплутати з дотиком до екрана.
        MethodChannel(messenger, "road_gps/vibrate").setMethodCallHandler { call, result ->
            if (call.method != "vibrate") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val ms = ((call.arguments as? Int) ?: 400).toLong()
            val v: Vibrator = if (Build.VERSION.SDK_INT >= 31) {
                getSystemService(VibratorManager::class.java).defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(VIBRATOR_SERVICE) as Vibrator
            }
            val pattern = longArrayOf(0, ms, 200, ms)
            if (Build.VERSION.SDK_INT >= 26) {
                v.vibrate(VibrationEffect.createWaveform(pattern, -1))
            } else {
                @Suppress("DEPRECATION")
                v.vibrate(pattern, -1)
            }
            result.success(null)
        }
        // Надіслати файл у конкретну програму (Telegram, WhatsApp, диск) чи в поштову.
        MethodChannel(messenger, "road_gps/send").setMethodCallHandler { call, result ->
            when (call.method) {
                "installed" -> {
                    val pkgs = call.arguments as List<*>
                    result.success(pkgs.filterIsInstance<String>().filter { installed(it) })
                }
                "send" -> {
                    val file = File(call.argument<String>("path")!!)
                    val uri = FileProvider.getUriForFile(this, "$packageName.send", file)
                    val pkg = call.argument<String>("package")
                    val email = call.argument<Boolean>("email") == true
                    val i = Intent(Intent.ACTION_SEND).apply {
                        type = call.argument<String>("mime")
                        putExtra(Intent.EXTRA_STREAM, uri)
                        putExtra(Intent.EXTRA_SUBJECT, call.argument<String>("subject"))
                        putExtra(Intent.EXTRA_TEXT, call.argument<String>("text"))
                        // Дозвіл на файл має дійти й через selector пошти — тому ще й ClipData.
                        clipData = ClipData.newRawUri(file.name, uri)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        if (pkg != null) setPackage(pkg)
                        if (email) selector = Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:"))
                    }
                    try {
                        startActivity(if (pkg == null && !email) Intent.createChooser(i, null) else i)
                        result.success(true)
                    } catch (e: ActivityNotFoundException) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun installed(pkg: String): Boolean = try {
        if (Build.VERSION.SDK_INT >= 33) {
            packageManager.getPackageInfo(pkg, PackageManager.PackageInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(pkg, 0)
        }
        true
    } catch (e: Exception) {
        false
    }
}
