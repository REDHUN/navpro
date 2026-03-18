package com.example.navprov2

import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.util.Log
import android.app.NotificationManager
import android.content.Context
import android.os.Process

class NavigationTerminationService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Keep the service running so it can detect when the app is swiped away
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        Log.e("NavTermination", "App swiped away. Terminating process to stop navigation.")
        
        // 1. Clear all notifications (including navigation guidance)
        try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.cancelAll()
        } catch (e: Exception) {
            Log.e("NavTermination", "Failed to cancel notifications: ${e.message}")
        }

        // 2. Kill the process. This is the most reliable way to stop the 
        // Google Navigation SDK's foreground service and voice guidance.
        stopSelf()
        Process.killProcess(Process.myPid())
        System.exit(0)
    }
}
