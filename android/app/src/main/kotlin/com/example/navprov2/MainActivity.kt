package com.example.navprov2

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.Process

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.navprov2/navigation"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Start the service that detects when the app is swiped away
        startService(Intent(this, NavigationTerminationService::class.java))
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "forceStopNavigation") {
                // Force kill the process to stop all foreground services and notifications
                Process.killProcess(Process.myPid())
                System.exit(0)
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }
}
