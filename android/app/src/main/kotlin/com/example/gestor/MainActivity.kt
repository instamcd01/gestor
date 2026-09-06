package com.example.gestor

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    companion object {
        // Referenciado também no AndroidManifest.xml
        // (com.google.firebase.messaging.default_notification_channel_id)
        // pra ser o canal padrão usado pelas notificações push do FCM.
        const val CANAL_NOTIFICACOES_ID = "notificacoes_padrao"

        // Usado pelo PushNotificationService (Dart) pra tocar som/vibrar quando
        // um push de "novo pedido" chega com o app aberto — o FCM não faz isso
        // sozinho em primeiro plano (só em segundo plano/fechado, via o canal
        // acima). Toca o som de notificação já configurado no aparelho em vez
        // de empacotar um áudio próprio.
        private const val CANAL_METODO_ALERTA = "gestor/notificacao_alerta"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        criarCanalDeNotificacao()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CANAL_METODO_ALERTA).setMethodCallHandler { call, result ->
            when (call.method) {
                "tocarSom" -> {
                    tocarSomNotificacaoPadrao()
                    result.success(null)
                }
                "vibrar" -> {
                    vibrarAlerta()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun tocarSomNotificacaoPadrao() {
        try {
            val uri = RingtoneManager.getActualDefaultRingtoneUri(this, RingtoneManager.TYPE_NOTIFICATION)
            RingtoneManager.getRingtone(this, uri)?.play()
        } catch (e: Exception) {
            // Silencioso — pior caso é só não tocar som, não deve derrubar o app.
        }
    }

    private fun vibrarAlerta() {
        try {
            val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(VibrationEffect.createOneShot(500, VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(500)
            }
        } catch (e: Exception) {
            // Silencioso — mesmo critério do som acima.
        }
    }

    // Sem isso, o FCM cria um canal de importância padrão/baixa na primeira
    // notificação recebida — sem som nem banner (heads-up). Precisa existir
    // ANTES da primeira mensagem chegar, por isso é criado aqui e não sob
    // demanda.
    private fun criarCanalDeNotificacao() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val canal = NotificationChannel(
            CANAL_NOTIFICACOES_ID,
            "Notificações",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Estoque, pedidos, despesas e marketplace"
        }

        val manager = getSystemService(NotificationManager::class.java)
        manager?.createNotificationChannel(canal)
    }
}
