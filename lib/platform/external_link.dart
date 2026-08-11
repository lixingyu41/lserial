import 'external_link_stub.dart'
    if (dart.library.io) 'external_link_io.dart'
    if (dart.library.js_interop) 'external_link_web.dart'
    as impl;

Future<void> openExternalLink(Uri uri) => impl.openExternalLink(uri);
