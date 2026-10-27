package app.broomm.broomm

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import android.os.Handler
import android.os.Looper
import android.hardware.input.InputManager
import android.content.Intent

class MainActivity : FlutterActivity(), InputManager.InputDeviceListener {
    private var controls: MethodChannel? = null
    private var credentials: BroommCredentials? = null
    private var emulators: BroommEmulators? = null
    private var updates: BroommUpdates? = null
    private val handler = Handler(Looper.getMainLooper())
    private var held: String? = null
    private val shifts = mutableSetOf<String>()
    private val enters = mutableSetOf<String>()
    private fun enter(key: String, down: Boolean) {
        val device = key.substringBefore('-')
        val wasDown = enters.any { it.startsWith("$device-") }
        if (down) enters.add(key) else enters.remove(key)
        if (!wasDown && enters.any { it.startsWith("$device-") }) controls?.invokeMethod("controller", "keyboard-enter")
    }
    private var inputs: InputManager? = null
    private fun shift(key: String, down: Boolean) {
        val previous = shifts.isNotEmpty()
        if (down) shifts.add(key) else shifts.remove(key)
        if (previous != shifts.isNotEmpty()) controls?.invokeMethod("controller", if (shifts.isNotEmpty()) "shift-down" else "shift-up")
    }
    private val repeat = object : Runnable {
        override fun run() {
            held?.let { controls?.invokeMethod("controller", it); handler.postDelayed(this, 120) }
        }
    }
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        credentials = BroommCredentials(this).also { it.register(engine) }
        emulators = BroommEmulators(this).also { it.register(engine) }
        updates = BroommUpdates(this).also { it.register(engine) }
        controls = MethodChannel(engine.dartExecutor.binaryMessenger, "app.broomm/prototype")
        inputs = getSystemService(INPUT_SERVICE) as InputManager
        inputs?.registerInputDeviceListener(this, handler)
        MethodChannel(engine.dartExecutor.binaryMessenger, "app.broomm/platform").setMethodCallHandler { call, result ->
            if (call.method == "dataDirectory") result.success(filesDir.absolutePath) else result.notImplemented()
        }
    }
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if ((event.source and InputDevice.SOURCE_GAMEPAD) == InputDevice.SOURCE_GAMEPAD ||
            (event.source and InputDevice.SOURCE_JOYSTICK) == InputDevice.SOURCE_JOYSTICK) {
            if (event.keyCode == KeyEvent.KEYCODE_BUTTON_L2) {
                shift("${event.deviceId}-key", event.action == KeyEvent.ACTION_DOWN)
                return true
            }
            if (event.keyCode == KeyEvent.KEYCODE_BUTTON_R2) {
                enter("${event.deviceId}-key", event.action == KeyEvent.ACTION_DOWN)
                return true
            }
            val action = when (event.keyCode) {
                KeyEvent.KEYCODE_BUTTON_A -> "accept"
                KeyEvent.KEYCODE_BUTTON_B -> "back"
                KeyEvent.KEYCODE_BUTTON_X -> "search"
                KeyEvent.KEYCODE_BUTTON_Y -> "space"
                KeyEvent.KEYCODE_BUTTON_THUMBL -> "caps"
                KeyEvent.KEYCODE_BUTTON_L1 -> "caret-left"
                KeyEvent.KEYCODE_BUTTON_R1 -> "caret-right"
                KeyEvent.KEYCODE_BUTTON_START -> "home"
                KeyEvent.KEYCODE_BUTTON_SELECT -> "options"
                KeyEvent.KEYCODE_DPAD_UP -> "up"
                KeyEvent.KEYCODE_DPAD_DOWN -> "down"
                KeyEvent.KEYCODE_DPAD_LEFT -> "left"
                KeyEvent.KEYCODE_DPAD_RIGHT -> "right"
                else -> null
            }
            if (action != null) {
                if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) controls?.invokeMethod("controller", action)
                return true
            }
        }
        return super.dispatchKeyEvent(event)
    }
    override fun onGenericMotionEvent(event: MotionEvent): Boolean {
        if ((event.source and InputDevice.SOURCE_JOYSTICK) == InputDevice.SOURCE_JOYSTICK && event.action == MotionEvent.ACTION_MOVE) {
            shift("${event.deviceId}-axis", event.getAxisValue(MotionEvent.AXIS_LTRIGGER) > 0.55f || event.getAxisValue(MotionEvent.AXIS_BRAKE) > 0.55f)
            enter("${event.deviceId}-axis", event.getAxisValue(MotionEvent.AXIS_RTRIGGER) > 0.55f || event.getAxisValue(MotionEvent.AXIS_GAS) > 0.55f)
            val x = event.getAxisValue(MotionEvent.AXIS_X)
            val y = event.getAxisValue(MotionEvent.AXIS_Y)
            val hx = event.getAxisValue(MotionEvent.AXIS_HAT_X)
            val hy = event.getAxisValue(MotionEvent.AXIS_HAT_Y)
            val direction = when {
                hy < -0.5 || y < -0.55 -> "up"
                hy > 0.5 || y > 0.55 -> "down"
                hx < -0.5 || x < -0.55 -> "left"
                hx > 0.5 || x > 0.55 -> "right"
                else -> null
            }
            if (direction != held) {
                handler.removeCallbacks(repeat); held = direction
                direction?.let { controls?.invokeMethod("controller", it); handler.postDelayed(repeat, 400) }
            }
            return true
        }
        return super.onGenericMotionEvent(event)
    }
    override fun onInputDeviceAdded(deviceId: Int) {}
    @Deprecated("Android activity result adapter")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (updates?.activityResult(requestCode) == true) return
        if (emulators?.activityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }
    override fun onInputDeviceChanged(deviceId: Int) {}
    override fun onInputDeviceRemoved(deviceId: Int) {
        for (key in shifts.filter { it.startsWith("$deviceId-") }) shift(key, false)
        enters.removeAll { it.startsWith("$deviceId-") }
    }
    override fun onPause() { held = null; handler.removeCallbacks(repeat); for (key in shifts.toList()) shift(key, false); enters.clear(); super.onPause() }
    override fun onDestroy() { inputs?.unregisterInputDeviceListener(this); inputs = null; handler.removeCallbacks(repeat); credentials?.close(); credentials = null; emulators?.close(); emulators = null; updates?.close(); updates = null; controls = null; super.onDestroy() }
}
