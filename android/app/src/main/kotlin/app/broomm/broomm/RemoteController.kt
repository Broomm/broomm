package app.broomm.broomm

import android.view.KeyEvent
import android.view.MotionEvent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Read foreground controller state. Host-side emulation remains in Broomm's desktop bridge. */
class RemoteController(engine: FlutterEngine) {
    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "app.broomm/remote")
    private var enabled = false
    private var device: Int? = null
    private var buttons = 0
    private val axes = IntArray(6)
    private val triggerButtons = BooleanArray(2)
    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method == "controller") {
                enabled = call.arguments == true
                clear()
                result.success(null)
            } else result.notImplemented()
        }
    }
    fun key(event: KeyEvent) {
        if (!enabled || (!event.isFromSource(android.view.InputDevice.SOURCE_GAMEPAD) &&
            !event.isFromSource(android.view.InputDevice.SOURCE_JOYSTICK))) return
        if (device != null && device != event.deviceId) return
        device = event.deviceId
        val index = when (event.keyCode) {
            KeyEvent.KEYCODE_BUTTON_A -> 0
            KeyEvent.KEYCODE_BUTTON_B -> 1
            KeyEvent.KEYCODE_BUTTON_X -> 2
            KeyEvent.KEYCODE_BUTTON_Y -> 3
            KeyEvent.KEYCODE_BUTTON_SELECT -> 4
            KeyEvent.KEYCODE_BUTTON_START -> 6
            KeyEvent.KEYCODE_BUTTON_THUMBL -> 7
            KeyEvent.KEYCODE_BUTTON_THUMBR -> 8
            KeyEvent.KEYCODE_BUTTON_L1 -> 9
            KeyEvent.KEYCODE_BUTTON_R1 -> 10
            KeyEvent.KEYCODE_DPAD_UP -> 11
            KeyEvent.KEYCODE_DPAD_DOWN -> 12
            KeyEvent.KEYCODE_DPAD_LEFT -> 13
            KeyEvent.KEYCODE_DPAD_RIGHT -> 14
            else -> null
        }
        if (index != null) {
            buttons = if (event.action == KeyEvent.ACTION_DOWN) buttons or (1 shl index) else buttons and (1 shl index).inv()
        }
        if (event.keyCode == KeyEvent.KEYCODE_BUTTON_L2) triggerButtons[0] = event.action == KeyEvent.ACTION_DOWN
        if (event.keyCode == KeyEvent.KEYCODE_BUTTON_R2) triggerButtons[1] = event.action == KeyEvent.ACTION_DOWN
        send()
    }
    fun motion(event: MotionEvent) {
        if (!enabled || !event.isFromSource(android.view.InputDevice.SOURCE_JOYSTICK)) return
        if (device != null && device != event.deviceId) return
        device = event.deviceId
        val codes = intArrayOf(MotionEvent.AXIS_X, MotionEvent.AXIS_Y, MotionEvent.AXIS_Z, MotionEvent.AXIS_RZ, MotionEvent.AXIS_LTRIGGER, MotionEvent.AXIS_RTRIGGER)
        for (i in codes.indices) {
            var value = event.getAxisValue(codes[i])
            if (i == 4) value = maxOf(value, event.getAxisValue(MotionEvent.AXIS_BRAKE))
            if (i == 5) value = maxOf(value, event.getAxisValue(MotionEvent.AXIS_GAS))
            axes[i] = (value.coerceIn(if (i >= 4) 0f else -1f, 1f) * 32767).toInt()
        }
        val hx = event.getAxisValue(MotionEvent.AXIS_HAT_X)
        val hy = event.getAxisValue(MotionEvent.AXIS_HAT_Y)
        for ((index, pressed) in listOf(11 to (hy < -0.5f), 12 to (hy > 0.5f), 13 to (hx < -0.5f), 14 to (hx > 0.5f))) {
            buttons = if (pressed) buttons or (1 shl index) else buttons and (1 shl index).inv()
        }
        send()
    }
    fun removed(id: Int) { if (device == id) clear() }
    fun clear() { device = null; buttons = 0; axes.fill(0); triggerButtons.fill(false); send() }
    private fun send() {
        val values = axes.toMutableList()
        for (i in triggerButtons.indices) if (triggerButtons[i]) values[4 + i] = 32767
        if (enabled) channel.invokeMethod("pad", mapOf("device" to device, "buttons" to buttons, "axes" to values, "connected" to (device != null)))
    }
}
