-dontwarn com.squareup.inject.assisted.Assisted
-dontwarn com.squareup.inject.assisted.AssistedInject
-dontwarn javax.script.ScriptEngineFactory

# Preserve the Paho MQTT Service, which is required for MQTT communication.
-keep class org.eclipse.paho.android.service.MqttService { *; }

# Preserve the MobileHub core service and broadcast receiver.
# These are called from the Flutter plugin and must not be obfuscated or removed.
-keep class br.pucrio.inf.lac.mobilehub.core.MobileHubService { *; }
-keep class br.pucrio.inf.lac.mobilehub.core.MobileHubServiceStopReceiver { *; }