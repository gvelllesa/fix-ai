package com.example.ai_car_diagnostics

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var callback: ConnectivityManager.NetworkCallback? = null

    // FTDI USB-Serial K+DCAN state (UNI_Flash.Platform.Android.FtdiInterface parity)
    private val usbExecutor = Executors.newSingleThreadExecutor()
    private var ftdiDevice: UsbDevice? = null
    private var ftdiConnection: UsbDeviceConnection? = null
    private var ftdiInterface: UsbInterface? = null
    private var ftdiBulkIn: UsbEndpoint? = null
    private var ftdiBulkOut: UsbEndpoint? = null

    companion object {
        private const val ACTION_USB_PERMISSION = "com.example.ai_car_diagnostics.USB_PERMISSION"
        private const val FTDI_VID = 0x0403
        private val FTDI_PIDS = setOf(0x6001, 0x6010, 0x6014, 0x6015)

        // FTDI Control Request Constants (USB Vendor Request Out = 0x40)
        private const val FTDI_REQTYPE_OUT = UsbConstants.USB_TYPE_VENDOR or UsbConstants.USB_DIR_OUT
        private const val SIO_RESET = 0x00
        private const val SIO_MODEM_CTRL = 0x01
        private const val SIO_SET_FLOW_CTRL = 0x02
        private const val SIO_SET_BAUD_RATE = 0x03
        private const val SIO_SET_DATA = 0x04
        private const val SIO_SET_LATENCY_TIMER = 0x09

        /**
         * Computes FTDI 3MHz base clock divisor (value, index) for arbitrary baudrates
         * including 10400 baud (BMW K-Line), 115200 baud, and 500000 baud (D-CAN).
         */
        fun computeFtdiDivisor(baudrate: Int): Pair<Int, Int> {
            if (baudrate <= 0) return Pair(0x001A, 0) // Default 115200
            if (baudrate == 3000000) return Pair(0, 0)
            if (baudrate == 2000000) return Pair(1, 0)

            // Sub-integer divisor encoding in eighths: 0, 0.125(3), 0.25(2), 0.375(4), 0.5(1), 0.625(5), 0.75(6), 0.875(7)
            val fracCode = intArrayOf(0, 3, 2, 4, 1, 5, 6, 7)
            val divisor8 = (24000000 + (baudrate / 2)) / baudrate
            val baseDiv = divisor8 shr 3
            val subDiv = fracCode[divisor8 and 0x07]
            val value = (baseDiv and 0x3FFF) or ((subDiv and 0x03) shl 14)
            val index = (subDiv shr 2) and 0x01
            return Pair(value, index)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val usbManager = getSystemService(Context.USB_SERVICE) as UsbManager

        // 1. Wi-Fi / ENET Network Binding Channel
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

        // 2. USB Host FTDI INPA K+DCAN Channel (fixai/usb_ftdi)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fixai/usb_ftdi")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openFtdi" -> {
                        val baudrate = call.argument<Int>("baudrate") ?: 115200
                        val latencyMs = call.argument<Int>("latencyTimerMs") ?: 1
                        val dtr = call.argument<Boolean>("dtr") ?: true
                        val rts = call.argument<Boolean>("rts") ?: false
                        openFtdiDevice(usbManager, baudrate, latencyMs, dtr, rts, result)
                    }
                    "setBaudrate" -> {
                        val baudrate = call.argument<Int>("baudrate") ?: 115200
                        val conn = ftdiConnection
                        if (conn == null) {
                            result.success(false)
                        } else {
                            val (value, index) = computeFtdiDivisor(baudrate)
                            val rc = conn.controlTransfer(FTDI_REQTYPE_OUT, SIO_SET_BAUD_RATE, value, index, null, 0, 500)
                            result.success(rc >= 0)
                        }
                    }
                    "flushBuffers" -> {
                        val conn = ftdiConnection
                        if (conn != null) {
                            conn.controlTransfer(FTDI_REQTYPE_OUT, SIO_RESET, 1, 0, null, 0, 300) // Purge RX
                            conn.controlTransfer(FTDI_REQTYPE_OUT, SIO_RESET, 2, 0, null, 0, 300) // Purge TX
                        }
                        result.success(null)
                    }
                    "isConnected" -> {
                        result.success(ftdiConnection != null && ftdiBulkIn != null && ftdiBulkOut != null)
                    }
                    "transceive" -> {
                        val txBytes = call.argument<ByteArray>("txBytes")
                        val timeoutMs = call.argument<Int>("timeoutMs") ?: 1500
                        if (txBytes == null || ftdiConnection == null) {
                            result.success(null)
                        } else {
                            usbExecutor.execute {
                                val rxBytes = transceiveFtdi(txBytes, timeoutMs)
                                runOnUiThread {
                                    result.success(rxBytes)
                                }
                            }
                        }
                    }
                    "closeFtdi" -> {
                        closeFtdiInternal()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun openFtdiDevice(
        usbManager: UsbManager,
        baudrate: Int,
        latencyMs: Int,
        dtr: Boolean,
        rts: Boolean,
        result: MethodChannel.Result
    ) {
        val candidate = usbManager.deviceList.values.firstOrNull { dev ->
            dev.vendorId == FTDI_VID && FTDI_PIDS.contains(dev.productId)
        } ?: usbManager.deviceList.values.firstOrNull()

        if (candidate == null) {
            result.success(false)
            return
        }

        if (!usbManager.hasPermission(candidate)) {
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            val pi = PendingIntent.getBroadcast(this, 0, Intent(ACTION_USB_PERMISSION), flags)
            val receiver = object : BroadcastReceiver() {
                override fun onReceive(ctx: Context, intent: Intent) {
                    if (ACTION_USB_PERMISSION == intent.action) {
                        runCatching { unregisterReceiver(this) }
                        val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                        if (granted) {
                            result.success(configureFtdiConnection(usbManager, candidate, baudrate, latencyMs, dtr, rts))
                        } else {
                            result.success(false)
                        }
                    }
                }
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(receiver, IntentFilter(ACTION_USB_PERMISSION), Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(receiver, IntentFilter(ACTION_USB_PERMISSION))
            }
            usbManager.requestPermission(candidate, pi)
            return
        }

        result.success(configureFtdiConnection(usbManager, candidate, baudrate, latencyMs, dtr, rts))
    }

    private fun configureFtdiConnection(
        usbManager: UsbManager,
        device: UsbDevice,
        baudrate: Int,
        latencyMs: Int,
        dtr: Boolean,
        rts: Boolean
    ): Boolean {
        closeFtdiInternal()
        if (device.interfaceCount < 1) return false

        val usbIf = device.getInterface(0)
        val conn = usbManager.openDevice(device) ?: return false
        if (!conn.claimInterface(usbIf, true)) {
            conn.close()
            return false
        }

        var epIn: UsbEndpoint? = null
        var epOut: UsbEndpoint? = null
        for (i in 0 until usbIf.endpointCount) {
            val ep = usbIf.getEndpoint(i)
            if (ep.type == UsbConstants.USB_ENDPOINT_XFER_BULK) {
                if (ep.direction == UsbConstants.USB_DIR_IN) epIn = ep
                else if (ep.direction == UsbConstants.USB_DIR_OUT) epOut = ep
            }
        }
        if (epIn == null || epOut == null) {
            conn.releaseInterface(usbIf)
            conn.close()
            return false
        }

        // 1. Reset FTDI SIO & purge FIFOs
        conn.controlTransfer(FTDI_REQTYPE_OUT, SIO_RESET, 0, 0, null, 0, 500)
        conn.controlTransfer(FTDI_REQTYPE_OUT, SIO_RESET, 1, 0, null, 0, 500)
        conn.controlTransfer(FTDI_REQTYPE_OUT, SIO_RESET, 2, 0, null, 0, 500)

        // 2. Configure 8N1 data format (8 data bits, 1 stop bit, no parity)
        conn.controlTransfer(FTDI_REQTYPE_OUT, SIO_SET_DATA, 0x0008, 0, null, 0, 500)

        // 3. Disable flow control
        conn.controlTransfer(FTDI_REQTYPE_OUT, SIO_SET_FLOW_CTRL, 0, 0, null, 0, 500)

        // 4. Configure 1ms Latency Timer for fast KWP2000 / D-CAN P2 timing
        conn.controlTransfer(FTDI_REQTYPE_OUT, SIO_SET_LATENCY_TIMER, latencyMs.coerceIn(1, 255), 0, null, 0, 500)

        // 5. Configure Baudrate (10400 K-Line or 115200 / 500000 D-CAN)
        val (divValue, divIndex) = computeFtdiDivisor(baudrate)
        conn.controlTransfer(FTDI_REQTYPE_OUT, SIO_SET_BAUD_RATE, divValue, divIndex, null, 0, 500)

        // 6. Set DTR / RTS modem control lines (used by INPA K+DCAN for ignition sense / K-Line state)
        val dtrVal = if (dtr) 0x0101 else 0x0100
        val rtsVal = if (rts) 0x0202 else 0x0200
        conn.controlTransfer(FTDI_REQTYPE_OUT, SIO_MODEM_CTRL, dtrVal or rtsVal, 0, null, 0, 500)

        ftdiDevice = device
        ftdiConnection = conn
        ftdiInterface = usbIf
        ftdiBulkIn = epIn
        ftdiBulkOut = epOut
        return true
    }

    /**
     * Transmits [txBytes] on FTDI Bulk OUT and reads back the KWP2000 response on Bulk IN,
     * stripping the 2-byte FTDI modem status header from each 64-byte USB packet.
     */
    private fun transceiveFtdi(txBytes: ByteArray, timeoutMs: Int): ByteArray? {
        val conn = ftdiConnection ?: return null
        val epOut = ftdiBulkOut ?: return null
        val epIn = ftdiBulkIn ?: return null

        val written = conn.bulkTransfer(epOut, txBytes, txBytes.size, timeoutMs.coerceAtLeast(300))
        if (written < 0) return null

        val outBuffer = ByteArrayOutputStream()
        val packetBuf = ByteArray(epIn.maxPacketSize.coerceAtLeast(64))
        val deadline = System.currentTimeMillis() + timeoutMs
        var lastDataTime = System.currentTimeMillis()

        while (System.currentTimeMillis() < deadline) {
            val readLen = conn.bulkTransfer(epIn, packetBuf, packetBuf.size, 50)
            if (readLen > 2) {
                // First 2 bytes of every FTDI Bulk IN packet are modem/line status bytes
                outBuffer.write(packetBuf, 2, readLen - 2)
                lastDataTime = System.currentTimeMillis()
            } else if (outBuffer.size() > txBytes.size && (System.currentTimeMillis() - lastDataTime) >= 35) {
                // Received more than TX echo and line has been idle for >= 35ms (KWP P3 inter-frame gap)
                break
            }
        }

        return if (outBuffer.size() > 0) outBuffer.toByteArray() else null
    }

    private fun closeFtdiInternal() {
        runCatching {
            ftdiInterface?.let { ftdiConnection?.releaseInterface(it) }
            ftdiConnection?.close()
        }
        ftdiInterface = null
        ftdiConnection = null
        ftdiDevice = null
        ftdiBulkIn = null
        ftdiBulkOut = null
    }

    override fun onDestroy() {
        closeFtdiInternal()
        usbExecutor.shutdownNow()
        super.onDestroy()
    }
}
