package com.example.ai_car_diagnostics

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var callback: ConnectivityManager.NetworkCallback? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fixai/netbind")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "bindWifi" -> {
                        val req = NetworkRequest.Builder()
                            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                            .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                            .build()
                        var replied = false
                        callback = object : ConnectivityManager.NetworkCallback() {
                            override fun onAvailable(network: Network) {
                                cm.bindProcessToNetwork(network)
                                runOnUiThread {
                                    if (!replied) {
                                        replied = true
                                        result.success(true)
                                    }
                                }
                            }
                            override fun onLost(network: Network) {
                                cm.bindProcessToNetwork(null)
                            }
                            override fun onUnavailable() {
                                runOnUiThread {
                                    if (!replied) {
                                        replied = true
                                        result.success(false)
                                    }
                                }
                            }
                        }
                        cm.requestNetwork(req, callback!!, 5000)
                    }
                    "unbind" -> {
                        cm.bindProcessToNetwork(null)
                        callback?.let { runCatching { cm.unregisterNetworkCallback(it) } }
                        callback = null
                        result.success(true)
                    }
                    "keepScreenOn" -> {
                        val enable = call.argument<Boolean>("enable") ?: false
                        runOnUiThread {
                            if (enable) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            }
                            result.success(true)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
