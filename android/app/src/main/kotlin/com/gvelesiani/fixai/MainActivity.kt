package com.gvelesiani.fixai

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.InetAddress
import java.net.URL
import android.net.LinkProperties
import android.content.Intent
import android.provider.Settings
import io.flutter.plugin.common.EventChannel
import android.os.Handler
import android.os.Looper
import android.system.ErrnoException
import java.net.ConnectException
import java.net.InetSocketAddress
import java.net.Socket
import java.net.SocketTimeoutException

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.gvelesiani.fixai/cellular_routing"

    /// Network references are written from ConnectivityManager binder threads
    /// (onAvailable / onLost / onCapabilitiesChanged) and read from the main
    /// thread (method channel handlers). `@Volatile` establishes a
    /// happens-before relationship so the main thread always sees the latest
    /// reference rather than a thread-local cached copy. Without it, the
    /// method channel handler could read a stale `null` for `vehicleNetwork`
    /// even after `onAvailable` fired on the binder thread, causing
    /// `bindProcessToVehicleNetwork` to return false and the OBD socket to
    /// fail on the rerouting path.
    @Volatile private var cellularNetwork: Network? = null
    @Volatile private var vehicleNetwork: Network? = null

    /// True iff the current system default network has validated internet.
    /// Written from the default-network binder callback, read from the
    /// `getConnectivitySnapshot` handler — same cross-thread story as above.
    @Volatile private var defaultHasInternet: Boolean = false

    /// The most recently available Wi-Fi or Ethernet network on the device.
    /// This is the network the OBD adapter (ELM327 Wi-Fi) or the ENET cable
    /// lives on. Tracked so that, while an OBD socket is open, we can bind
    /// the *process* to it via [bindProcessToNetwork] — which forces all
    /// `dart:io` sockets (including OBD) to use this link even when Samsung's
    /// "Avoid bad Wi-Fi" has rerouted the system default to cellular.
    ///
    /// CRITICAL: we never auto-bind the process to cellular. Binding to
    /// cellular would make OBD sockets to private LAN addresses
    /// (192.168.0.10, 169.254.1.1) unreachable — that was the regression.
    /// Instead, cellular is used only by [executeHttpRequestOnCellular],
    /// which calls [cellularNetwork.openConnection] directly and so bypasses
    /// the process binding entirely. The two mechanisms are independent and
    /// compose cleanly:
    ///   * API HTTP  → always via cellular (binding-independent).
    ///   * OBD socket → always via Wi-Fi/Ethernet (process-bound for the
    ///     duration of the OBD session, released on disconnect).
    /// (Field declared `@Volatile` near the top of the class — written from
    /// binder threads, read from the main thread.)

    /// Explicit tracking of whether the process is currently bound to the
    /// vehicle network by [bindProcessToVehicleNetwork]. Set true on a
    /// successful bind, false on release or when the vehicle network is lost.
    /// `getConnectivitySnapshot` reads this so the diagnostic reports the
    /// actual binding state, not just whether a vehicle network exists.
    /// Also `@Volatile`: written from binder-thread `onLost`, read from
    /// main-thread method handlers.
    @Volatile private var isProcessBound: Boolean = false

    /// Native ENET TCP socket bound to [vehicleNetwork] via [Network.bindSocket].
    /// dart:io sockets fail with errno 113 on Samsung when cellular is active;
    /// this path bypasses that limitation.
    @Volatile private var vehicleSocket: Socket? = null
    @Volatile private var vehicleSocketReader: Thread? = null
    private val vehicleTcpHandler = Handler(Looper.getMainLooper())
    @Volatile private var vehicleTcpEventSink: EventChannel.EventSink? = null

    /// Monotonic connect generation counter. Bumped on every new
    /// `vehicleTcpConnect`. The reader thread captures the generation it was
    /// started with and only posts `endOfStream`/error events if the sink
    /// still belongs to THAT generation. This prevents a stale reader from a
    /// previous (already-closed) attempt from racing a fresh connect and
    /// sending `endOfStream`, which on the Dart side fired `onDone` →
    /// `disconnect()` → "ENET socket is not open" during HSFZ handshake.
    @Volatile private var vehicleTcpGeneration: Int = 0

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        registerCellularNetworkCallback()
        registerVehicleNetworkCallback()
        registerDefaultNetworkCallback()

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.gvelesiani.fixai/vehicle_tcp_rx"
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                vehicleTcpEventSink = events
            }

            override fun onCancel(arguments: Any?) {
                vehicleTcpEventSink = null
            }
        })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "sendRequest" -> {
                    val url = call.argument<String>("url")!!
                    val method = call.argument<String>("method")!!
                    val headers = call.argument<Map<String, String>>("headers")
                    val body = call.argument<ByteArray>("body")

                    CoroutineScope(Dispatchers.IO).launch {
                        try {
                            val response = executeHttpRequestOnCellular(url, method, headers, body)
                            withContext(Dispatchers.Main) {
                                result.success(response)
                            }
                        } catch (e: Exception) {
                            withContext(Dispatchers.Main) {
                                result.error("HTTP_ERROR", e.localizedMessage, null)
                            }
                        }
                    }
                }
                "probeCellularInternet" -> {
                    CoroutineScope(Dispatchers.IO).launch {
                        val ok = withTimeoutOrNull(3000L) {
                            probeCellularInternet()
                        } ?: false
                        withContext(Dispatchers.Main) {
                            result.success(ok)
                        }
                    }
                }
                "bindProcessToVehicleNetwork" -> {
                    // Called by WifiStrategy/EnetStrategy right before opening
                    // the OBD socket. Binds the whole process to the Wi-Fi /
                    // Ethernet network so the socket actually reaches the
                    // adapter even when Samsung has rerouted the default.
                    refreshVehicleNetworkFromActiveNetworks()
                    val ok = bindProcessToVehicleNetwork()
                    result.success(ok)
                }
                "releaseProcessBinding" -> {
                    // Called by WifiStrategy/EnetStrategy in disconnect() /
                    // dispose(). Restores the system default routing so API
                    // traffic flows normally again.
                    val ok = releaseProcessBinding()
                    result.success(ok)
                }
                "getConnectivitySnapshot" -> {
                    result.success(mapOf(
                        "vehicleNetworkAvailable" to (vehicleNetwork != null),
                        "cellularNetworkAvailable" to (cellularNetwork != null),
                        "defaultHasInternet" to defaultHasInternet,
                        "isProcessBound" to isProcessBound
                    ))
                }
                "getVehicleGatewayIp" -> {
                    refreshVehicleNetworkFromActiveNetworks()
                    val gateway = getVehicleGatewayIp()
                    result.success(gateway)
                }
                "getLocalWifiIp" -> {
                    // Returns the phone's own IPv4 on the active vehicle
                    // network, or null. Used by the connection dialog to warn
                    // the user if they typed their own local IP into the
                    // adapter/gateway field (a very common mistake — it causes
                    // "No route to host" because the socket connects to self).
                    refreshVehicleNetworkFromActiveNetworks()
                    val local = getLocalWifiIp()
                    result.success(local)
                }
                "openWifiSettings" -> {
                    openWifiSettings()
                    result.success(true)
                }
                "openMobileDataSettings" -> {
                    openMobileDataSettings()
                    result.success(true)
                }
                "vehicleTcpConnect" -> {
                    val host = call.argument<String>("host") ?: ""
                    val port = call.argument<Int>("port") ?: 0
                    val timeoutMs = call.argument<Int>("timeoutMs") ?: 4000
                    CoroutineScope(Dispatchers.IO).launch {
                        // FIX #1 (native): hard-close any stale socket from a
                        // previous attempt BEFORE opening a new one. A prior
                        // connect that was torn down on the Dart side (e.g. the
                        // user tapped Connect again, or a previous HSFZ
                        // handshake failed) could leave `vehicleSocket` half-
                        // open; the new connect would then either reuse it
                        // silently or get an immediate peer RST because the ZGW
                        // still thinks the old session is alive. Forcing a clean
                        // teardown here guarantees a fresh TCP session per
                        // connect attempt — exactly what ProTool does.
                        hardCloseVehicleTcpSocket()
                        val map = vehicleTcpConnect(host, port, timeoutMs)
                        withContext(Dispatchers.Main) { result.success(map) }
                    }
                }
                "vehicleTcpWrite" -> {
                    val data = call.argument<ByteArray>("data") ?: byteArrayOf()
                    val ok = vehicleTcpWrite(data)
                    result.success(ok)
                }
                "vehicleTcpClose" -> {
                    closeVehicleTcpSocket()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    /// Returns true iff the pinned cellular [Network] can resolve a well-known
    /// hostname. Run on a worker thread because [Network.getAllByName]
    /// performs I/O. Hostnames only — a literal IP (e.g. "1.1.1.1") returns
    /// from the resolver without any network I/O and would produce a false
    /// positive on a dead link, so we deliberately exclude those.
    private suspend fun probeCellularInternet(): Boolean {
        val network = cellularNetwork ?: return false
        val hosts = listOf("dns.google", "example.com")
        for (host in hosts) {
            try {
                val addrs: Array<InetAddress> = network.getAllByName(host)
                if (addrs.any { it.address.isNotEmpty() }) return true
            } catch (_: Exception) {
                // Try the next host.
            }
        }
        return false
    }

    private fun registerCellularNetworkCallback() {
        try {
            val connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val request = NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_CELLULAR)
                .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .build()

            connectivityManager.requestNetwork(request, object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    super.onAvailable(network)
                    cellularNetwork = network
                }

                override fun onLost(network: Network) {
                    super.onLost(network)
                    if (cellularNetwork == network) {
                        cellularNetwork = null
                    }
                }
            })
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    /// Tracks the active Wi-Fi or Ethernet network. We deliberately do NOT
    /// require `NET_CAPABILITY_VALIDATED_INTERNET` here — the whole point is
    /// that the OBD adapter network has no internet, so a validated-only
    /// request would never see it. We track any Wi-Fi or Ethernet transport:
    ///   * TRANSPORT_WIFI covers ELM327 Wi-Fi clones and Wi-Fi ENET adapters
    ///     (192.168.0.10).
    ///   * TRANSPORT_ETHERNET covers ENET USB-Ethernet dongles, which Android
    ///     classifies as Ethernet and exposes at 169.254.1.1. Without this,
    ///     ENET-cable scans would never get a process binding and would fall
    ///     back to source-address binding only — exactly the fragile path
    ///     Samsung's "Avoid bad Wi-Fi" breaks.
    private fun registerVehicleNetworkCallback() {
        try {
            val connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            for (transport in intArrayOf(
                NetworkCapabilities.TRANSPORT_WIFI,
                NetworkCapabilities.TRANSPORT_ETHERNET
            )) {
                val request = NetworkRequest.Builder()
                    .addTransportType(transport)
                    .build()
                connectivityManager.requestNetwork(request, object : ConnectivityManager.NetworkCallback() {
                    override fun onAvailable(network: Network) {
                        super.onAvailable(network)
                        vehicleNetwork = network
                    }

                    override fun onLost(network: Network) {
                        super.onLost(network)
                        if (vehicleNetwork == network) {
                            vehicleNetwork = null
                            // If the OBD session is still notionally open and the
                            // vehicle network went away, drop the binding so we
                            // don't pin the process to a dead network. MUST run
                            // on the main thread — `bindProcessToNetwork` is a
                            // main-thread API and this callback fires on a binder
                            // thread; calling it directly silently fails or throws
                            // on Samsung One UI.
                            runOnUiThread { releaseProcessBinding() }
                        }
                    }
                })
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    /// Tracks the system default network for the `getConnectivitySnapshot`
    /// diagnostic. Not used to drive automatic binding — that was the
    /// regression.
    private fun registerDefaultNetworkCallback() {
        try {
            val connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            connectivityManager.registerDefaultNetworkCallback(object : ConnectivityManager.NetworkCallback() {
                override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) {
                    super.onCapabilitiesChanged(network, capabilities)
                    defaultHasInternet = capabilities.hasCapability(
                        NetworkCapabilities.NET_CAPABILITY_VALIDATED
                    ) && capabilities.hasCapability(
                        NetworkCapabilities.NET_CAPABILITY_INTERNET
                    )
                }

                override fun onLost(network: Network) {
                    super.onLost(network)
                    defaultHasInternet = false
                }
            })
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    /// Scans [ConnectivityManager.allNetworks] for an active Wi-Fi or Ethernet
    /// link. The [NetworkCallback] may have missed a network that was already
    /// up when the app launched — that left [vehicleNetwork] null and caused
    /// errno 113 on Samsung even though the phone was on ENET_WIFI.
    ///
    /// Prefers ENET_WIFI (192.168.16.x) over generic home Wi-Fi.
    private fun refreshVehicleNetworkFromActiveNetworks() {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return
        var best: Network? = null
        var bestScore = -1
        try {
            for (network in cm.allNetworks) {
                val caps = cm.getNetworkCapabilities(network) ?: continue
                val isWifi = caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)
                val isEth = caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
                if (!isWifi && !isEth) continue

                var score = if (isWifi) 10 else 5
                val localIp = localIpv4OnNetwork(cm, network)
                when {
                    localIp?.startsWith("192.168.16.") == true -> score += 100
                    localIp?.startsWith("192.168.0.") == true -> score += 50
                    localIp?.startsWith("169.254.") == true -> score += 40
                }
                if (score > bestScore) {
                    bestScore = score
                    best = network
                }
            }
            if (best != null) {
                vehicleNetwork = best
            }
        } catch (e: Exception) {
            android.util.Log.e("CellularRouting", "refreshVehicleNetwork failed", e)
        }
    }

    private fun localIpv4OnNetwork(cm: ConnectivityManager, network: Network): String? {
        return try {
            val lp = cm.getLinkProperties(network) ?: return null
            for (addr in lp.linkAddresses) {
                val ia = addr.address
                if (ia.address.size == 4) {
                    val host = ia.hostAddress ?: continue
                    if (host.startsWith("169.254.")) continue
                    return host
                }
            }
            null
        } catch (_: Exception) {
            null
        }
    }

    private fun openWifiSettings() {
        startActivity(
            Intent(Settings.ACTION_WIFI_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }

    private fun openMobileDataSettings() {
        try {
            startActivity(
                Intent(Settings.ACTION_WIRELESS_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        } catch (e: Exception) {
            startActivity(
                Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        }
    }

    /// Opens a TCP socket on the active vehicle Wi-Fi/Ethernet using
    /// [Network.getSocketFactory] — required on Samsung when cellular is active.
    private fun vehicleTcpConnect(host: String, port: Int, timeoutMs: Int): Map<String, Any?> {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager

        if (isCellularDefaultRoute(cm)) {
            return mapOf(
                "ok" to false,
                "errno" to 113,
                "message" to "Mobile data is the system default route. Turn OFF "
                    + "Mobile Data in Settings, then retry ENET.",
                "cellularDefault" to true
            )
        }

        val network = resolveVehicleNetworkForHost(host, cm)
        if (network == null) {
            return mapOf(
                "ok" to false,
                "errno" to 113,
                "message" to "No vehicle Wi-Fi/Ethernet network detected. Join ENET_WIFI first."
            )
        }

        vehicleNetwork = network
        bindProcessToVehicleNetwork()

        val localIp = localIpv4OnNetwork(cm!!, network)
        val methods = if (host.startsWith("192.168.16.")) {
            // Samsung ENET_WIFI: explicit bindSocket is more reliable than
            // socketFactory when the AP gateway is 192.168.16.1 but the
            // adapter listens on .101.
            listOf("bindSocket", "socketFactory")
        } else {
            listOf("socketFactory", "bindSocket")
        }

        var lastFailure: Map<String, Any?>? = null
        for (method in methods) {
            val result = attemptVehicleTcpConnect(
                network, host, port, timeoutMs, method, localIp
            )
            if (result["ok"] == true) return result
            lastFailure = result
            val errno = result["errno"] as? Int ?: 0
            // Retry with the other binding strategy only on routing errors.
            if (errno != 113) break
        }
        return lastFailure ?: mapOf(
            "ok" to false,
            "errno" to 113,
            "message" to "No route to host ($host)",
            "localIp" to localIp
        )
    }

    private fun attemptVehicleTcpConnect(
        network: Network,
        host: String,
        port: Int,
        timeoutMs: Int,
        method: String,
        localIp: String?
    ): Map<String, Any?> {
        return try {
            closeVehicleTcpSocket(endStream = false)
            // FIX #1 (native): bump the generation so any reader thread from a
            // previous attempt can no longer post events to the EventSink.
            vehicleTcpGeneration++
            val generation = vehicleTcpGeneration
            val socket = when (method) {
                "bindSocket" -> {
                    val s = Socket()
                    network.bindSocket(s)
                    s
                }
                else -> network.socketFactory.createSocket()
            }
            socket.tcpNoDelay = true
            socket.connect(InetSocketAddress(host, port), timeoutMs)
            vehicleSocket = socket
            startVehicleSocketReader(socket, generation)
            android.util.Log.i(
                "VehicleTcp",
                "connected $host:$port via $method (local=$localIp, gen=$generation)"
            )
            mapOf(
                "ok" to true,
                "localIp" to localIp,
                "viaNative" to true,
                "connectMethod" to method,
                "generation" to generation
            )
        } catch (e: SocketTimeoutException) {
            android.util.Log.e("VehicleTcp", "timeout $host:$port ($method)", e)
            closeVehicleTcpSocket()
            mapOf(
                "ok" to false,
                "errno" to 110,
                "message" to "Connection timed out ($host:$port)",
                "localIp" to localIp,
                "connectMethod" to method
            )
        } catch (e: ConnectException) {
            val errno = (e.cause as? ErrnoException)?.errno ?: 111
            android.util.Log.e(
                "VehicleTcp",
                "connect failed $host:$port errno=$errno ($method)",
                e
            )
            closeVehicleTcpSocket()
            mapOf(
                "ok" to false,
                "errno" to errno,
                "message" to (e.message ?: "Connection refused"),
                "localIp" to localIp,
                "connectMethod" to method
            )
        } catch (e: ErrnoException) {
            android.util.Log.e("VehicleTcp", "errno ${e.errno} $host:$port ($method)", e)
            closeVehicleTcpSocket()
            mapOf(
                "ok" to false,
                "errno" to e.errno,
                "message" to (e.message ?: "Network error"),
                "localIp" to localIp,
                "connectMethod" to method
            )
        } catch (e: Exception) {
            android.util.Log.e("VehicleTcp", "unexpected $host:$port ($method)", e)
            closeVehicleTcpSocket()
            mapOf(
                "ok" to false,
                "errno" to 113,
                "message" to (e.message ?: "No route to host"),
                "localIp" to localIp,
                "connectMethod" to method
            )
        }
    }

    private fun isCellularDefaultRoute(cm: ConnectivityManager?): Boolean {
        if (cm == null) return false
        val active = cm.activeNetwork ?: return false
        val caps = cm.getNetworkCapabilities(active) ?: return false
        return caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) &&
            caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
    }

    /// Picks the Wi-Fi/Ethernet [Network] whose local IPv4 is on the same
    /// subnet as [host] (e.g. phone 192.168.16.102 → ENET 192.168.16.101).
    private fun resolveVehicleNetworkForHost(
        host: String,
        cm: ConnectivityManager?
    ): Network? {
        refreshVehicleNetworkFromActiveNetworks()
        if (cm == null) return vehicleNetwork

        val hostParts = host.split('.')
        val subnetPrefix = if (hostParts.size == 4) {
            "${hostParts[0]}.${hostParts[1]}.${hostParts[2]}."
        } else {
            null
        }

        var best: Network? = null
        var bestScore = -1
        for (network in cm.allNetworks) {
            val caps = cm.getNetworkCapabilities(network) ?: continue
            val isWifi = caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)
            val isEth = caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
            if (!isWifi && !isEth) continue

            val localIp = localIpv4OnNetwork(cm, network) ?: continue
            if (subnetPrefix != null && !localIp.startsWith(subnetPrefix)) continue

            var score = if (isWifi) 10 else 5
            if (localIp.startsWith("192.168.16.")) score += 100
            if (score > bestScore) {
                bestScore = score
                best = network
            }
        }
        return best ?: vehicleNetwork
    }

    private fun vehicleTcpWrite(data: ByteArray): Boolean {
        return try {
            val socket = vehicleSocket ?: return false
            socket.getOutputStream().write(data)
            socket.getOutputStream().flush()
            true
        } catch (e: Exception) {
            android.util.Log.e("VehicleTcp", "write failed", e)
            false
        }
    }

    private fun closeVehicleTcpSocket(endStream: Boolean = true) {
        // Bump the generation on every teardown so any in-flight reader thread
        // from this attempt stops posting events the moment we close.
        vehicleTcpGeneration++
        vehicleSocketReader?.interrupt()
        vehicleSocketReader = null
        try {
            vehicleSocket?.close()
        } catch (_: Exception) {
        }
        vehicleSocket = null
        if (endStream) {
            vehicleTcpHandler.post {
                vehicleTcpEventSink?.endOfStream()
            }
        }
    }

    /// FIX #1 (native): unconditional hard teardown used right before a fresh
    /// connect. Unlike [closeVehicleTcpSocket], this ALWAYS bumps the
    /// generation and tears down the socket + reader even if a prior session
    /// was left in a bad state, guaranteeing no stale socket is reused.
    private fun hardCloseVehicleTcpSocket() {
        vehicleTcpGeneration++
        val reader = vehicleSocketReader
        vehicleSocketReader = null
        reader?.interrupt()
        val s = vehicleSocket
        vehicleSocket = null
        if (s != null) {
            try {
                if (!s.isClosed) s.close()
            } catch (e: Exception) {
                android.util.Log.w("VehicleTcp", "hardClose: socket close error", e)
            }
        }
    }

    private fun startVehicleSocketReader(socket: Socket, generation: Int) {
        vehicleSocketReader?.interrupt()
        vehicleSocketReader = Thread {
            val buffer = ByteArray(8192)
            var localSawEof = false
            try {
                val input = socket.getInputStream()
                while (!Thread.currentThread().isInterrupted) {
                    val read = input.read(buffer)
                    if (read <= 0) {
                        localSawEof = true
                        break
                    }
                    val chunk = buffer.copyOf(read)
                    // FIX #1 (native): only forward data while this reader is
                    // still the active generation. A newer connect may have
                    // already replaced us; posting stale bytes would corrupt
                    // the new session's frame buffer.
                    if (generation != vehicleTcpGeneration) break
                    vehicleTcpHandler.post {
                        if (generation == vehicleTcpGeneration) {
                            vehicleTcpEventSink?.success(chunk)
                        }
                    }
                }
            } catch (e: Exception) {
                if (!Thread.currentThread().isInterrupted &&
                    generation == vehicleTcpGeneration) {
                    vehicleTcpHandler.post {
                        if (generation == vehicleTcpGeneration) {
                            vehicleTcpEventSink?.error("SOCKET_ERROR", e.message, null)
                        }
                    }
                }
            } finally {
                // FIX #1 (native): only emit endOfStream if this reader is
                // still the active generation. Previously EVERY reader emitted
                // endOfStream from its finally block, so a stale reader from a
                // torn-down attempt could fire endOfStream into a brand-new
                // session — on the Dart side that became onDone → disconnect()
                // → "ENET socket is not open" during HSFZ handshake.
                if (generation == vehicleTcpGeneration) {
                    vehicleTcpHandler.post {
                        if (generation == vehicleTcpGeneration) {
                            vehicleTcpEventSink?.endOfStream()
                        }
                    }
                }
                android.util.Log.i(
                    "VehicleTcp",
                    "reader gen=$generation exiting (eof=$localSawEof, " +
                        "active=${generation == vehicleTcpGeneration})"
                )
            }
        }.apply {
            name = "VehicleTcpReader"
            isDaemon = true
            start()
        }
    }

    /// Binds the process to the Wi-Fi/Ethernet network. Called from Dart
    /// immediately before opening an OBD socket. After this call, all
    /// `dart:io` sockets (including the OBD socket to 192.168.0.10 /
    /// 169.254.1.1) will be opened on the vehicle network regardless of the
    /// system default route. Cellular-bound HTTP via
    /// [executeHttpRequestOnCellular] is unaffected because it uses
    /// [Network.openConnection] directly, bypassing the process binding.
    ///
    /// Returns false if no vehicle network is currently available.
    private fun bindProcessToVehicleNetwork(): Boolean {
        val network = vehicleNetwork ?: return false
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return false
        return try {
            val ok = cm.bindProcessToNetwork(network)
            isProcessBound = ok
            ok
        } catch (e: Exception) {
            android.util.Log.e("CellularRouting", "bindProcessToVehicleNetwork failed", e)
            isProcessBound = false
            false
        }
    }

    /// Clears any active process binding, restoring system-default routing.
    /// Called from Dart in OBD disconnect()/dispose(). Idempotent.
    private fun releaseProcessBinding(): Boolean {
        isProcessBound = false
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return false
        return try {
            cm.bindProcessToNetwork(null)
        } catch (e: Exception) {
            android.util.Log.e("CellularRouting", "releaseProcessBinding failed", e)
            false
        }
    }

    /// Returns the default gateway IPv4 of the active vehicle (Wi-Fi or
    /// Ethernet) network, or null when it can't be determined.
    ///
    /// Reads it from the network's [LinkProperties].getRoutes(): each
    /// [RouteInfo] carries a `gateway`. We pick the IPv4 default route's
    /// gateway — that's the address the ENET/ELM327 adapter listens on
    /// (e.g. 192.168.16.254 on the ENET_WIFI network in the bug report).
    ///
    /// This is the native half of the "don't make the user type the IP"
    /// fix: the connection dialog calls this to auto-fill and sanity-check
    /// the gateway field, so the user can no longer accidentally paste
    /// their phone's own IP (192.168.16.102) into the adapter field.
    ///
    /// CRITICAL — the "Found gateway 0.0.0.0" bug: many ENET/ELM327 Wi-Fi
    /// adapters act as a standalone AP with no upstream. Android then
    /// advertises the default route as `0.0.0.0/0` with a gateway of
    /// `0.0.0.0` (the "any"/unspecified address). Returning that makes the
    /// Dart side try `Socket.connect("0.0.0.0", 13400)`, which always fails.
    /// We must reject the unspecified address and loopback here; the Dart
    /// scanner will then fall back to deriving the adapter IP from our own
    /// link address (e.g. 192.168.0.x → 192.168.0.10).
    private fun getVehicleGatewayIp(): String? {
        val network = vehicleNetwork ?: return null
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return null
        return try {
            val lp = cm.getLinkProperties(network) ?: return null
            // Prefer the default (no host route) IPv4 gateway.
            for (route in lp.routes) {
                val gw = route.gateway ?: continue
                val host = ipv4GatewayOrNull(gw) ?: continue
                return host
            }
            // Fall back to any non-loopback IPv4 gateway on a host route.
            for (route in lp.routes) {
                val gw = route.gateway ?: continue
                val host = ipv4GatewayOrNull(gw) ?: continue
                return host
            }
            null
        } catch (e: Exception) {
            android.util.Log.e("CellularRouting", "getVehicleGatewayIp failed", e)
            null
        }
    }

    /// Returns the dotted-IPv4 form of [addr] iff it is a usable gateway
    /// (IPv4, non-loopback, non-link-local, non-unspecified), else null.
    /// Centralizes the "is this a real gateway?" filter so the two loops
    /// above stay identical and the 0.0.0.0 regression can't slip back in.
    private fun ipv4GatewayOrNull(addr: InetAddress?): String? {
        if (addr == null) return null
        if (addr.address.size != 4) return null // IPv6 gateways are irrelevant here.
        val host = addr.hostAddress ?: return null
        // Reject the unspecified address (0.0.0.0) — this is the root cause
        // of the "Found gateway 0.0.0.0" ENET failure. It is NOT a usable
        // destination; connecting to it always times out.
        if (host == "0.0.0.0") return null
        if (host == "127.0.0.1") return null
        // Link-local self routes (169.254.x) are not adapter addresses.
        if (host.startsWith("169.254.")) return null
        return host
    }

    /// Returns the phone's own IPv4 on the active vehicle network, or null.
    /// Used to detect the "user typed their own IP" mistake.
    private fun getLocalWifiIp(): String? {
        val network = vehicleNetwork ?: return null
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return null
        return try {
            val lp = cm.getLinkProperties(network) ?: return null
            for (addr in lp.linkAddresses) {
                val ia = addr.address
                if (ia is InetAddress && ia.address.size == 4) {
                    val host = ia.hostAddress ?: continue
                    if (host.startsWith("169.254.")) continue
                    return host
                }
            }
            null
        } catch (e: Exception) {
            android.util.Log.e("CellularRouting", "getLocalWifiIp failed", e)
            null
        }
    }

    private fun executeHttpRequestOnCellular(
        urlString: String,
        method: String,
        headers: Map<String, String>?,
        body: ByteArray?
    ): Map<String, Any> {
        val url = URL(urlString)

        // IMPORTANT: cellular-bound HTTP bypasses the process binding because
        // it calls `cellularNetwork.openConnection(url)` directly on the
        // cellular Network object — not `url.openConnection()`. So even when
        // the process is bound to the vehicle Wi-Fi for an OBD session, API
        // traffic still flows over cellular. This is the key invariant that
        // lets OBD-over-Wi-Fi and API-over-cellular coexist.
        val connection = if (cellularNetwork != null) {
            cellularNetwork!!.openConnection(url) as HttpURLConnection
        } else {
            url.openConnection() as HttpURLConnection
        }

        connection.requestMethod = method
        connection.connectTimeout = 15000
        connection.readTimeout = 15000

        headers?.forEach { (key, value) ->
            connection.setRequestProperty(key, value)
        }

        if (body != null && body.isNotEmpty()) {
            connection.doOutput = true
            connection.outputStream.use { os ->
                os.write(body)
            }
        }

        connection.connect()

        val statusCode = connection.responseCode
        val responseHeaders = mutableMapOf<String, String>()
        connection.headerFields.forEach { (key, valueList) ->
            if (key != null && valueList.isNotEmpty()) {
                responseHeaders[key] = valueList.joinToString(", ")
            }
        }

        val stream = if (statusCode in 200..299) {
            connection.inputStream
        } else {
            connection.errorStream ?: connection.inputStream
        }

        val responseBody = stream?.use { it.readBytes() } ?: ByteArray(0)

        return mapOf(
            "statusCode" to statusCode,
            "headers" to responseHeaders,
            "body" to responseBody
        )
    }
}
