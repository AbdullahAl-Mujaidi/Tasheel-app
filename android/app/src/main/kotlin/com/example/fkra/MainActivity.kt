package com.example.fkra

import android.content.Intent
import android.net.Uri
import android.provider.Telephony
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tasahel/sms")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openDefaultSmsApp" -> {
                        val phone = call.argument<String>("phone").orEmpty()
                        val body = call.argument<String>("body").orEmpty()
                        if (phone.isEmpty()) {
                            result.error("no_phone", "رقم الهاتف فارغ", null)
                        } else {
                            result.success(openDefaultSmsApp(phone, body))
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun openDefaultSmsApp(phone: String, body: String): Boolean {
        return try {
            val smsIntent = Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:$phone")).apply {
                putExtra("sms_body", body)
                putExtra(Intent.EXTRA_TEXT, body)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            val defaultSmsPackage = Telephony.Sms.getDefaultSmsPackage(applicationContext)
            if (!defaultSmsPackage.isNullOrEmpty()) {
                smsIntent.setPackage(defaultSmsPackage)
            }
            startActivity(smsIntent)
            true
        } catch (e: Exception) {
            false
        }
    }
}