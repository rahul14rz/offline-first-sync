import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'src/local/local_store.dart';
import 'src/orders_controller.dart';
import 'src/sync/sync_api.dart';
import 'src/sync/sync_engine.dart';
import 'src/sync/sync_scheduler.dart';
import 'src/ui/orders_screen.dart';

/// Set with --dart-define=API_URL=http://host:3000/. The Android emulator reaches the host
/// machine at 10.0.2.2.
const _apiUrlOverride = String.fromEnvironment('API_URL');

Uri get apiUrl => Uri.parse(
  _apiUrlOverride.isNotEmpty
      ? _apiUrlOverride
      : Platform.isAndroid
      ? 'http://10.0.2.2:3000/'
      : 'http://localhost:3000/',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationSupportDirectory();
  final store = LocalStore.open(p.join(dir.path, 'orders.sqlite'));
  final engine = SyncEngine(store, SyncApi(baseUrl: apiUrl));
  final scheduler = SyncScheduler(engine.syncOnce)..start();
  runApp(OrdersApp(controller: OrdersController(store, scheduler)));
}

class OrdersApp extends StatelessWidget {
  const OrdersApp({super.key, required this.controller});

  final OrdersController controller;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Offline orders',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: Colors.teal),
    home: OrdersScreen(controller: controller),
  );
}
