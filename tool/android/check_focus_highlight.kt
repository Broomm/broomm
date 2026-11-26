package app.broomm.broomm.focusfixture

import android.content.Context
import android.content.res.Configuration
import android.os.Build
import android.os.Looper
import android.view.ContextThemeWrapper
import android.widget.FrameLayout
import kotlin.system.exitProcess

// A read-only app_process check against the installed APK's real resources.
// No Activity/window is attached and no application data is opened.
@Suppress("DEPRECATION")
fun main() {
    check(Build.VERSION.SDK_INT >= 26) { "Default focus highlights require Android 8 or later." }
    if (Looper.getMainLooper() == null) Looper.prepareMainLooper()
    val threadClass = Class.forName("android.app.ActivityThread")
    val thread = threadClass.getMethod("systemMain").invoke(null)
    val system = threadClass.getMethod("getSystemContext").invoke(thread) as Context
    val app = system.createPackageContext("app.broomm.broomm", 0)
    var failures = 0
    for ((label, mode) in listOf("day" to Configuration.UI_MODE_NIGHT_NO, "night" to Configuration.UI_MODE_NIGHT_YES)) {
        val config = Configuration(app.resources.configuration)
        config.uiMode = (config.uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or mode
        val configured = app.createConfigurationContext(config)
        val parent = if (mode == Configuration.UI_MODE_NIGHT_YES)
            android.R.style.Theme_Black_NoTitleBar else android.R.style.Theme_Light_NoTitleBar
        // Match FlutterView's actual superclass constructor: the one-argument
        // View constructor bypasses styled-attribute loading entirely.
        check(FrameLayout(ContextThemeWrapper(configured, parent), null).defaultFocusHighlightEnabled) {
            "The platform parent must reproduce the default highlight."
        }
        for (theme in listOf("LaunchTheme", "NormalTheme")) {
            val id = configured.resources.getIdentifier(theme, "style", "app.broomm.broomm")
            check(id != 0) { "Missing installed theme $theme." }
            val view = FrameLayout(ContextThemeWrapper(configured, id), null)
            view.isFocusable = true
            // FlutterView accepts keyboard focus while Android is in touch mode.
            view.isFocusableInTouchMode = true
            view.layout(0, 0, 128, 128)
            val focused = view.requestFocus() && view.isFocused
            val passed = !view.defaultFocusHighlightEnabled && focused
            println("${if (passed) "PASS" else "FAIL"}: $label $theme defaultHighlight=${view.defaultFocusHighlightEnabled} focusPreserved=$focused")
            if (!passed) failures++
        }
    }
    exitProcess(if (failures == 0) 0 else 1)
}
