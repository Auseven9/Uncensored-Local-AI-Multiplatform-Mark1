package com.portableai.portable_ai_flutter

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.media.AudioManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.TrafficStats
import android.os.BatteryManager
import android.os.Build
import android.os.Debug
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.Process
import android.os.StatFs
import android.os.SystemClock
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import java.io.File
import java.io.RandomAccessFile
import kotlin.math.abs
import kotlin.math.acos
import kotlin.math.atan2
import kotlin.math.sqrt

/// Native sensor + telemetry hub. Registers every available sensor at the
/// fastest rate and streams a combined frame (~60fps) over an EventChannel.
/// Everything is a real reading or a real derivation of one; anything the
/// device/OS does not expose is simply absent from the frame, so the UI shows
/// "no socket" — never a fabricated value.
class MainActivity : FlutterActivity(), SensorEventListener {
    private val streamName = "aether/stream"
    private var sink: EventChannel.EventSink? = null

    private var sm: SensorManager? = null
    private val handler = Handler(Looper.getMainLooper())

    // ── cached raw sensor values ──
    private var accel: FloatArray? = null
    private var linear: FloatArray? = null
    private var gravity: FloatArray? = null
    private var gyro: FloatArray? = null
    private var mag: FloatArray? = null
    private var light: Float? = null
    private var prox: Float? = null
    private var pressure: Float? = null
    private var ambientTemp: Float? = null
    private var humidity: Float? = null
    private var hall: Float? = null
    private val rotM = FloatArray(9)
    private val ori = FloatArray(3)

    // ── sensor health: name/liveness/accuracy per type ──
    private val sensorNames = HashMap<Int, String>()
    private val lastSeen = HashMap<Int, Long>()
    private val accuracyMap = HashMap<Int, Int>()

    // ── full inventory probe: per distinct sensor (by name) ──
    private val lastSeenName = HashMap<String, Long>()
    private val registeredOkName = HashMap<String, Boolean>()
    private var haveRot = false

    // ── derivation state ──
    private var lastAmag = 0.0
    private var lastAmagT = 0L
    private var jerk = 0.0
    private var lastAlt = Double.NaN
    private var lastAltT = 0L
    private var vspeed = 0.0
    private var floors = 0.0
    private var stepCount = 0
    private var lastStepT = 0L
    private var lastPeakT = 0L
    private var aboveThresh = false
    private val cadenceStamps = ArrayDeque<Long>()
    private var shakes = 0
    private var jolt = 0.0
    private var motionEnergy = 0.0
    private var zc = 0
    private var lastZcWindow = 0L
    private var vibHz = 0.0
    private var lastSign = 0

    // ── heavy telemetry cache ──
    private var lastHeavy = 0L
    private var heavy = HashMap<String, Any>()
    private var lastCpuTime = 0L
    private var lastCpuWall = 0L
    private var lastRx = 0L
    private var lastTx = 0L
    private var lastNetT = 0L
    private var ncores = Runtime.getRuntime().availableProcessors()

    private val emitter = object : Runnable {
        override fun run() {
            try {
                sink?.success(frame())
            } catch (_: Exception) {}
            handler.postDelayed(this, 16)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, streamName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    sink = events
                    registerSensors()
                    handler.post(emitter)
                }
                override fun onCancel(arguments: Any?) {
                    handler.removeCallbacks(emitter)
                    try { sm?.unregisterListener(this@MainActivity) } catch (_: Exception) {}
                    sink = null
                }
            })
    }

    private fun reg(type: Int, delay: Int) {
        try {
            val sensor = sm?.getDefaultSensor(type)
            if (sensor != null) {
                sensorNames[type] = sensor.name
                val ok = sm?.registerListener(this, sensor, delay) ?: false
                registeredOkName[sensor.name] = ok
            }
        } catch (_: Exception) {}
    }

    // Permission a sensor type needs before it will stream (for honest labeling).
    private fun gateFor(type: Int): String = when (type) {
        Sensor.TYPE_STEP_COUNTER, Sensor.TYPE_STEP_DETECTOR -> "ACTIVITY_RECOGNITION"
        Sensor.TYPE_HEART_RATE -> "BODY_SENSORS"
        31, 34 -> "BODY_SENSORS" // heart-beat, low-latency off-body
        else -> ""
    }

    private fun registerSensors() {
        val mgr = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        sm = mgr
        val fast = SensorManager.SENSOR_DELAY_FASTEST
        val game = SensorManager.SENSOR_DELAY_GAME
        val norm = SensorManager.SENSOR_DELAY_NORMAL
        reg(Sensor.TYPE_ACCELEROMETER, fast)
        reg(Sensor.TYPE_LINEAR_ACCELERATION, fast)
        reg(Sensor.TYPE_GRAVITY, game)
        reg(Sensor.TYPE_GYROSCOPE, fast)
        reg(Sensor.TYPE_MAGNETIC_FIELD, game)
        reg(Sensor.TYPE_ROTATION_VECTOR, game)
        reg(Sensor.TYPE_LIGHT, norm)
        reg(Sensor.TYPE_PROXIMITY, norm)
        reg(Sensor.TYPE_PRESSURE, norm)
        reg(Sensor.TYPE_AMBIENT_TEMPERATURE, norm)
        reg(Sensor.TYPE_RELATIVE_HUMIDITY, norm)
        // Inventory probe: attempt to register EVERY sensor the device exposes
        // (Samsung private paths included) at a low rate, and record whether the
        // registration was accepted — the real "how deep can we reach" signal.
        // The high-rate sensors above are skipped here (already registered).
        try {
            for (s in mgr.getSensorList(Sensor.TYPE_ALL)) {
                if (registeredOkName.containsKey(s.name)) continue
                val ok = try {
                    mgr.registerListener(this, s, norm)
                } catch (_: Exception) {
                    false
                }
                registeredOkName[s.name] = ok
            }
        } catch (_: Exception) {}
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
        if (sensor != null) accuracyMap[sensor.type] = accuracy
    }

    override fun onSensorChanged(e: SensorEvent) {
        val tNow = SystemClock.elapsedRealtime()
        lastSeen[e.sensor.type] = tNow
        lastSeenName[e.sensor.name] = tNow
        when (e.sensor.type) {
            Sensor.TYPE_ACCELEROMETER -> {
                accel = e.values.clone()
                val m = mag3(e.values)
                val now = SystemClock.elapsedRealtime()
                if (lastAmagT > 0) {
                    val dt = (now - lastAmagT) / 1000.0
                    if (dt > 0) jerk = abs(m - lastAmag) / dt
                }
                lastAmag = m; lastAmagT = now
                // vibration dominant Hz via zero-crossings of AC component (~9.81 mean)
                val ac = m - 9.81
                val sign = if (ac > 0.15) 1 else if (ac < -0.15) -1 else 0
                if (sign != 0 && lastSign != 0 && sign != lastSign) zc++
                if (sign != 0) lastSign = sign
                if (now - lastZcWindow >= 1000) {
                    vibHz = zc / 2.0
                    zc = 0; lastZcWindow = now
                }
            }
            Sensor.TYPE_LINEAR_ACCELERATION -> {
                linear = e.values.clone()
                val lm = mag3(e.values)
                motionEnergy = motionEnergy * 0.9 + lm * 0.1
                jolt = if (lm > jolt) lm else jolt * 0.92 // peak-hold with decay
                val now = SystemClock.elapsedRealtime()
                // self pedometer: peak detection on linear-accel magnitude
                if (lm > 2.2 && !aboveThresh && now - lastPeakT > 300) {
                    aboveThresh = true
                    stepCount++
                    lastPeakT = now
                    cadenceStamps.addLast(now)
                    while (cadenceStamps.isNotEmpty() && now - cadenceStamps.first() > 10000) cadenceStamps.removeFirst()
                } else if (lm < 1.2) {
                    aboveThresh = false
                }
                if (lm > 18) shakes++
            }
            Sensor.TYPE_GRAVITY -> gravity = e.values.clone()
            Sensor.TYPE_GYROSCOPE -> gyro = e.values.clone()
            Sensor.TYPE_MAGNETIC_FIELD -> mag = e.values.clone()
            Sensor.TYPE_ROTATION_VECTOR -> {
                SensorManager.getRotationMatrixFromVector(rotM, e.values)
                SensorManager.getOrientation(rotM, ori)
                haveRot = true
            }
            Sensor.TYPE_LIGHT -> light = e.values[0]
            Sensor.TYPE_PROXIMITY -> prox = e.values[0]
            Sensor.TYPE_PRESSURE -> pressure = e.values[0]
            Sensor.TYPE_AMBIENT_TEMPERATURE -> ambientTemp = e.values[0]
            Sensor.TYPE_RELATIVE_HUMIDITY -> humidity = e.values[0]
            else -> {
                if (e.sensor.stringType?.contains("hall", true) == true) hall = e.values[0]
            }
        }
    }

    private fun mag3(v: FloatArray): Double =
        sqrt((v[0] * v[0] + v[1] * v[1] + v[2] * v[2]).toDouble())

    private fun frame(): HashMap<String, Any> {
        val f = HashMap<String, Any>()

        accel?.let {
            f["ax"] = it[0].toDouble(); f["ay"] = it[1].toDouble(); f["az"] = it[2].toDouble()
            f["amag"] = mag3(it); f["jerk"] = jerk
        }
        linear?.let {
            f["lax"] = it[0].toDouble(); f["lay"] = it[1].toDouble(); f["laz"] = it[2].toDouble()
            f["lmag"] = mag3(it); f["menergy"] = motionEnergy
        }
        gravity?.let { g ->
            f["grx"] = g[0].toDouble(); f["gry"] = g[1].toDouble(); f["grz"] = g[2].toDouble()
            val gm = mag3(g)
            if (gm > 0) f["incl"] = Math.toDegrees(acos((g[2] / gm).toDouble().coerceIn(-1.0, 1.0)))
            f["pose"] = pose(g)
        }
        gyro?.let {
            f["gx"] = it[0].toDouble(); f["gy"] = it[1].toDouble(); f["gz"] = it[2].toDouble()
            f["gmag"] = mag3(it)
        }
        mag?.let { b ->
            f["mx"] = b[0].toDouble(); f["my"] = b[1].toDouble(); f["mz"] = b[2].toDouble()
            f["bmag"] = mag3(b)
            gravity?.let { g ->
                // magnetic dip = angle between field and horizontal plane
                val dot = (b[0] * g[0] + b[1] * g[1] + b[2] * g[2]).toDouble()
                val denom = mag3(b) * mag3(g)
                if (denom > 0) f["dip"] = 90.0 - Math.toDegrees(acos((dot / denom).coerceIn(-1.0, 1.0)))
            }
        }
        if (haveRot) {
            // Tilt-compensated heading that does NOT pole-flip when vertical.
            // world = R · device (world is East-North-Up). Pick whichever device
            // axis — top edge (+Y) or back/camera (−Z) — is most horizontal, and
            // take its compass bearing. This stays continuous through vertical.
            val topE = rotM[1]; val topN = rotM[4]; val topU = rotM[7]
            val backE = -rotM[2]; val backN = -rotM[5]; val backU = -rotM[8]
            val he: Float; val hn: Float
            if (abs(topU) <= abs(backU)) { he = topE; hn = topN } else { he = backE; hn = backN }
            var az = Math.toDegrees(atan2(he.toDouble(), hn.toDouble())); if (az < 0) az += 360.0
            f["compass"] = az
            f["cardinal"] = cardinal(az)
            f["pitch"] = Math.toDegrees(ori[1].toDouble())
            f["roll"] = Math.toDegrees(ori[2].toDouble())
        }
        light?.let { f["lux"] = it.toDouble(); f["lightcat"] = lightCat(it) }
        prox?.let { f["prox"] = it.toDouble() }
        pressure?.let { p ->
            f["press"] = p.toDouble()
            val alt = SensorManager.getAltitude(SensorManager.PRESSURE_STANDARD_ATMOSPHERE, p).toDouble()
            f["alt"] = alt
            val now = SystemClock.elapsedRealtime()
            if (!lastAlt.isNaN() && lastAltT > 0) {
                val dt = (now - lastAltT) / 1000.0
                if (dt > 0.5) {
                    vspeed = (alt - lastAlt) / dt
                    floors += abs(alt - lastAlt) / 3.0
                    f["ptrend"] = if (alt - lastAlt > 0.3) "rising" else if (alt - lastAlt < -0.3) "falling" else "steady"
                    lastAlt = alt; lastAltT = now
                }
            } else { lastAlt = alt; lastAltT = now }
            f["vspeed"] = vspeed
            f["floors"] = floors
        }
        ambientTemp?.let { f["atemp"] = it.toDouble() }
        humidity?.let { f["humid"] = it.toDouble() }
        hall?.let { f["hall"] = if (it > 0) "field" else "none" }

        // fusion
        f["steps"] = stepCount
        f["cadence"] = cadenceStamps.size * 6 // 10s window → per minute
        f["motionstate"] = motionState()
        f["shakes"] = shakes
        if (accel != null) f["freefall"] = (f["amag"] as? Double ?: 9.81) < 2.0
        f["vibhz"] = vibHz
        f["jolt"] = jolt

        // heavy telemetry (recomputed ~1s, cached)
        val now = SystemClock.elapsedRealtime()
        if (now - lastHeavy > 800) {
            heavy = computeHeavy()
            lastHeavy = now
        }
        f.putAll(heavy)
        return f
    }

    private fun pose(g: FloatArray): String {
        val x = g[0]; val y = g[1]; val z = g[2]
        if (z > 8.5) return "face up"
        if (z < -8.5) return "face down"
        return if (abs(x) > abs(y)) { if (x > 0) "landscape L" else "landscape R" } else { if (y > 0) "portrait" else "upside down" }
    }

    private fun cardinal(a: Double): String {
        val dirs = arrayOf("N", "NE", "E", "SE", "S", "SW", "W", "NW")
        return dirs[((a + 22.5) / 45.0).toInt() % 8]
    }

    private fun lightCat(l: Float): String = when {
        l < 10 -> "dark"; l < 50 -> "dim"; l < 300 -> "indoor"; l < 1000 -> "bright"; l < 10000 -> "overcast"; else -> "sunlight"
    }

    // Honest motion-energy tiers. This is a motion-intensity / jolt classifier,
    // not a gait classifier — it reports how much energy is in the movement,
    // never a fabricated "walking/running" it can't actually distinguish.
    private fun motionState(): String {
        val e = motionEnergy
        return when {
            e < 0.3 -> "still"
            e < 2.0 -> "moving"
            e < 6.0 -> "active"
            else -> "impact"
        }
    }

    private fun computeHeavy(): HashMap<String, Any> {
        val m = HashMap<String, Any>()
        // CPU (app) + per-core freq
        try {
            val cpu = Process.getElapsedCpuTime()
            val wall = SystemClock.elapsedRealtime()
            if (lastCpuWall > 0) {
                val dCpu = cpu - lastCpuTime
                val dWall = wall - lastCpuWall
                if (dWall > 0) m["appcpu"] = (100.0 * dCpu / (dWall * ncores)).coerceIn(0.0, 100.0)
            }
            lastCpuTime = cpu; lastCpuWall = wall
            m["cores"] = ncores
            val freqs = ArrayList<Int>()
            for (c in 0 until ncores) {
                try {
                    val t = File("/sys/devices/system/cpu/cpu$c/cpufreq/scaling_cur_freq").readText().trim().toInt()
                    freqs.add(t / 1000)
                } catch (_: Exception) { freqs.add(-1) }
            }
            m["corefreq"] = freqs
        } catch (_: Exception) {}
        // Try device-wide CPU from /proc/stat (usually blocked → absent)
        try {
            RandomAccessFile("/proc/stat", "r").use { raf ->
                val line = raf.readLine()
                if (line != null && line.startsWith("cpu ")) {
                    // if readable, parse (rare on modern Android); otherwise skipped by catch
                }
            }
        } catch (_: Exception) {}
        // RAM
        try {
            val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val mi = ActivityManager.MemoryInfo(); am.getMemoryInfo(mi)
            m["ramtotal"] = mi.totalMem / 1048576.0
            m["ramavail"] = mi.availMem / 1048576.0
            m["ramused"] = (mi.totalMem - mi.availMem) / 1048576.0
            m["lowmem"] = mi.lowMemory
        } catch (_: Exception) {}
        try {
            val mi = Debug.MemoryInfo(); Debug.getMemoryInfo(mi)
            m["apppss"] = mi.totalPss / 1024.0
        } catch (_: Exception) {}
        // Storage
        try {
            val s = StatFs(Environment.getDataDirectory().path)
            m["storfree"] = s.availableBytes / 1.0e9
            m["stortotal"] = s.totalBytes / 1.0e9
        } catch (_: Exception) {}
        try { m["uptime"] = SystemClock.elapsedRealtime() } catch (_: Exception) {}
        // Battery
        try {
            val bm = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
            val cur = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CURRENT_NOW)
            if (cur != Int.MIN_VALUE && cur != 0) m["batcur"] = cur
            val avg = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CURRENT_AVERAGE)
            if (avg != Int.MIN_VALUE && avg != 0) m["batcuravg"] = avg
            val cc = bm.getLongProperty(BatteryManager.BATTERY_PROPERTY_CHARGE_COUNTER)
            if (cc > 0) m["chargecounter"] = cc / 1000.0 // µAh
            val cap = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
            if (cap in 0..100) m["batpct"] = cap
            if (Build.VERSION.SDK_INT >= 28) {
                val ctr = bm.computeChargeTimeRemaining()
                if (ctr > 0) m["chargetime"] = ctr / 60000.0 // minutes
            }
            val it2 = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            if (it2 != null) {
                val temp = it2.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, -1)
                val volt = it2.getIntExtra(BatteryManager.EXTRA_VOLTAGE, -1)
                if (temp > 0) m["battemp"] = temp / 10.0
                if (volt > 0) m["batvolt"] = volt / 1000.0
                val st = it2.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
                m["batcharging"] = (st == BatteryManager.BATTERY_STATUS_CHARGING || st == BatteryManager.BATTERY_STATUS_FULL)
                m["bathealth"] = healthStr(it2.getIntExtra(BatteryManager.EXTRA_HEALTH, 0))
                it2.getStringExtra(BatteryManager.EXTRA_TECHNOLOGY)?.let { t -> m["battech"] = t }
                m["batplug"] = plugStr(it2.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0))
                try {
                    val cyc = it2.getIntExtra("android.os.extra.CYCLE_COUNT", -1)
                    if (cyc >= 0) m["batcycles"] = cyc
                } catch (_: Exception) {}
                if (temp > 0 && volt > 0 && cur != Int.MIN_VALUE) {
                    m["batpower"] = abs(volt / 1000.0 * (cur / 1000.0) / 1000.0) // W
                }
            }
        } catch (_: Exception) {}
        // Thermal
        try {
            if (Build.VERSION.SDK_INT >= 29) {
                val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                m["thermstatus"] = pm.currentThermalStatus
                if (Build.VERSION.SDK_INT >= 30) {
                    val hr = pm.getThermalHeadroom(10)
                    if (!hr.isNaN()) m["thermheadroom"] = hr.toDouble()
                }
            }
        } catch (_: Exception) {}
        try {
            var maxT = -1000.0
            for (z in 0 until 40) {
                try {
                    val dir = File("/sys/class/thermal/thermal_zone$z")
                    if (!dir.exists()) break
                    val t = File(dir, "temp").readText().trim().toDouble()
                    val tc = if (abs(t) > 1000) t / 1000.0 else t
                    val type = try { File(dir, "type").readText().trim() } catch (_: Exception) { "" }
                    if (tc > maxT) maxT = tc
                    val lt = type.lowercase()
                    if (lt.contains("cpu") && !m.containsKey("thermcpu")) m["thermcpu"] = tc
                    if (lt.contains("batt") && !m.containsKey("thermbatt")) m["thermbatt"] = tc
                    if ((lt.contains("skin") || lt.contains("ambient")) && !m.containsKey("thermskin")) m["thermskin"] = tc
                    if (lt.contains("gpu") && !m.containsKey("thermgpu")) m["thermgpu"] = tc
                } catch (_: Exception) {}
            }
            if (maxT > -1000.0) m["thermmax"] = maxT
        } catch (_: Exception) {}
        // Network
        try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val net = cm.activeNetwork
            val cap = if (net != null) cm.getNetworkCapabilities(net) else null
            m["online"] = cap != null
            if (cap != null) {
                m["nettype"] = when {
                    cap.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
                    cap.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
                    cap.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
                    cap.hasTransport(NetworkCapabilities.TRANSPORT_VPN) -> "vpn"
                    else -> "other"
                }
                m["metered"] = !cap.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
                m["vpn"] = cap.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
                m["linkdown"] = cap.linkDownstreamBandwidthKbps
                m["linkup"] = cap.linkUpstreamBandwidthKbps
            }
            val rx = TrafficStats.getTotalRxBytes()
            val tx = TrafficStats.getTotalTxBytes()
            val now = SystemClock.elapsedRealtime()
            if (lastNetT > 0 && rx >= 0 && tx >= 0) {
                val dt = (now - lastNetT) / 1000.0
                if (dt > 0) {
                    m["downkbs"] = (rx - lastRx) / 1024.0 / dt
                    m["upkbs"] = (tx - lastTx) / 1024.0 / dt
                }
            }
            lastRx = rx; lastTx = tx; lastNetT = now
            if (rx >= 0) m["rxmb"] = rx / 1048576.0
            if (tx >= 0) m["txmb"] = tx / 1048576.0
        } catch (_: Exception) {}
        // Display
        try {
            val d = windowManager.defaultDisplay
            m["refresh"] = d.refreshRate.toDouble()
        } catch (_: Exception) {}
        try {
            val dm = resources.displayMetrics
            m["screenw"] = dm.widthPixels
            m["screenh"] = dm.heightPixels
            m["density"] = dm.density.toDouble()
        } catch (_: Exception) {}
        // Audio
        try {
            val au = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val mv = au.getStreamVolume(AudioManager.STREAM_MUSIC)
            val mmax = au.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
            if (mmax > 0) m["volmedia"] = (100.0 * mv / mmax)
            val rv = au.getStreamVolume(AudioManager.STREAM_RING)
            val rmax = au.getStreamMaxVolume(AudioManager.STREAM_RING)
            if (rmax > 0) m["volring"] = (100.0 * rv / rmax)
            m["ringer"] = when (au.ringerMode) {
                AudioManager.RINGER_MODE_SILENT -> "silent"
                AudioManager.RINGER_MODE_VIBRATE -> "vibrate"
                else -> "normal"
            }
            m["musicactive"] = au.isMusicActive
            m["audioout"] = when {
                au.isBluetoothA2dpOn -> "bluetooth"
                au.isWiredHeadsetOn -> "wired"
                else -> "speaker"
            }
        } catch (_: Exception) {}
        // Sensor health: [name, present, ageMs since last event, accuracy -1..3]
        try {
            val now = SystemClock.elapsedRealtime()
            val sh = HashMap<String, Any>()
            fun put(key: String, type: Int) {
                val nm = sensorNames[type]
                val present = nm != null
                val age = if (present) now - (lastSeen[type] ?: 0L) else -1L
                sh[key] = listOf(nm ?: "", present, age, accuracyMap[type] ?: -1)
            }
            put("accel", Sensor.TYPE_ACCELEROMETER)
            put("lin", Sensor.TYPE_LINEAR_ACCELERATION)
            put("grav", Sensor.TYPE_GRAVITY)
            put("gyro", Sensor.TYPE_GYROSCOPE)
            put("mag", Sensor.TYPE_MAGNETIC_FIELD)
            put("rot", Sensor.TYPE_ROTATION_VECTOR)
            put("light", Sensor.TYPE_LIGHT)
            put("prox", Sensor.TYPE_PROXIMITY)
            put("press", Sensor.TYPE_PRESSURE)
            put("temp", Sensor.TYPE_AMBIENT_TEMPERATURE)
            put("humid", Sensor.TYPE_RELATIVE_HUMIDITY)
            m["sensors"] = sh
        } catch (_: Exception) {}
        // Full sensor inventory — every sensor the device exposes, with its spec
        // and whether we could register it (listed vs actually reachable).
        try {
            val mgr = sm
            if (mgr != null) {
                val now = SystemClock.elapsedRealtime()
                val inv = ArrayList<List<Any>>()
                for (s in mgr.getSensorList(Sensor.TYPE_ALL)) {
                    val age = lastSeenName[s.name]?.let { now - it } ?: -1L
                    inv.add(
                        listOf(
                            s.type,
                            s.name,
                            s.vendor,
                            s.stringType ?: "",
                            s.power.toDouble(),
                            s.resolution.toDouble(),
                            s.maximumRange.toDouble(),
                            s.minDelay,
                            s.reportingMode,
                            s.isWakeUpSensor,
                            registeredOkName[s.name] ?: false,
                            age,
                            gateFor(s.type)
                        )
                    )
                }
                m["inventory"] = inv
            }
        } catch (_: Exception) {}
        return m
    }

    private fun healthStr(h: Int): String = when (h) {
        BatteryManager.BATTERY_HEALTH_GOOD -> "good"
        BatteryManager.BATTERY_HEALTH_OVERHEAT -> "overheat"
        BatteryManager.BATTERY_HEALTH_DEAD -> "dead"
        BatteryManager.BATTERY_HEALTH_OVER_VOLTAGE -> "over-voltage"
        BatteryManager.BATTERY_HEALTH_COLD -> "cold"
        else -> "unknown"
    }

    private fun plugStr(p: Int): String = when (p) {
        BatteryManager.BATTERY_PLUGGED_AC -> "AC"
        BatteryManager.BATTERY_PLUGGED_USB -> "USB"
        BatteryManager.BATTERY_PLUGGED_WIRELESS -> "wireless"
        0 -> "unplugged"
        else -> "plugged"
    }

    override fun onDestroy() {
        try { sm?.unregisterListener(this) } catch (_: Exception) {}
        handler.removeCallbacks(emitter)
        super.onDestroy()
    }
}
