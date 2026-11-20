package com.xenu.retroxr.qr

import android.content.Context
import android.graphics.ImageFormat
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.media.ImageReader
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import android.util.Log
import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.PlanarYUVLuminanceSource
import com.google.zxing.common.HybridBinarizer
import com.google.zxing.qrcode.QRCodeReader
import org.godotengine.godot.Dictionary
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot

/**
 * Reads QR codes through a Meta passthrough camera.
 *
 * Horizon OS exposes the passthrough cameras as ordinary Camera2 devices tagged
 * with vendor metadata, so this is plain Camera2 plus a ZXing decode on the Y
 * plane. Quest 3 / 3S on Horizon OS v74 or newer only.
 *
 * Frames never cross into Godot at capture size: decoding happens here, and the
 * only thing sent over is a 320x240 luma viewfinder.
 *
 * The same camera also serves a luma FEED (startFeed / camera_frame) for what
 * looks through it from inside the game, the Game Boy Camera's lens. A scan and
 * a feed share one open camera: it opens for whichever wants it first and closes
 * when neither does, and decoding runs only while a scan is wanted. Where the
 * camera sits on the head and how it projects is read once at open
 * (getCameraInfo), which a feed needs and a scan never did.
 */
class QrScannerPlugin(godot: Godot) : GodotPlugin(godot) {

    private companion object {
        const val TAG = "RetroXRQr"

        const val CAPTURE_WIDTH = 1280
        const val CAPTURE_HEIGHT = 960
        const val PREVIEW_WIDTH = 320
        const val PREVIEW_HEIGHT = 240

        const val DECODE_INTERVAL_MS = 125L   // ~8 Hz
        const val PREVIEW_INTERVAL_MS = 83L   // ~12 Hz
        // A little faster than the Game Boy Camera's 12 pictures a second, so the
        // newest feed frame is never more than one capture behind a picture.
        const val FEED_INTERVAL_MS = 62L      // ~16 Hz
        const val FEED_MAX_SIDE = 1280

        // Verified against a Quest 3 on Horizon OS: cameras 50 and 51 carry
        // camera_source / position / camera_name / camera_thumbnail. The tag is
        // "position", NOT "camera_position".
        const val META_SOURCE = "com.meta.extra_metadata.camera_source"
        const val META_POSITION = "com.meta.extra_metadata.position"
        const val SOURCE_PASSTHROUGH = 0
        const val POSITION_LEFT = 0

        val SIGNAL_FRAME = SignalInfo("qr_frame", ByteArray::class.java)
        val SIGNAL_DETECTED = SignalInfo("qr_detected", String::class.java)
        val SIGNAL_ERROR = SignalInfo("qr_error", String::class.java)
        // Luma, width, height, and how many microseconds before the emit the
        // frame was exposed (-1 when the sensor's clock is not elapsedRealtime).
        // Ints, not a Long: an age fits, and Integer is the boxed type every
        // Godot release converts.
        val SIGNAL_CAMERA_FRAME = SignalInfo(
            "camera_frame", ByteArray::class.java,
            Int::class.javaObjectType, Int::class.javaObjectType, Int::class.javaObjectType
        )
    }

    private var thread: HandlerThread? = null
    private var handler: Handler? = null
    private var device: CameraDevice? = null
    private var session: CameraCaptureSession? = null
    private var reader: ImageReader? = null

    /** The camera is open or opening. */
    @Volatile
    private var running = false
    @Volatile
    private var scanWanted = false
    @Volatile
    private var feedWanted = false
    @Volatile
    private var feedWidth = 640
    @Volatile
    private var feedHeight = 480
    private var lastDecodeMs = 0L
    private var lastPreviewMs = 0L
    private var lastFeedMs = 0L

    /** Read on the camera thread at open, handed out on Godot's. */
    @Volatile
    private var cameraInfo: Map<String, Any> = emptyMap()
    private var realtimeTimestamps = false

    private val qrReader = QRCodeReader()
    private val hints = mapOf<DecodeHintType, Any>(DecodeHintType.TRY_HARDER to true)

    override fun getPluginName() = "RetroXRQr"

    override fun getPluginSignals(): Set<SignalInfo> =
        setOf(SIGNAL_FRAME, SIGNAL_DETECTED, SIGNAL_ERROR, SIGNAL_CAMERA_FRAME)

    // The camera must not survive the app going to the background: an open
    // handle keeps the Horizon OS privacy indicator lit and drains the battery.
    // A scan ends there, as it always has; a feed is still wanted, and reopens
    // on resume, because its owner (a cartridge in a running machine) is still
    // there when the app comes back.
    override fun onMainPause() {
        scanWanted = false
        closeCamera()
    }

    override fun onMainResume() {
        if (feedWanted) ensureOpen()
    }

    override fun onMainDestroy() {
        scanWanted = false
        feedWanted = false
        closeCamera()
    }

    private val cameraManager: CameraManager?
        get() = activity?.getSystemService(Context.CAMERA_SERVICE) as? CameraManager

    /**
     * Answers from the model alone — deliberately no Camera2 call.
     *
     * Two reasons. This runs while the menu is being built on Godot's main
     * thread, and `getCameraCharacteristics` is a blocking Binder call into the
     * camera service; a slow or busy service would stall startup. And Horizon OS
     * does not expose the passthrough cameras until HEADSET_CAMERA is granted
     * (ungranted, `cameraIdList` holds one camera with no vendor tags at all),
     * so enumerating here would hide the very button that requests it.
     *
     * Whether a camera can actually be opened is settled in startScan(), off the
     * main thread, and reported through `qr_error`.
     */
    @UsedByGodot
    fun isAvailable(): Boolean {
        val supported = isPassthroughCameraModel()
        Log.i(TAG, "isAvailable=$supported (model ${Build.MODEL})")
        return supported
    }

    /** Quest 3 and 3S only; Quest 2 and Pro have no passthrough camera access. */
    private fun isPassthroughCameraModel(): Boolean =
        (Build.MODEL ?: "").startsWith("Quest 3", ignoreCase = true)

    /**
     * Returns true meaning "starting", not "started" — enumeration and the open
     * both happen on the camera thread, because they are blocking Binder calls
     * and this is invoked from Godot's main thread. Failures arrive on
     * `qr_error`.
     */
    @UsedByGodot
    fun startScan(): Boolean {
        lastDecodeMs = 0L
        lastPreviewMs = 0L
        scanWanted = true
        return ensureOpen()
    }

    /** Safe from any thread and at any point in the open sequence. */
    @UsedByGodot
    fun stopScan() {
        scanWanted = false
        if (!feedWanted) closeCamera()
    }

    /**
     * Start emitting `camera_frame` at `width` x `height` (the capture, scaled
     * down; never up). Like startScan, true means "starting"; failures arrive
     * on `qr_error`, after which the feed is no longer wanted and a caller that
     * still wants it asks again.
     */
    @UsedByGodot
    fun startFeed(width: Int, height: Int): Boolean {
        feedWidth = width.coerceIn(1, FEED_MAX_SIDE)
        feedHeight = height.coerceIn(1, FEED_MAX_SIDE)
        lastFeedMs = 0L
        feedWanted = true
        return ensureOpen()
    }

    @UsedByGodot
    fun stopFeed() {
        feedWanted = false
        if (!scanWanted) closeCamera()
    }

    /**
     * What a picture through the camera needs to be placed in the world, read
     * from CameraCharacteristics when it opened. Empty until then.
     *
     * - pose_rotation: LENS_POSE_ROTATION, quaternion x, y, z, w
     * - pose_translation: LENS_POSE_TRANSLATION, meters
     * - pose_reference: LENS_POSE_REFERENCE (-1 below API 28)
     * - intrinsics: LENS_INTRINSIC_CALIBRATION, fx, fy, cx, cy, s in active-array pixels
     * - active_array: SENSOR_INFO_ACTIVE_ARRAY_SIZE, left, top, right, bottom
     * - capture_size: the frames' width and height before any feed scaling
     * - timestamp_realtime: whether frame ages are measured (camera_frame's age)
     */
    @UsedByGodot
    fun getCameraInfo(): Dictionary {
        val out = Dictionary()
        out.putAll(cameraInfo)
        return out
    }

    private fun ensureOpen(): Boolean {
        if (running) return true
        if (cameraManager == null) {
            fail("No camera service")
            abandon()
            return false
        }

        startThread()
        running = true

        val posted = handler?.post { openOnCameraThread() } ?: false
        if (!posted) {
            fail("Could not start the camera thread")
            abandon()
            return false
        }
        return true
    }

    /** A failure ends every use of the camera; its owners ask again. */
    private fun abandon() {
        scanWanted = false
        feedWanted = false
        closeCamera()
    }

    private fun openOnCameraThread() {
        if (!running) return
        val manager = cameraManager ?: return

        val id = findPassthroughCameraId()
        if (id == null) {
            logCameraKeys()
            fail("No passthrough camera available")
            abandon()
            return
        }
        readCameraInfo(manager, id)

        reader = ImageReader.newInstance(
            CAPTURE_WIDTH, CAPTURE_HEIGHT, ImageFormat.YUV_420_888, 3
        ).apply {
            setOnImageAvailableListener({ r -> onImage(r) }, handler)
        }

        try {
            manager.openCamera(id, deviceCallback, handler)
        } catch (e: SecurityException) {
            fail("Camera permission was not granted")
            abandon()
        } catch (e: Exception) {
            fail("Could not open the camera: ${e.message}")
            abandon()
        }
    }

    /** Safe from any thread and at any point in the open sequence. */
    private fun closeCamera() {
        running = false

        session?.let { s ->
            runCatching { s.stopRepeating() }
            runCatching { s.close() }
        }
        session = null

        device?.let { d -> runCatching { d.close() } }
        device = null

        reader?.let { r -> runCatching { r.close() } }
        reader = null

        stopThread()
    }

    private val deviceCallback = object : CameraDevice.StateCallback() {
        override fun onOpened(camera: CameraDevice) {
            device = camera
            val surface = reader?.surface
            if (surface == null) {
                fail("Camera opened with no target surface")
                return
            }
            try {
                @Suppress("DEPRECATION")
                camera.createCaptureSession(listOf(surface), sessionCallback, handler)
            } catch (e: Exception) {
                fail("Could not create the capture session: ${e.message}")
            }
        }

        override fun onDisconnected(camera: CameraDevice) {
            fail("Camera disconnected")
            abandon()
        }

        override fun onError(camera: CameraDevice, error: Int) {
            fail("Camera error $error")
            abandon()
        }
    }

    private val sessionCallback = object : CameraCaptureSession.StateCallback() {
        override fun onConfigured(configured: CameraCaptureSession) {
            session = configured
            val dev = device ?: return
            val surface = reader?.surface ?: return
            try {
                val request = dev.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
                request.addTarget(surface)
                configured.setRepeatingRequest(request.build(), null, handler)
            } catch (e: Exception) {
                fail("Could not start the capture: ${e.message}")
            }
        }

        override fun onConfigureFailed(configured: CameraCaptureSession) {
            fail("Camera session configuration failed")
        }
    }

    private fun onImage(from: ImageReader) {
        val image = try {
            from.acquireLatestImage()
        } catch (e: Exception) {
            null
        } ?: return

        try {
            if (!running) return

            val plane = image.planes[0]
            val buffer = plane.buffer
            val luma = ByteArray(buffer.remaining())
            buffer.get(luma)

            val stride = plane.rowStride
            val width = image.width
            val height = image.height
            val now = SystemClock.elapsedRealtime()

            if (feedWanted && now - lastFeedMs >= FEED_INTERVAL_MS) {
                lastFeedMs = now
                val w = minOf(feedWidth, width)
                val h = minOf(feedHeight, height)
                val ageUs = if (realtimeTimestamps)
                    ((SystemClock.elapsedRealtimeNanos() - image.timestamp) / 1000L)
                        .coerceIn(0L, Int.MAX_VALUE.toLong()).toInt()
                else -1
                emitSignal(
                    SIGNAL_CAMERA_FRAME.name,
                    downsample(luma, stride, width, height, w, h), w, h, ageUs
                )
            }

            if (!scanWanted) return

            if (now - lastPreviewMs >= PREVIEW_INTERVAL_MS) {
                lastPreviewMs = now
                emitSignal(
                    SIGNAL_FRAME.name,
                    downsample(luma, stride, width, height, PREVIEW_WIDTH, PREVIEW_HEIGHT)
                )
            }

            if (now - lastDecodeMs >= DECODE_INTERVAL_MS) {
                lastDecodeMs = now
                decode(luma, stride, width, height)?.let { text ->
                    emitSignal(SIGNAL_DETECTED.name, text)
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "frame handling failed", e)
        } finally {
            // Skipping this stalls the reader after `maxImages` frames.
            runCatching { image.close() }
        }
    }

    /** Null on every frame that holds no readable code — the normal case. */
    private fun decode(luma: ByteArray, stride: Int, width: Int, height: Int): String? {
        if (luma.size < stride * height) return null
        return try {
            val source = PlanarYUVLuminanceSource(
                luma, stride, height, 0, 0, width, height, false
            )
            qrReader.decode(BinaryBitmap(HybridBinarizer(source)), hints).text
        } catch (e: Exception) {
            null
        } finally {
            qrReader.reset()
        }
    }

    /**
     * Nearest-neighbour: the preview is an aiming aid, and the decode above
     * always runs on the full-resolution plane regardless of what the preview
     * looks like. A feed ends as a Game Boy Camera's 128x112 in four grays.
     */
    private fun downsample(
        luma: ByteArray, stride: Int, width: Int, height: Int, outWidth: Int, outHeight: Int
    ): ByteArray {
        val out = ByteArray(outWidth * outHeight)
        var at = 0
        for (py in 0 until outHeight) {
            val row = (py * height / outHeight) * stride
            for (px in 0 until outWidth) {
                val index = row + (px * width / outWidth)
                out[at++] = if (index < luma.size) luma[index] else 0
            }
        }
        return out
    }

    /**
     * Logged as well as kept: which way the pose is expressed on a Quest is
     * settled by looking, and this line is what that look starts from.
     */
    private fun readCameraInfo(manager: CameraManager, id: String) {
        val info = HashMap<String, Any>()
        try {
            val c = manager.getCameraCharacteristics(id)
            c.get(CameraCharacteristics.LENS_POSE_ROTATION)?.let { info["pose_rotation"] = it }
            c.get(CameraCharacteristics.LENS_POSE_TRANSLATION)?.let { info["pose_translation"] = it }
            c.get(CameraCharacteristics.LENS_INTRINSIC_CALIBRATION)?.let { info["intrinsics"] = it }
            info["pose_reference"] = if (Build.VERSION.SDK_INT >= 28)
                c.get(CameraCharacteristics.LENS_POSE_REFERENCE) ?: -1 else -1
            c.get(CameraCharacteristics.SENSOR_INFO_ACTIVE_ARRAY_SIZE)?.let { r ->
                info["active_array"] = intArrayOf(r.left, r.top, r.right, r.bottom)
            }
            info["capture_size"] = intArrayOf(CAPTURE_WIDTH, CAPTURE_HEIGHT)
            realtimeTimestamps = c.get(CameraCharacteristics.SENSOR_INFO_TIMESTAMP_SOURCE) ==
                CameraCharacteristics.SENSOR_INFO_TIMESTAMP_SOURCE_REALTIME
            info["timestamp_realtime"] = realtimeTimestamps
            info["camera_id"] = id
        } catch (e: Exception) {
            Log.w(TAG, "camera characteristics failed", e)
        }
        Log.i(TAG, "camera $id: " + info.entries.joinToString { (k, v) ->
            "$k=" + when (v) {
                is FloatArray -> v.contentToString()
                is IntArray -> v.contentToString()
                else -> v.toString()
            }
        })
        cameraInfo = info
    }

    private fun findPassthroughCameraId(): String? {
        val manager = cameraManager ?: return null
        return try {
            val passthrough = manager.cameraIdList.filter { id ->
                vendorInt(manager.getCameraCharacteristics(id), META_SOURCE) == SOURCE_PASSTHROUGH
            }
            // Prefer the left eye, but take any passthrough camera if the
            // position tag is missing: that tag has already been renamed once,
            // and losing it should cost the eye choice, not the whole feature.
            passthrough.firstOrNull { id ->
                vendorInt(manager.getCameraCharacteristics(id), META_POSITION) == POSITION_LEFT
            } ?: passthrough.firstOrNull()
        } catch (e: Exception) {
            Log.w(TAG, "camera enumeration failed", e)
            null
        }
    }

    /**
     * CameraCharacteristics.Key has no public constructor, so the Meta vendor
     * tags are matched by name against the keys the device actually reports.
     */
    private fun vendorInt(characteristics: CameraCharacteristics, name: String): Int? {
        val key = characteristics.keys.firstOrNull { it.name == name } ?: return null
        @Suppress("UNCHECKED_CAST")
        val value = characteristics.get(key as CameraCharacteristics.Key<Any>) ?: return null
        // Verified on a Quest 3: these come back as byte[], not as a scalar.
        return when (value) {
            is ByteArray -> if (value.isEmpty()) null else value[0].toInt()
            is Number -> value.toInt()
            else -> null
        }
    }

    /** Makes a vendor-tag rename or a value-encoding surprise diagnosable
     *  instead of looking like missing hardware. */
    private fun logCameraKeys() {
        val manager = cameraManager ?: return
        runCatching {
            for (id in manager.cameraIdList) {
                val characteristics = manager.getCameraCharacteristics(id)
                val described = characteristics.keys
                    .filter { it.name.startsWith("com.meta") }
                    .map { key -> "${key.name}=${vendorInt(characteristics, key.name)}" }
                Log.i(TAG, "camera $id: $described")
            }
        }
    }

    private fun startThread() {
        if (thread != null) return
        thread = HandlerThread("RetroXRQr").apply { start() }
        handler = Handler(thread!!.looper)
    }

    private fun stopThread() {
        val t = thread ?: return
        thread = null
        handler = null
        t.quitSafely()
        // Joining from the camera thread itself would deadlock.
        if (Thread.currentThread() !== t) {
            runCatching { t.join(1000) }
        }
    }

    private fun fail(message: String) {
        Log.w(TAG, message)
        emitSignal(SIGNAL_ERROR.name, message)
    }
}
