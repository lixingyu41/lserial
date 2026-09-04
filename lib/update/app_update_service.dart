import 'app_update_models.dart';
import 'app_update_service_stub.dart'
    if (dart.library.io) 'app_update_service_io.dart'
    as impl;

export 'app_update_models.dart';

AppUpdateService createAppUpdateService() => impl.createAppUpdateService();
