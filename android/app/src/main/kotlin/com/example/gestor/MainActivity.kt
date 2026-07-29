package com.example.gestor

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity: FlutterActivity() {
    companion object {
        // Referenciado também no AndroidManifest.xml
        // (com.google.firebase.messaging.default_notification_channel_id)
        // pra ser o canal padrão usado pelas notificações push do FCM.
        const val CANAL_NOTIFICACOES_ID = "notificacoes_padrao"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        criarCanalDeNotificacao()
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
