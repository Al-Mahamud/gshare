import '../core/constants.dart';
import '../core/identity.dart';
import '../core/models.dart';
import '../core/settings.dart';
import '../platform/native_bridge.dart';
import 'discovery/discovery_service.dart';
import 'receive_manager.dart';
import 'selection.dart';
import 'send_manager.dart';
import 'server.dart';
import 'transfer_log.dart';

/// Wires the app's long-lived services together.
class AppServices {
  AppServices._(this.identity, this.settings)
      : log = TransferLog(),
        selection = SendSelection() {
    receiver = ReceiveManager(identity: identity, settings: settings, log: log);
    server = GshareServer(identity: identity, selfInfo: () => self, receiver: receiver);
    sender = SendManager(self: () => self, log: log);
    discovery = DiscoveryService(self: () => self);
  }

  static AppServices? _instance;
  static AppServices get I => _instance!;

  final Identity identity;
  final AppSettings settings;
  final TransferLog log;
  final SendSelection selection;
  late final ReceiveManager receiver;
  late final GshareServer server;
  late final SendManager sender;
  late final DiscoveryService discovery;

  DeviceInfo get self => DeviceInfo(
        id: identity.fingerprint,
        name: settings.deviceName,
        platform: DevicePlatform.current,
        port: server.port,
      );

  static Future<void> init() async {
    if (_instance != null) return;
    NativeBridge.init();
    final settings = await AppSettings.load();
    final identity = await Identity.loadOrCreate();
    final services = AppServices._(identity, settings);
    await services.server.start(kDefaultPort);
    _instance = services;
    await services.discovery.start();
  }
}
