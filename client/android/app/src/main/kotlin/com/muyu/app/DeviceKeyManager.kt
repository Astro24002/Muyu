package com.muyu.app

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.Signature
import java.util.Base64

class DeviceKeyManager(private val context: Context) : MethodChannel.MethodCallHandler {
    private val keyStoreName = "AndroidKeyStore"
    private val alias = "muyu-device-signing-key"

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "getOrCreatePublicKey" -> result.success(getOrCreatePublicKey())
                "sign" -> result.success(sign(call.argument<String>("payload") ?: ""))
                "deleteKey" -> {
                    deleteKey()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            result.error("DEVICE_KEY_ERROR", error.message, null)
        }
    }

    private fun getOrCreatePublicKey(): String {
        val keyStore = KeyStore.getInstance(keyStoreName).apply { load(null) }
        if (!keyStore.containsAlias(alias)) {
            val generator = KeyPairGenerator.getInstance(
                KeyProperties.KEY_ALGORITHM_EC,
                keyStoreName,
            )
            generator.initialize(
                KeyGenParameterSpec.Builder(
                    alias,
                    KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY,
                )
                    .setAlgorithmParameterSpec(java.security.spec.ECGenParameterSpec("secp256r1"))
                    .setDigests(KeyProperties.DIGEST_SHA256)
                    .build(),
            )
            generator.generateKeyPair()
        }
        return Base64.getEncoder().encodeToString(keyStore.getCertificate(alias).publicKey.encoded)
    }

    private fun sign(payload: String): String {
        val keyStore = KeyStore.getInstance(keyStoreName).apply { load(null) }
        val privateKey = keyStore.getKey(alias, null) as? PrivateKey
            ?: throw IllegalStateException("device key not found")
        return Base64.getEncoder().encodeToString(
            Signature.getInstance("SHA256withECDSA").run {
                initSign(privateKey)
                update(Base64.getDecoder().decode(payload))
                sign()
            },
        )
    }

    private fun deleteKey() {
        KeyStore.getInstance(keyStoreName).apply {
            load(null)
            deleteEntry(alias)
        }
    }
}
