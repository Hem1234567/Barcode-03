@file:Suppress("DEPRECATION")
package PKG_PLACEHOLDER

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.bluetooth.*
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.*
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.OutputStream
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Raw byte transport to any printer: Bluetooth Classic (SPP), Bluetooth LE (GATT), USB host.
 * Dart decides what bytes to send (ESC/POS, TSPL, CPCL, ZPL).
 */
@SuppressLint("MissingPermission")
class MainActivity : FlutterActivity() {
    private val exec = Executors.newSingleThreadExecutor()
    private val SPP: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")

    private var mode = ""
    private var socket: BluetoothSocket? = null
    private var out: OutputStream? = null
    private var gatt: BluetoothGatt? = null
    private var gattChar: BluetoothGattCharacteristic? = null
    private var mtu = 23
    @Volatile private var writeLatch: CountDownLatch? = null
    private var usbConn: UsbDeviceConnection? = null
    private var usbIface: UsbInterface? = null
    private var usbOut: UsbEndpoint? = null

    private val adapter: BluetoothAdapter?
        get() = (getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "barcode_studio/printer")
            .setMethodCallHandler { call, result ->
                exec.execute {
                    try {
                        val r: Any? = when (call.method) {
                            "bonded" -> bonded()
                            "usb" -> usbList()
                            "scanBle" -> scanBle(call.argument<Int>("ms") ?: 5000)
                            "connect" -> connect(call.argument<String>("type")!!, call.argument<String>("id")!!)
                            "write" -> write(call.argument<ByteArray>("bytes")!!, call.argument<Int>("delay") ?: 20)
                            "disconnect" -> { close(); true }
                            "isConnected" -> connected()
                            else -> "__nf"
                        }
                        runOnUiThread {
                            if (r == "__nf") result.notImplemented() else result.success(r)
                        }
                    } catch (e: Throwable) {
                        runOnUiThread { result.error("ERR", e.message, null) }
                    }
                }
            }
    }

    // ---------- discovery ----------
    private fun bonded(): List<Map<String, String>> {
        val ad = adapter ?: return emptyList()
        return ad.bondedDevices.map {
            mapOf(
                "name" to (it.name ?: "Unknown"),
                "id" to it.address,
                "type" to if (it.type == BluetoothDevice.DEVICE_TYPE_LE) "ble" else "classic"
            )
        }
    }

    private fun usbList(): List<Map<String, String>> {
        val um = getSystemService(Context.USB_SERVICE) as UsbManager
        return um.deviceList.values.map {
            mapOf(
                "name" to (it.productName ?: "USB device %04X:%04X".format(it.vendorId, it.productId)),
                "id" to it.deviceName,
                "type" to "usb"
            )
        }
    }

    private fun scanBle(ms: Int): List<Map<String, String>> {
        val scanner = adapter?.bluetoothLeScanner ?: return emptyList()
        val found = LinkedHashMap<String, Map<String, String>>()
        val cb = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, r: ScanResult) {
                val n = r.device.name ?: r.scanRecord?.deviceName
                found[r.device.address] = mapOf("name" to (n ?: "Unnamed BLE"), "id" to r.device.address, "type" to "ble")
            }
        }
        scanner.startScan(cb)
        Thread.sleep(ms.toLong())
        scanner.stopScan(cb)
        return found.values.toList()
    }

    // ---------- connect ----------
    private fun connected(): Boolean = when (mode) {
        "classic" -> socket?.isConnected == true
        "ble" -> gattChar != null && gatt != null
        "usb" -> usbConn != null && usbOut != null
        else -> false
    }

    private fun connect(type: String, id: String): Boolean {
        close()
        return when (type) {
            "classic" -> connectClassic(id)
            "ble" -> connectBle(id)
            "usb" -> connectUsb(id)
            else -> false
        }
    }

    private fun connectClassic(addr: String): Boolean {
        val ad = adapter ?: return false
        val dev = ad.getRemoteDevice(addr)
        ad.cancelDiscovery()
        var s: BluetoothSocket? = null
        try {
            s = dev.createRfcommSocketToServiceRecord(SPP)
            s.connect()
        } catch (e: Exception) {
            try { s?.close() } catch (_: Exception) {}
            // Fallback used by many cheap printers
            s = dev.javaClass.getMethod("createRfcommSocket", Int::class.javaPrimitiveType)
                .invoke(dev, 1) as BluetoothSocket
            s.connect()
        }
        socket = s
        out = s!!.outputStream
        mode = "classic"
        return true
    }

    private fun connectBle(addr: String): Boolean {
        val ad = adapter ?: return false
        val dev = ad.getRemoteDevice(addr)
        val ready = CountDownLatch(1)
        val preferred = listOf("ffe1", "ff02", "49535343-8841-43f4-a8d4-ecbe34729bb3", "bef8d6c9-9c21-4c9e-b632-bd58c1009f9f", "ae01", "fff2")
        val cb = object : BluetoothGattCallback() {
            override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
                if (newState == BluetoothProfile.STATE_CONNECTED) {
                    if (!g.requestMtu(185)) g.discoverServices()
                } else {
                    gattChar = null
                    ready.countDown()
                }
            }
            override fun onMtuChanged(g: BluetoothGatt, m: Int, status: Int) {
                mtu = m
                g.discoverServices()
            }
            override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
                val cands = mutableListOf<BluetoothGattCharacteristic>()
                for (svc in g.services) {
                    val su = svc.uuid.toString().lowercase()
                    if (su.startsWith("00001800") || su.startsWith("00001801")) continue
                    for (c in svc.characteristics) {
                        val p = c.properties
                        if (p and (BluetoothGattCharacteristic.PROPERTY_WRITE or BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE) != 0) cands.add(c)
                    }
                }
                gattChar = cands.firstOrNull { c -> preferred.any { c.uuid.toString().lowercase().contains(it) } } ?: cands.firstOrNull()
                ready.countDown()
            }
            override fun onCharacteristicWrite(g: BluetoothGatt, c: BluetoothGattCharacteristic, status: Int) {
                writeLatch?.countDown()
            }
        }
        gatt = dev.connectGatt(this, false, cb, BluetoothDevice.TRANSPORT_LE)
        ready.await(15, TimeUnit.SECONDS)
        if (gattChar == null) { close(); return false }
        mode = "ble"
        return true
    }

    private fun connectUsb(name: String): Boolean {
        val um = getSystemService(Context.USB_SERVICE) as UsbManager
        val dev = um.deviceList[name] ?: return false
        if (!um.hasPermission(dev)) {
            val action = "$packageName.USB_PERMISSION"
            val latch = CountDownLatch(1)
            val rx = object : BroadcastReceiver() {
                override fun onReceive(c: Context, i: Intent) { latch.countDown() }
            }
            val flags = if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0
            val pi = PendingIntent.getBroadcast(this, 0, Intent(action).setPackage(packageName), flags)
            if (Build.VERSION.SDK_INT >= 33) registerReceiver(rx, IntentFilter(action), Context.RECEIVER_NOT_EXPORTED)
            else registerReceiver(rx, IntentFilter(action))
            um.requestPermission(dev, pi)
            latch.await(30, TimeUnit.SECONDS)
            try { unregisterReceiver(rx) } catch (_: Exception) {}
            if (!um.hasPermission(dev)) return false
        }
        var best: Pair<UsbInterface, UsbEndpoint>? = null
        for (i in 0 until dev.interfaceCount) {
            val itf = dev.getInterface(i)
            for (e in 0 until itf.endpointCount) {
                val ep = itf.getEndpoint(e)
                if (ep.type == UsbConstants.USB_ENDPOINT_XFER_BULK && ep.direction == UsbConstants.USB_DIR_OUT) {
                    if (best == null || itf.interfaceClass == UsbConstants.USB_CLASS_PRINTER) best = Pair(itf, ep)
                }
            }
        }
        val (itf, ep) = best ?: return false
        val conn = um.openDevice(dev) ?: return false
        if (!conn.claimInterface(itf, true)) { conn.close(); return false }
        usbConn = conn; usbIface = itf; usbOut = ep; mode = "usb"
        return true
    }

    // ---------- write ----------
    private fun write(bytes: ByteArray, delayMs: Int): Boolean {
        when (mode) {
            "classic" -> {
                val o = out ?: return false
                var i = 0
                while (i < bytes.size) {
                    val n = minOf(1024, bytes.size - i)
                    o.write(bytes, i, n); o.flush()
                    i += n
                    Thread.sleep(delayMs.toLong())
                }
                return true
            }
            "ble" -> {
                val g = gatt ?: return false
                val c = gattChar ?: return false
                val noResp = c.properties and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE != 0
                val type = if (noResp) BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE else BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
                val size = maxOf(20, mtu - 3)
                var i = 0
                while (i < bytes.size) {
                    val part = bytes.copyOfRange(i, minOf(i + size, bytes.size))
                    writeLatch = CountDownLatch(1)
                    if (Build.VERSION.SDK_INT >= 33) {
                        g.writeCharacteristic(c, part, type)
                    } else {
                        c.writeType = type
                        c.value = part
                        g.writeCharacteristic(c)
                    }
                    if (!writeLatch!!.await(3, TimeUnit.SECONDS)) return false
                    Thread.sleep(maxOf(delayMs, 5).toLong())
                    i += size
                }
                return true
            }
            "usb" -> {
                val conn = usbConn ?: return false
                val ep = usbOut ?: return false
                var i = 0
                while (i < bytes.size) {
                    val n = minOf(4096, bytes.size - i)
                    val chunk = bytes.copyOfRange(i, i + n)
                    if (conn.bulkTransfer(ep, chunk, n, 5000) < 0) return false
                    i += n
                }
                return true
            }
        }
        return false
    }

    private fun close() {
        try { out?.close() } catch (_: Exception) {}
        try { socket?.close() } catch (_: Exception) {}
        try { gatt?.disconnect(); gatt?.close() } catch (_: Exception) {}
        try { usbIface?.let { usbConn?.releaseInterface(it) }; usbConn?.close() } catch (_: Exception) {}
        out = null; socket = null; gatt = null; gattChar = null
        usbConn = null; usbIface = null; usbOut = null; mode = ""
    }

    override fun onDestroy() { close(); super.onDestroy() }
}
