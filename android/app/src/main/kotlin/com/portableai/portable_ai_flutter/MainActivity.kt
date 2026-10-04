package com.portableai.portable_ai_flutter

import android.annotation.SuppressLint
import android.app.ActivityManager
import android.bluetooth.BluetoothManager
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import android.hardware.GeomagneticField
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.hardware.TriggerEvent
import android.hardware.TriggerEventListener
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CameraMetadata
import android.location.GnssStatus
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.VibrationEffect
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.TrafficStats
import android.net.wifi.WifiManager
import android.nfc.NfcAdapter
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
import android.os.Vibrator
import android.telephony.TelephonyManager
import android.view.InputDevice
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.RandomAccessFile
import kotlin.math.abs
import kotlin.math.acos
import kotlin.math.atan2
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.sqrt

/// Native sensor + telemetry hub. Registers every available sensor at the
/// fastest rate and streams a combined frame (~60fps) over an EventChannel.
/// Everything is a real reading or a real derivation of one; anything the
/// device/OS does not expose is simply absent from the frame, so the UI shows
/// "no socket" — never a fabricated value.
class MainActivity : FlutterActivity(), SensorEventListener {
    private val streamName = "aether/stream"
    private var sink: EventChannel.EventSink? = null

    // Runtime-permission request bridge (aether/perms). One request in flight.
    private var pendingPerm: MethodChannel.Result? = null
    private val permCode = 9017

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
    private var cct: FloatArray? = null // Samsung color-temp sensor raw channels
    private var lightIr: Float? = null // Samsung IR illuminance (raw)
    private val rotM = FloatArray(9)
    private val ori = FloatArray(3)
    private var headTop = true // which device axis the heading currently tracks (hysteresis)

    // ── event sensors (fire-and-flash): count + last-fired + whether armed ──
    private val eventCount = HashMap<String, Int>()
    private val eventLast = HashMap<String, Long>()
    private val eventArmed = HashMap<String, Boolean>()
    private var smSensor: Sensor? = null
    private val smTrigger = object : TriggerEventListener() {
        override fun onTrigger(e: TriggerEvent?) {
            bumpEvent("sigmotion")
            // one-shot trigger sensors must be re-armed after each fire
            try { smSensor?.let { sm?.requestTriggerSensor(this, it) } } catch (_: Exception) {}
        }
    }

    // ── live control-channel streams (aether/ctl): mic · location/GNSS · torch · haptics ──
    @Volatile private var micRunning = false
    private var audioRecord: AudioRecord? = null
    private var micThread: Thread? = null
    @Volatile private var micDb = -120.0
    @Volatile private var micPeak = -120.0
    @Volatile private var micWave: FloatArray? = null

    private var locRunning = false
    private var lastFix: Location? = null
    private var gnssCb: GnssStatus.Callback? = null
    @Volatile private var satUsed = 0
    @Volatile private var satSeen = 0
    // per satellite: [azimuthDeg, elevationDeg, cn0DbHz, constellationType, usedInFix(0/1)]
    @Volatile private var satArr: ArrayList<FloatArray>? = null
    private var qnh = Double.NaN // sea-level pressure (hPa) calibrated from the GPS altitude

    private var torchOn = false
    private var torchCamId: String? = null

    // BLE nearby scanner: addr -> [rssi, lastSeenMs]; names from advertisements.
    private var bleRunning = false
    private var bleScanner: BluetoothLeScanner? = null
    private val bleSeen = HashMap<String, FloatArray>()
    private val bleName = HashMap<String, String>()
    private val bleScanCb = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult?) {
            val r = result ?: return
            try {
                val addr = r.device?.address ?: return
                bleSeen[addr] = floatArrayOf(r.rssi.toFloat(), SystemClock.elapsedRealtime().toFloat())
                val nm = (try { r.scanRecord?.deviceName } catch (_: Exception) { null }) ?: ""
                if (nm.isNotEmpty()) bleName[addr] = nm
            } catch (_: Exception) {}
        }
    }

    private val locListener = object : LocationListener {
        override fun onLocationChanged(loc: Location) { lastFix = loc }
        override fun onProviderEnabled(provider: String) {}
        override fun onProviderDisabled(provider: String) {}
        @Deprecated("deprecated in API 29")
        override fun onStatusChanged(provider: String?, status: Int, extras: android.os.Bundle?) {}
    }

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
    private var lastRadio = 0L
    private var radioCache = HashMap<String, Any>()
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
                    try { smSensor?.let { sm?.cancelTriggerSensor(smTrigger, it) } } catch (_: Exception) {}
                    stopMic()
                    stopLoc()
                    stopBle()
                    sink = null
                }
            })
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "aether/index")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "full" -> try { result.success(buildIndex()) } catch (e: Exception) { result.error("INDEX", e.message, null) }
                    "caps" -> try { result.success(buildCaps()) } catch (e: Exception) { result.error("CAPS", e.message, null) }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "aether/perms")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> {
                        val perms = call.argument<List<String>>("perms") ?: emptyList()
                        val m = HashMap<String, Boolean>()
                        for (p in perms) {
                            m[p] = try {
                                ContextCompat.checkSelfPermission(this, p) == PackageManager.PERMISSION_GRANTED
                            } catch (_: Exception) { false }
                        }
                        result.success(m)
                    }
                    "request" -> {
                        val perms = (call.argument<List<String>>("perms") ?: emptyList()).toTypedArray()
                        if (perms.isEmpty()) { result.success(HashMap<String, Boolean>()); return@setMethodCallHandler }
                        if (pendingPerm != null) {
                            // a request is already in flight — just report current status
                            val m = HashMap<String, Boolean>()
                            for (p in perms) m[p] = try {
                                ContextCompat.checkSelfPermission(this, p) == PackageManager.PERMISSION_GRANTED
                            } catch (_: Exception) { false }
                            result.success(m); return@setMethodCallHandler
                        }
                        pendingPerm = result
                        try {
                            ActivityCompat.requestPermissions(this, perms, permCode)
                        } catch (e: Exception) {
                            pendingPerm = null
                            result.error("PERM", e.message, null)
                        }
                    }
                    "openSettings" -> {
                        result.success(
                            try {
                                startActivity(
                                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
                                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                                true
                            } catch (_: Exception) { false })
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "aether/ctl")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "micStart" -> result.success(startMic())
                    "micStop" -> { stopMic(); result.success(true) }
                    "locStart" -> result.success(startLoc())
                    "locStop" -> { stopLoc(); result.success(true) }
                    "bleStart" -> result.success(startBle())
                    "bleStop" -> { stopBle(); result.success(true) }
                    "torch" -> result.success(setTorch(call.argument<Boolean>("on") ?: false))
                    "buzz" -> { buzz(call.argument<Int>("ms") ?: 20); result.success(true) }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == permCode) {
            val m = HashMap<String, Boolean>()
            for (i in permissions.indices) {
                m[permissions[i]] = grantResults.getOrNull(i) == PackageManager.PERMISSION_GRANTED
            }
            pendingPerm?.success(m)
            pendingPerm = null
        }
    }

    private fun bumpEvent(label: String) {
        eventCount[label] = (eventCount[label] ?: 0) + 1
        eventLast[label] = SystemClock.elapsedRealtime()
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
        // Event sensors: mark which on-change ones we can actually listen to, and
        // arm the significant-motion trigger (one-shot sensors use the trigger API,
        // not registerListener). Honest armed flags — a lamp lights only if live.
        try {
            for (s in mgr.getSensorList(Sensor.TYPE_ALL)) {
                val st = s.stringType ?: ""
                val ok = registeredOkName[s.name] ?: false
                when {
                    st.contains("tilt", true) -> eventArmed["tilt"] = ok
                    st.endsWith("step_detector", true) -> eventArmed["stepdet"] = ok
                }
            }
            smSensor = mgr.getDefaultSensor(Sensor.TYPE_SIGNIFICANT_MOTION)
            smSensor?.let { eventArmed["sigmotion"] = sm?.requestTriggerSensor(smTrigger, it) ?: false }
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
                val st = e.sensor.stringType ?: ""
                when {
                    st.contains("hall", true) -> hall = e.values[0]
                    st.contains("light_cct", true) -> cct = e.values.clone()
                    st.contains("light_ir", true) -> lightIr = e.values[0]
                    st.contains("tilt", true) -> bumpEvent("tilt")
                    st.endsWith("step_detector", true) -> bumpEvent("stepdet")
                }
            }
        }
    }

    private fun mag3(v: FloatArray): Double =
        sqrt((v[0] * v[0] + v[1] * v[1] + v[2] * v[2]).toDouble())

    private fun frame(): HashMap<String, Any> {
        val f = HashMap<String, Any>()

        // Geomagnetic model (needs a GPS fix): declination for TRUE north, plus
        // the local field strength + inclination for the magnetometer / detector.
        var declination = 0.0
        var geoFieldUt = 0.0
        var haveGeo = false
        lastFix?.let { loc ->
            try {
                val gf = GeomagneticField(
                    loc.latitude.toFloat(), loc.longitude.toFloat(),
                    (if (loc.hasAltitude()) loc.altitude else 0.0).toFloat(),
                    System.currentTimeMillis())
                declination = gf.declination.toDouble()
                geoFieldUt = gf.fieldStrength.toDouble() / 1000.0 // nT → µT
                f["geoDecl"] = declination
                f["geoField"] = geoFieldUt
                f["geoIncl"] = gf.inclination.toDouble()
                haveGeo = true
            } catch (_: Exception) {}
        }

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
            // Cross-check measured field against the geomagnetic model: a large
            // deviation = local ferrous/magnetic interference distorting the heading.
            if (haveGeo && geoFieldUt > 0) {
                val meas = mag3(b)
                val devPct = abs(meas - geoFieldUt) / geoFieldUt * 100.0
                f["magDev"] = meas - geoFieldUt
                f["magDevPct"] = devPct
                f["headingTrust"] = if (devPct < 12) "good" else if (devPct < 30) "fair" else "poor"
            }
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
            // Hysteresis: stay on the current axis until the other is clearly more
            // horizontal (by 0.15), so the heading doesn't snap at the crossover.
            if (headTop) { if (abs(backU) < abs(topU) - 0.15f) headTop = false }
            else { if (abs(topU) < abs(backU) - 0.15f) headTop = true }
            val he: Float; val hn: Float
            if (headTop) { he = topE; hn = topN } else { he = backE; hn = backN }
            var az = Math.toDegrees(atan2(he.toDouble(), hn.toDouble())); if (az < 0) az += 360.0
            f["compass"] = az
            f["cardinal"] = cardinal(az)
            if (haveGeo) {
                val tru = (((az + declination) % 360) + 360) % 360
                f["trueHeading"] = tru
                f["cardinalTrue"] = cardinal(tru)
            }
            f["pitch"] = Math.toDegrees(ori[1].toDouble())
            f["roll"] = Math.toDegrees(ori[2].toDouble())
        }
        light?.let { f["lux"] = it.toDouble(); f["lightcat"] = lightCat(it) }
        prox?.let { f["prox"] = it.toDouble() }
        pressure?.let { p ->
            f["press"] = p.toDouble()
            val alt = SensorManager.getAltitude(SensorManager.PRESSURE_STANDARD_ATMOSPHERE, p).toDouble()
            f["alt"] = alt
            // GPS-anchored altitude: solve sea-level pressure (QNH) from a good GPS
            // fix, then take barometric altitude against it — absolute-accurate AND
            // baro-fast/stable, instead of the 1013.25 hPa standard-atmosphere guess.
            lastFix?.let { loc ->
                if (loc.hasAltitude() && (!loc.hasAccuracy() || loc.accuracy < 40f)) {
                    qnh = p.toDouble() / Math.pow(1.0 - loc.altitude / 44330.0, 5.255)
                }
            }
            if (!qnh.isNaN()) {
                f["seaLevel"] = qnh
                f["altCal"] = 44330.0 * (1.0 - Math.pow(p.toDouble() / qnh, 1.0 / 5.255))
            }
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
        cct?.let {
            f["cct0"] = it[0].toDouble()
            if (it.size > 1) f["cct1"] = it[1].toDouble()
        }
        lightIr?.let { f["lightir"] = it.toDouble() }

        // event sensors: [armed, count, ageMs] — emitted every frame so the lamp
        // can flash the moment one fires (age small) and go quiet between.
        val evNow = SystemClock.elapsedRealtime()
        val ev = HashMap<String, Any>()
        for (label in listOf("tilt", "sigmotion", "stepdet")) {
            val last = eventLast[label] ?: 0L
            val age = if (last > 0) evNow - last else -1L
            ev[label] = listOf(eventArmed[label] ?: false, eventCount[label] ?: 0, age)
        }
        f["events"] = ev

        // live control-channel streams (only when running / fixed — never faked)
        if (micRunning) {
            f["micDb"] = micDb
            f["micPeak"] = micPeak
            micWave?.let { w -> f["micWave"] = w.map { s -> s.toDouble() } }
        }
        lastFix?.let { loc ->
            f["lat"] = loc.latitude
            f["lon"] = loc.longitude
            if (loc.hasAltitude()) f["gpsAlt"] = loc.altitude
            if (loc.hasSpeed()) f["gpsSpeed"] = loc.speed.toDouble()
            if (loc.hasBearing()) f["gpsBearing"] = loc.bearing.toDouble()
            if (loc.hasAccuracy()) f["gpsAcc"] = loc.accuracy.toDouble()
            f["gpsProvider"] = loc.provider ?: ""
        }
        if (locRunning) {
            f["satUsed"] = satUsed
            f["satSeen"] = satSeen
            satArr?.let { arr -> f["sats"] = arr.map { s -> s.map { v -> v.toDouble() } } }
            // Indoor/outdoor inference (GNSS × optical). An inference, labeled so.
            val acc = lastFix?.accuracy ?: 999f
            val outdoor = satUsed >= 5 || acc < 15f
            val dim = (light ?: 1000f) < 30f
            f["envContext"] = if (outdoor) "outdoor" else if (dim && satUsed < 3) "indoor" else "transition"
        }

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
        if (now - lastRadio > 400) {
            radioCache = computeRadio()
            lastRadio = now
        }
        f.putAll(heavy)
        f.putAll(radioCache)
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

    // Radio & Nearby on a faster ~400ms cadence so the radar/signal feel live.
    private fun computeRadio(): HashMap<String, Any> {
        val m = HashMap<String, Any>()
        try {
            val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            @Suppress("DEPRECATION") val info = wm.connectionInfo
            if (info != null) {
                val rssi = info.rssi
                if (rssi in -100..0) {
                    m["wifiRssi"] = rssi
                    m["wifiSpeed"] = info.linkSpeed
                    val freq = info.frequency
                    m["wifiFreq"] = freq
                    m["wifiBand"] = if (freq >= 5955) "6 GHz" else if (freq >= 4900) "5 GHz" else "2.4 GHz"
                }
            }
            if (ContextCompat.checkSelfPermission(this, android.Manifest.permission.NEARBY_WIFI_DEVICES)
                == PackageManager.PERMISSION_GRANTED) {
                try {
                    @Suppress("DEPRECATION") val res = wm.scanResults
                    val aps = ArrayList<List<Any>>()
                    for (r in res.sortedByDescending { it.level }.take(16)) {
                        val ssid = try { r.SSID ?: "" } catch (_: Exception) { "" }
                        aps.add(listOf(r.level, r.frequency, if (ssid.isEmpty()) "(hidden)" else ssid))
                    }
                    m["wifiAps"] = aps
                    try { @Suppress("DEPRECATION") wm.startScan() } catch (_: Exception) {}
                } catch (_: Exception) {}
            }
        } catch (_: Exception) {}
        try {
            if (Build.VERSION.SDK_INT >= 29 &&
                ContextCompat.checkSelfPermission(this, android.Manifest.permission.READ_PHONE_STATE)
                == PackageManager.PERMISSION_GRANTED) {
                val tm = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
                val ss = tm.signalStrength
                if (ss != null) {
                    val cs = ss.cellSignalStrengths
                    if (cs.isNotEmpty()) {
                        m["cellDbm"] = cs[0].dbm
                        m["cellLevel"] = cs[0].level
                    }
                }
                m["cellType"] = cellTypeName(tm.dataNetworkType)
            }
        } catch (_: Exception) {}
        try {
            if (bleRunning) {
                val now = SystemClock.elapsedRealtime()
                val list = ArrayList<List<Any>>()
                val iter = bleSeen.entries.iterator()
                while (iter.hasNext()) {
                    val e = iter.next()
                    val age = now - e.value[1].toLong()
                    if (age > 12000) { iter.remove(); continue }
                    list.add(listOf(e.value[0].toInt(), bleName[e.key] ?: ""))
                }
                list.sortByDescending { it[0] as Int }
                m["bleList"] = ArrayList(list.take(20))
                m["bleCount"] = list.size
            }
        } catch (_: Exception) {}
        return m
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
        // Radio & Nearby now runs on its own faster ~400ms cadence (computeRadio).
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

    // ── Wider capability index: probe every subsystem/API for reachability ──
    // status: available | needs-perm | command | sealed | unsupported
    private fun idxEntry(
        label: String, status: String, detail: String = "", perm: String = "", api: String = ""
    ): HashMap<String, String> =
        hashMapOf("label" to label, "status" to status, "detail" to detail, "perm" to perm, "api" to api)

    private fun feat(f: String): Boolean =
        try { packageManager.hasSystemFeature(f) } catch (_: Exception) { false }

    // ── live control-channel implementations ──
    @SuppressLint("MissingPermission")
    private fun startMic(): Boolean {
        if (micRunning) return true
        if (ContextCompat.checkSelfPermission(this, android.Manifest.permission.RECORD_AUDIO)
            != PackageManager.PERMISSION_GRANTED) return false
        try {
            val rate = 48000
            val minBuf = AudioRecord.getMinBufferSize(rate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
            if (minBuf <= 0) return false
            val ar = AudioRecord(MediaRecorder.AudioSource.MIC, rate,
                AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, max(minBuf, rate / 5))
            if (ar.state != AudioRecord.STATE_INITIALIZED) { ar.release(); return false }
            audioRecord = ar
            micRunning = true
            ar.startRecording()
            val t = Thread {
                val data = ShortArray(1024)
                while (micRunning) {
                    val n = try { ar.read(data, 0, data.size) } catch (_: Exception) { -1 }
                    if (n <= 0) continue
                    var sumSq = 0.0
                    var peak = 0
                    for (i in 0 until n) {
                        val v = data[i].toInt()
                        sumSq += (v.toDouble() * v)
                        val a = abs(v)
                        if (a > peak) peak = a
                    }
                    val rms = sqrt(sumSq / n)
                    micDb = if (rms > 0) (20.0 * log10(rms / 32768.0)).coerceIn(-120.0, 0.0) else -120.0
                    micPeak = if (peak > 0) (20.0 * log10(peak / 32768.0)).coerceIn(-120.0, 0.0) else -120.0
                    val pts = 64
                    val wave = FloatArray(pts)
                    val step = max(1, n / pts)
                    var wi = 0; var i = 0
                    while (wi < pts && i < n) { wave[wi] = data[i].toInt() / 32768.0f; wi++; i += step }
                    micWave = wave
                }
            }
            micThread = t
            t.isDaemon = true
            t.start()
            return true
        } catch (_: Exception) {
            micRunning = false
            try { audioRecord?.release() } catch (_: Exception) {}
            audioRecord = null
            return false
        }
    }

    private fun stopMic() {
        micRunning = false
        try { micThread?.join(200) } catch (_: Exception) {}
        micThread = null
        try { audioRecord?.stop() } catch (_: Exception) {}
        try { audioRecord?.release() } catch (_: Exception) {}
        audioRecord = null
        micWave = null
        micDb = -120.0; micPeak = -120.0
    }

    @SuppressLint("MissingPermission")
    private fun startLoc(): Boolean {
        if (locRunning) return true
        if (ContextCompat.checkSelfPermission(this, android.Manifest.permission.ACCESS_FINE_LOCATION)
            != PackageManager.PERMISSION_GRANTED) return false
        try {
            val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
            try {
                lm.requestLocationUpdates(LocationManager.GPS_PROVIDER, 1000L, 0f, locListener, Looper.getMainLooper())
            } catch (_: Exception) {}
            try {
                lastFix = lm.getLastKnownLocation(LocationManager.GPS_PROVIDER)
                    ?: lm.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
            } catch (_: Exception) {}
            if (Build.VERSION.SDK_INT >= 24) {
                val cb = object : GnssStatus.Callback() {
                    override fun onSatelliteStatusChanged(status: GnssStatus) {
                        try {
                            val n = status.satelliteCount
                            var used = 0
                            val arr = ArrayList<FloatArray>(n)
                            for (i in 0 until n) {
                                val u = if (status.usedInFix(i)) 1f else 0f
                                if (u > 0f) used++
                                arr.add(floatArrayOf(
                                    status.getAzimuthDegrees(i),
                                    status.getElevationDegrees(i),
                                    status.getCn0DbHz(i),
                                    status.getConstellationType(i).toFloat(),
                                    u))
                            }
                            satSeen = n; satUsed = used; satArr = arr
                        } catch (_: Exception) {}
                    }
                }
                gnssCb = cb
                try { lm.registerGnssStatusCallback(cb, handler) } catch (_: Exception) {}
            }
            locRunning = true
            return true
        } catch (_: Exception) { return false }
    }

    private fun stopLoc() {
        locRunning = false
        try {
            val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
            try { lm.removeUpdates(locListener) } catch (_: Exception) {}
            if (Build.VERSION.SDK_INT >= 24) gnssCb?.let { cb ->
                try { lm.unregisterGnssStatusCallback(cb) } catch (_: Exception) {}
            }
        } catch (_: Exception) {}
        gnssCb = null
        satArr = null; satSeen = 0; satUsed = 0
    }

    @SuppressLint("MissingPermission")
    private fun startBle(): Boolean {
        if (bleRunning) return true
        if (ContextCompat.checkSelfPermission(this, android.Manifest.permission.BLUETOOTH_SCAN)
            != PackageManager.PERMISSION_GRANTED) return false
        try {
            val bm = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
            val ad = bm.adapter ?: return false
            if (!ad.isEnabled) return false
            val sc = ad.bluetoothLeScanner ?: return false
            bleScanner = sc
            bleRunning = true
            sc.startScan(bleScanCb)
            return true
        } catch (_: Exception) {
            bleRunning = false
            return false
        }
    }

    @SuppressLint("MissingPermission")
    private fun stopBle() {
        if (!bleRunning && bleScanner == null) return
        bleRunning = false
        try { bleScanner?.stopScan(bleScanCb) } catch (_: Exception) {}
        bleScanner = null
        bleSeen.clear()
        bleName.clear()
    }

    private fun cellTypeName(t: Int): String = when (t) {
        TelephonyManager.NETWORK_TYPE_NR -> "5G NR"
        TelephonyManager.NETWORK_TYPE_LTE -> "LTE"
        TelephonyManager.NETWORK_TYPE_HSPAP, TelephonyManager.NETWORK_TYPE_HSPA,
        TelephonyManager.NETWORK_TYPE_HSDPA, TelephonyManager.NETWORK_TYPE_UMTS -> "3G"
        TelephonyManager.NETWORK_TYPE_EDGE, TelephonyManager.NETWORK_TYPE_GPRS -> "2G"
        TelephonyManager.NETWORK_TYPE_UNKNOWN -> "none"
        else -> "cell"
    }

    private fun setTorch(on: Boolean): Boolean {
        try {
            val cm = getSystemService(Context.CAMERA_SERVICE) as CameraManager
            if (torchCamId == null) {
                for (id in cm.cameraIdList) {
                    val c = cm.getCameraCharacteristics(id)
                    val has = c.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
                    if (has) {
                        torchCamId = id
                        if (c.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK) break
                    }
                }
            }
            val id = torchCamId ?: return false
            cm.setTorchMode(id, on)
            torchOn = on
            return true
        } catch (_: Exception) { return false }
    }

    private fun buzz(ms: Int) {
        try {
            val v = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            val dur = ms.toLong().coerceIn(1L, 1000L)
            if (Build.VERSION.SDK_INT >= 26) {
                v.vibrate(VibrationEffect.createOneShot(dur, VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION") v.vibrate(dur)
            }
        } catch (_: Exception) {}
    }

    // Flat presence/feature probe — the single source of truth the Dart
    // capability registry reads to decide each card's state. Facts only; the
    // Dart side merges these with live permission status and live stream health.
    private fun buildCaps(): HashMap<String, Any> {
        val c = HashMap<String, Any>()
        c["mic"] = feat("android.hardware.microphone")
        try {
            val cm = getSystemService(Context.CAMERA_SERVICE) as CameraManager
            c["cameraCount"] = cm.cameraIdList.size
            var back = 0; var front = 0
            for (id in cm.cameraIdList) {
                when (cm.getCameraCharacteristics(id).get(CameraCharacteristics.LENS_FACING)) {
                    CameraCharacteristics.LENS_FACING_BACK -> back++
                    CameraCharacteristics.LENS_FACING_FRONT -> front++
                }
            }
            c["cameraBack"] = back; c["cameraFront"] = front
        } catch (_: Exception) {}
        c["torch"] = feat("android.hardware.camera.flash")
        try {
            val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
            c["gps"] = lm.allProviders.contains(LocationManager.GPS_PROVIDER)
            c["locationProviders"] = lm.allProviders.joinToString(",")
            if (Build.VERSION.SDK_INT >= 28) c["gnssYear"] = lm.gnssYearOfHardware
        } catch (_: Exception) {}
        c["wifiRtt"] = feat("android.hardware.wifi.rtt")
        c["wifiAware"] = feat("android.hardware.wifi.aware")
        try {
            val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            c["wifi"] = true
            c["wifi5"] = wm.is5GHzBandSupported
            if (Build.VERSION.SDK_INT >= 30) c["wifi6"] = wm.is6GHzBandSupported
        } catch (_: Exception) {}
        c["cell"] = feat("android.hardware.telephony")
        try {
            val tm = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
            c["simState"] = tm.simState
        } catch (_: Exception) {}
        c["ble"] = feat("android.hardware.bluetooth_le")
        c["uwb"] = feat("android.hardware.uwb")
        try {
            val nfc = NfcAdapter.getDefaultAdapter(this)
            c["nfc"] = nfc != null
            c["nfcEnabled"] = nfc?.isEnabled ?: false
        } catch (_: Exception) {}
        c["nfcHce"] = feat("android.hardware.nfc.hce")
        try {
            val v = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            c["vibrator"] = v.hasVibrator()
            c["vibAmplitude"] = v.hasAmplitudeControl()
        } catch (_: Exception) {}
        c["bioFace"] = feat("android.hardware.biometrics.face")
        c["bioFingerprint"] = feat("android.hardware.fingerprint")
        c["bioIris"] = feat("android.hardware.biometrics.iris")
        try {
            var stylus = false
            for (id in InputDevice.getDeviceIds()) {
                val d = InputDevice.getDevice(id) ?: continue
                if ((d.sources and InputDevice.SOURCE_STYLUS) == InputDevice.SOURCE_STYLUS) { stylus = true; break }
            }
            c["stylus"] = stylus
        } catch (_: Exception) {}
        c["multitouch"] = feat("android.hardware.touchscreen.multitouch.jazzhand")
        c["vulkan"] = feat("android.hardware.vulkan.level")
        try { c["displayModes"] = windowManager.defaultDisplay.supportedModes.size } catch (_: Exception) {}
        return c
    }

    private fun buildIndex(): ArrayList<HashMap<String, Any>> {
        val out = ArrayList<HashMap<String, Any>>()
        fun section(name: String, entries: ArrayList<HashMap<String, String>>) {
            out.add(hashMapOf("name" to name, "entries" to entries))
        }

        // ── Device ──
        run {
            val es = ArrayList<HashMap<String, String>>()
            try { es.add(idxEntry("Model", "available", "${Build.MANUFACTURER} ${Build.MODEL}")) } catch (_: Exception) {}
            try { es.add(idxEntry("Android", "available", "Android ${Build.VERSION.RELEASE} · API ${Build.VERSION.SDK_INT}")) } catch (_: Exception) {}
            try { if (Build.VERSION.SDK_INT >= 31) es.add(idxEntry("SoC", "available", "${Build.SOC_MANUFACTURER} ${Build.SOC_MODEL}")) } catch (_: Exception) {}
            try { es.add(idxEntry("ABIs", "available", Build.SUPPORTED_ABIS.joinToString(", "))) } catch (_: Exception) {}
            try { es.add(idxEntry("Security patch", "available", Build.VERSION.SECURITY_PATCH)) } catch (_: Exception) {}
            section("Device", es)
        }

        // ── Compute ──
        run {
            val es = ArrayList<HashMap<String, String>>()
            try {
                val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                es.add(idxEntry("CPU", "available", "$ncores cores · ${Build.SUPPORTED_ABIS.firstOrNull() ?: ""}"))
                es.add(idxEntry("OpenGL ES", "command", am.deviceConfigurationInfo.glEsVersion, "", "OpenGL ES"))
            } catch (_: Exception) {}
            es.add(idxEntry("Vulkan", if (feat("android.hardware.vulkan.level")) "command" else "unsupported", "GPU compute/render", "", "Vulkan"))
            es.add(idxEntry("NPU / DSP", "command", "AI accel — drive via NNAPI/QNN; no utilization readout", "", "NNAPI/TFLite"))
            try {
                val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                val mi = ActivityManager.MemoryInfo(); am.getMemoryInfo(mi)
                es.add(idxEntry("RAM", "available", "${(mi.totalMem / 1073741824.0).let { "%.1f".format(it) }} GB total"))
            } catch (_: Exception) {}
            section("Compute", es)
        }

        // ── Sensors (SensorManager) ──
        run {
            val es = ArrayList<HashMap<String, String>>()
            try {
                val mgr = sm ?: (getSystemService(Context.SENSOR_SERVICE) as SensorManager)
                val list = mgr.getSensorList(Sensor.TYPE_ALL)
                es.add(idxEntry("SensorManager", "available", "${list.size} hardware sensors (see live index)", "", "SensorManager"))
                for (s in list) {
                    val ok = registeredOkName[s.name] ?: false
                    val gate = gateFor(s.type)
                    val status = when {
                        ok -> "available"
                        gate.isNotEmpty() -> "needs-perm"
                        s.reportingMode == 2 -> "command"
                        else -> "sealed"
                    }
                    es.add(idxEntry(s.name, status, "#${s.type} · ${s.vendor} · ${s.stringType ?: ""}", gate, "SensorManager"))
                }
            } catch (_: Exception) {}
            section("Sensors", es)
        }

        // ── Location / GNSS ──
        run {
            val es = ArrayList<HashMap<String, String>>()
            try {
                val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
                es.add(idxEntry("Providers", "available", lm.allProviders.joinToString(", "), "", "LocationManager"))
                if (Build.VERSION.SDK_INT >= 28) {
                    try { es.add(idxEntry("GNSS hardware", "available", "${lm.gnssHardwareModelName ?: "?"} · year ${lm.gnssYearOfHardware}")) } catch (_: Exception) {}
                }
            } catch (_: Exception) {}
            es.add(idxEntry("Fused location", "needs-perm", "lat/lon/alt, speed, bearing, accuracy", "ACCESS_FINE_LOCATION", "FusedLocationProvider"))
            es.add(idxEntry("GNSS raw measurements", "needs-perm", "per-satellite C/N0, pseudorange, carrier phase, constellation", "ACCESS_FINE_LOCATION", "GnssMeasurementsEvent"))
            section("Location / GNSS", es)
        }

        // ── Cellular ──
        run {
            val es = ArrayList<HashMap<String, String>>()
            val hasTel = feat("android.hardware.telephony")
            try {
                val tm = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
                es.add(idxEntry("Telephony", if (hasTel) "available" else "unsupported", "phoneType ${tm.phoneType} · simState ${tm.simState}", "", "TelephonyManager"))
            } catch (_: Exception) {
                es.add(idxEntry("Telephony", if (hasTel) "available" else "unsupported", "", "", "TelephonyManager"))
            }
            es.add(idxEntry("Signal strength", "needs-perm", "dBm RSRP/RSRQ/RSSNR, cell id, band, network type", "READ_PHONE_STATE", "CellInfo/SignalStrength"))
            section("Cellular", es)
        }

        // ── Wi-Fi ──
        run {
            val es = ArrayList<HashMap<String, String>>()
            try {
                val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                val b6 = if (Build.VERSION.SDK_INT >= 30) wm.is6GHzBandSupported else false
                es.add(idxEntry("Wi-Fi", "available", "5GHz:${wm.is5GHzBandSupported} 6GHz:$b6", "", "WifiManager"))
            } catch (_: Exception) {}
            es.add(idxEntry("Wi-Fi RTT ranging", if (feat("android.hardware.wifi.rtt")) "needs-perm" else "unsupported", "fine timing measurement distance", "NEARBY_WIFI_DEVICES", "WifiRttManager"))
            es.add(idxEntry("Wi-Fi Aware", if (feat("android.hardware.wifi.aware")) "needs-perm" else "unsupported", "", "NEARBY_WIFI_DEVICES", "WifiAwareManager"))
            es.add(idxEntry("Scan (RSSI/BSSID)", "needs-perm", "per-AP signal, channel, link speed", "NEARBY_WIFI_DEVICES / location", "WifiManager.scanResults"))
            section("Wi-Fi", es)
        }

        // ── Bluetooth ──
        run {
            val es = ArrayList<HashMap<String, String>>()
            val le = feat("android.hardware.bluetooth_le")
            es.add(idxEntry("Bluetooth LE", if (le) "available" else "unsupported", "", "", "BluetoothManager"))
            try {
                val bm = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
                val a = bm.adapter
                if (a != null && Build.VERSION.SDK_INT >= 26) {
                    es.add(idxEntry("LE PHY", "available", "2M:${a.isLe2MPhySupported} Coded:${a.isLeCodedPhySupported} ExtAdv:${a.isLeExtendedAdvertisingSupported}"))
                }
            } catch (_: Exception) {
                es.add(idxEntry("LE details", "needs-perm", "adapter capabilities", "BLUETOOTH_CONNECT", "BluetoothAdapter"))
            }
            es.add(idxEntry("BLE scan (RSSI/beacons)", "needs-perm", "nearby device signal", "BLUETOOTH_SCAN + location", "BluetoothLeScanner"))
            section("Bluetooth", es)
        }

        // ── UWB ──
        run {
            val es = ArrayList<HashMap<String, String>>()
            val uwb = feat("android.hardware.uwb")
            es.add(idxEntry("Ultra-Wideband", if (uwb) "needs-perm" else "unsupported", if (uwb) "ranging + angle-of-arrival (needs a peer)" else "not present", "UWB_RANGING", "UwbManager"))
            section("UWB", es)
        }

        // ── NFC ──
        run {
            val es = ArrayList<HashMap<String, String>>()
            try {
                val nfc = NfcAdapter.getDefaultAdapter(this)
                es.add(idxEntry("NFC", if (nfc != null) "available" else "unsupported", if (nfc != null) "enabled:${nfc.isEnabled}" else "", "NFC", "NfcAdapter"))
            } catch (_: Exception) {}
            es.add(idxEntry("Host card emulation", if (feat("android.hardware.nfc.hce")) "available" else "unsupported", "", "NFC", "HCE"))
            section("NFC", es)
        }

        // ── Cameras ──
        run {
            val es = ArrayList<HashMap<String, String>>()
            try {
                val cm = getSystemService(Context.CAMERA_SERVICE) as CameraManager
                for (id in cm.cameraIdList) {
                    try {
                        val c = cm.getCameraCharacteristics(id)
                        val facing = when (c.get(CameraCharacteristics.LENS_FACING)) {
                            CameraCharacteristics.LENS_FACING_FRONT -> "front"
                            CameraCharacteristics.LENS_FACING_BACK -> "back"
                            else -> "ext"
                        }
                        val px = c.get(CameraCharacteristics.SENSOR_INFO_PIXEL_ARRAY_SIZE)
                        val mp = if (px != null) "%.0f MP".format(px.width.toLong() * px.height / 1e6) else "?"
                        val iso = c.get(CameraCharacteristics.SENSOR_INFO_SENSITIVITY_RANGE)
                        val caps = c.get(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES)
                        val tags = ArrayList<String>()
                        if (caps != null) {
                            if (caps.contains(CameraMetadata.REQUEST_AVAILABLE_CAPABILITIES_RAW)) tags.add("RAW")
                            if (caps.contains(CameraMetadata.REQUEST_AVAILABLE_CAPABILITIES_MANUAL_SENSOR)) tags.add("MANUAL")
                            if (caps.contains(CameraMetadata.REQUEST_AVAILABLE_CAPABILITIES_DEPTH_OUTPUT)) tags.add("DEPTH")
                        }
                        es.add(idxEntry("Camera $id ($facing)", "needs-perm",
                            "$mp · ISO ${iso?.lower ?: "?"}-${iso?.upper ?: "?"} · ${tags.joinToString("/")}",
                            "CAMERA", "Camera2"))
                    } catch (_: Exception) {}
                }
            } catch (_: Exception) {}
            es.add(idxEntry("Flashlight / torch", if (feat("android.hardware.camera.flash")) "available" else "unsupported", "incl. strength level (API33+)", "", "CameraManager.setTorchMode"))
            section("Cameras", es)
        }

        // ── Microphone / Audio ──
        run {
            val es = ArrayList<HashMap<String, String>>()
            es.add(idxEntry("Microphone", if (feat("android.hardware.microphone")) "needs-perm" else "unsupported", "raw PCM — SPL, FFT, waveform", "RECORD_AUDIO", "AudioRecord"))
            try {
                val au = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                val ins = au.getDevices(AudioManager.GET_DEVICES_INPUTS)
                es.add(idxEntry("Input devices", "available", ins.joinToString(", ") { audioTypeName(it.type) }, "", "AudioManager"))
                val outs = au.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                es.add(idxEntry("Output devices", "available", outs.joinToString(", ") { audioTypeName(it.type) }, "", "AudioManager"))
                es.add(idxEntry("Native rate", "available",
                    "${au.getProperty(AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE)} Hz · ${au.getProperty(AudioManager.PROPERTY_OUTPUT_FRAMES_PER_BUFFER)} frames"))
            } catch (_: Exception) {}
            section("Microphone / Audio", es)
        }

        // ── Input / Touch ──
        run {
            val es = ArrayList<HashMap<String, String>>()
            es.add(idxEntry("Touch (digitizer)", "available", "per-touch pressure, size, tool — our own MotionEvents", "", "MotionEvent"))
            es.add(idxEntry("Multitouch", if (feat("android.hardware.touchscreen.multitouch.jazzhand")) "available" else "basic", "10-point distinct", "", "PackageManager"))
            try {
                for (id in InputDevice.getDeviceIds()) {
                    val d = InputDevice.getDevice(id) ?: continue
                    val isStylus = (d.sources and InputDevice.SOURCE_STYLUS) == InputDevice.SOURCE_STYLUS
                    if (isStylus) es.add(idxEntry("Stylus / S-Pen", "available", d.name, "", "InputDevice"))
                }
            } catch (_: Exception) {}
            section("Input / Touch", es)
        }

        // ── Display ──
        run {
            val es = ArrayList<HashMap<String, String>>()
            try {
                val d = windowManager.defaultDisplay
                val modes = d.supportedModes.joinToString(", ") { "${it.physicalWidth}x${it.physicalHeight}@${it.refreshRate.toInt()}" }
                es.add(idxEntry("Display modes", "available", modes, "", "Display"))
            } catch (_: Exception) {}
            try {
                val dm = resources.displayMetrics
                es.add(idxEntry("Metrics", "available", "${dm.widthPixels}x${dm.heightPixels} · ${dm.densityDpi} dpi"))
            } catch (_: Exception) {}
            es.add(idxEntry("HDR", if (feat("android.hardware.ram.normal")) "available" else "available", "high-dynamic-range caps queryable", "", "Display.getHdrCapabilities"))
            section("Display", es)
        }

        // ── Biometrics ──
        run {
            val es = ArrayList<HashMap<String, String>>()
            es.add(idxEntry("Fingerprint", if (feat("android.hardware.fingerprint")) "command" else "unsupported", "auth only — no raw image", "USE_BIOMETRIC", "BiometricPrompt"))
            es.add(idxEntry("Face", if (feat("android.hardware.biometrics.face")) "command" else "unsupported", "auth only", "USE_BIOMETRIC", "BiometricPrompt"))
            es.add(idxEntry("Iris", if (feat("android.hardware.biometrics.iris")) "command" else "unsupported", "auth only", "USE_BIOMETRIC", "BiometricPrompt"))
            section("Biometrics", es)
        }

        // ── Haptics ──
        run {
            val es = ArrayList<HashMap<String, String>>()
            try {
                val v = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
                es.add(idxEntry("Vibrator", if (v.hasVibrator()) "command" else "unsupported", "amplitude control: ${v.hasAmplitudeControl()}", "", "Vibrator"))
            } catch (_: Exception) {}
            section("Haptics", es)
        }

        // ── Thermal / Power ──
        run {
            val es = ArrayList<HashMap<String, String>>()
            es.add(idxEntry("Thermal", "available", "status + headroom (API30) + /sys zones", "", "PowerManager"))
            es.add(idxEntry("Battery / BMS", "available", "V, I, charge counter, cycle count, temp", "", "BatteryManager"))
            section("Thermal / Power", es)
        }

        // ── System features (hardware.*) ──
        run {
            val es = ArrayList<HashMap<String, String>>()
            try {
                val feats = packageManager.systemAvailableFeatures
                    .mapNotNull { it.name }
                    .filter { it.startsWith("android.hardware") }
                    .sorted()
                for (f in feats) es.add(idxEntry(f, "available", "", "", "PackageManager"))
            } catch (_: Exception) {}
            section("System features", es)
        }

        return out
    }

    private fun audioTypeName(t: Int): String = when (t) {
        AudioDeviceInfo.TYPE_BUILTIN_MIC -> "builtin-mic"
        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "speaker"
        AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "earpiece"
        AudioDeviceInfo.TYPE_WIRED_HEADSET -> "wired-headset"
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "wired-headphones"
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "bt-a2dp"
        AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "bt-sco"
        AudioDeviceInfo.TYPE_USB_DEVICE -> "usb"
        AudioDeviceInfo.TYPE_TELEPHONY -> "telephony"
        else -> "type$t"
    }

    override fun onDestroy() {
        try { sm?.unregisterListener(this) } catch (_: Exception) {}
        try { smSensor?.let { sm?.cancelTriggerSensor(smTrigger, it) } } catch (_: Exception) {}
        stopMic()
        stopLoc()
        stopBle()
        try { setTorch(false) } catch (_: Exception) {}
        handler.removeCallbacks(emitter)
        super.onDestroy()
    }
}
