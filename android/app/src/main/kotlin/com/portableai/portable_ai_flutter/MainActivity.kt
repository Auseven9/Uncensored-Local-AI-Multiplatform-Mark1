package com.portableai.portable_ai_flutter

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.os.StatFs
import android.os.SystemClock
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.RandomAccessFile

/// Native resource channel for the Monitor. Returns only the real device
/// readings Android exposes to a sandboxed app (own/total CPU where the kernel
/// allows, RAM, thermal, battery detail, storage, uptime, environment sensors,
/// and fused orientation). Values the OS withholds are simply absent — the Dart
/// side renders those as "no socket" rather than inventing a number.
class MainActivity : FlutterActivity(), SensorEventListener {
    private val channelName = "aether/stats"

    private var sensorManager: SensorManager? = null
    private var lightLux: Float? = null
    private var proximityCm: Float? = null
    private var pressureHpa: Float? = null

    private val rotMatrix = FloatArray(9)
    private val orientationAngles = FloatArray(3)
    private var oriAzimuth: Float? = null
    private var oriPitch: Float? = null
    private var oriRoll: Float? = null

    private var lastCpuTotal = 0L
    private var lastCpuIdle = 0L

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        setupSensors()
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "read" -> result.success(readStats())
                    "readFast" -> result.success(readFast())
                    else -> result.notImplemented()
                }
            }
    }

    private fun setupSensors() {
        try {
            val sm = getSystemService(Context.SENSOR_SERVICE) as SensorManager
            sensorManager = sm
            sm.getDefaultSensor(Sensor.TYPE_LIGHT)?.let {
                sm.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL)
            }
            sm.getDefaultSensor(Sensor.TYPE_PROXIMITY)?.let {
                sm.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL)
            }
            sm.getDefaultSensor(Sensor.TYPE_PRESSURE)?.let {
                sm.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL)
            }
            sm.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)?.let {
                sm.registerListener(this, it, SensorManager.SENSOR_DELAY_GAME)
            }
        } catch (_: Exception) {}
    }

    override fun onSensorChanged(event: SensorEvent) {
        when (event.sensor.type) {
            Sensor.TYPE_LIGHT -> lightLux = event.values[0]
            Sensor.TYPE_PROXIMITY -> proximityCm = event.values[0]
            Sensor.TYPE_PRESSURE -> pressureHpa = event.values[0]
            Sensor.TYPE_ROTATION_VECTOR -> {
                SensorManager.getRotationMatrixFromVector(rotMatrix, event.values)
                SensorManager.getOrientation(rotMatrix, orientationAngles)
                oriAzimuth = orientationAngles[0]
                oriPitch = orientationAngles[1]
                oriRoll = orientationAngles[2]
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    override fun onDestroy() {
        try {
            sensorManager?.unregisterListener(this)
        } catch (_: Exception) {}
        super.onDestroy()
    }

    /// Cheap, IO-free read of the cached high-rate sensors (orientation +
    /// light/proximity/pressure) — polled fast so they feel live.
    private fun readFast(): HashMap<String, Any> {
        val m = HashMap<String, Any>()
        oriAzimuth?.let {
            var d = Math.toDegrees(it.toDouble())
            if (d < 0) d += 360.0
            m["compassDeg"] = d
        }
        oriPitch?.let { m["pitchDeg"] = Math.toDegrees(it.toDouble()) }
        oriRoll?.let { m["rollDeg"] = Math.toDegrees(it.toDouble()) }
        lightLux?.let { m["lightLux"] = it }
        proximityCm?.let { m["proximityCm"] = it }
        pressureHpa?.let { m["pressureHpa"] = it }
        return m
    }

    private fun readStats(): HashMap<String, Any> {
        val m = HashMap<String, Any>()

        try {
            RandomAccessFile("/proc/stat", "r").use { raf ->
                val line = raf.readLine()
                if (line != null && line.startsWith("cpu ")) {
                    val parts = line.split(Regex("\\s+")).drop(1).mapNotNull { it.toLongOrNull() }
                    if (parts.size >= 4) {
                        val idle = parts[3] + (if (parts.size > 4) parts[4] else 0L)
                        val total = parts.sum()
                        val dTotal = total - lastCpuTotal
                        val dIdle = idle - lastCpuIdle
                        if (lastCpuTotal > 0L && dTotal > 0L) {
                            m["cpu"] = (100.0 * (dTotal - dIdle) / dTotal).coerceIn(0.0, 100.0)
                        }
                        lastCpuTotal = total
                        lastCpuIdle = idle
                    }
                }
            }
        } catch (_: Exception) {}

        try {
            val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val mi = ActivityManager.MemoryInfo()
            am.getMemoryInfo(mi)
            m["ramTotalMb"] = mi.totalMem / 1048576.0
            m["ramAvailMb"] = mi.availMem / 1048576.0
            m["ramUsedMb"] = (mi.totalMem - mi.availMem) / 1048576.0
        } catch (_: Exception) {}

        try {
            if (Build.VERSION.SDK_INT >= 29) {
                val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                m["thermal"] = pm.currentThermalStatus
            }
        } catch (_: Exception) {}

        try {
            val bm = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
            val cur = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CURRENT_NOW)
            if (cur != Int.MIN_VALUE && cur != 0) m["batteryCurrentUa"] = cur
            val intent = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            if (intent != null) {
                val temp = intent.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, -1)
                val volt = intent.getIntExtra(BatteryManager.EXTRA_VOLTAGE, -1)
                if (temp > 0) m["batteryTempC"] = temp / 10.0
                if (volt > 0) m["batteryVoltageMv"] = volt
            }
        } catch (_: Exception) {}

        try {
            val stat = StatFs(Environment.getDataDirectory().path)
            m["storageFreeGb"] = stat.availableBytes / 1.0e9
            m["storageTotalGb"] = stat.totalBytes / 1.0e9
        } catch (_: Exception) {}

        try {
            m["uptimeMs"] = SystemClock.elapsedRealtime()
        } catch (_: Exception) {}

        lightLux?.let { m["lightLux"] = it }
        proximityCm?.let { m["proximityCm"] = it }
        pressureHpa?.let { m["pressureHpa"] = it }
        oriAzimuth?.let {
            var d = Math.toDegrees(it.toDouble())
            if (d < 0) d += 360.0
            m["compassDeg"] = d
        }
        oriPitch?.let { m["pitchDeg"] = Math.toDegrees(it.toDouble()) }
        oriRoll?.let { m["rollDeg"] = Math.toDegrees(it.toDouble()) }

        return m
    }
}
