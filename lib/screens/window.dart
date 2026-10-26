import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:simple_barcode_scanner/constant.dart';
import 'package:simple_barcode_scanner/enum.dart';
import 'package:webview_windows/webview_windows.dart';

class WindowBarcodeScanner extends StatefulWidget {
  final String lineColor;
  final String cancelButtonText;
  final bool isShowFlashIcon;
  final ScanType scanType;
  final Function(String) onScanned;
  final String? appBarTitle;
  final bool? centerTitle;
  final bool isShowDebugInfo;

  const WindowBarcodeScanner({
    Key? key,
    required this.lineColor,
    required this.cancelButtonText,
    required this.isShowFlashIcon,
    required this.scanType,
    required this.onScanned,
    this.appBarTitle,
    this.centerTitle,
    this.isShowDebugInfo = false,
  }) : super(key: key);

  @override
  State<WindowBarcodeScanner> createState() => _WindowBarcodeScannerState();
}

class _WindowBarcodeScannerState extends State<WindowBarcodeScanner> {
  /// Created once, so rebuilds (e.g. window resize) don't re-initialize the webview
  /// and don't ask for the camera permission again
  final WebviewController controller = WebviewController();
  late final Future<bool> initFuture;
  StreamSubscription? webMessageSubscription;

  @override
  void initState() {
    super.initState();
    initFuture = initPlatformState();
  }

  @override
  void dispose() {
    webMessageSubscription?.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.appBarTitle ?? kScanPageTitle),
        centerTitle: widget.centerTitle,
        leading: IconButton(
          onPressed: () {
            /// send close event to web-view
            controller.postWebMessage(json.encode({"event": "close"}));
            Navigator.pop(context);
          },
          icon: const Icon(Icons.arrow_back_ios),
        ),
      ),
      body: FutureBuilder<bool>(
          future: initFuture,
          builder: (context, snapshot) {
            if (snapshot.hasData && snapshot.data != null) {
              /// The webview fills the available space, and follows the window size
              return SizedBox.expand(
                child: Webview(
                  controller,
                  permissionRequested: onPermissionRequested,
                ),
              );
            } else if (snapshot.hasError) {
              return Center(
                child: Text(snapshot.error.toString()),
              );
            }
            return const Center(
              child: CircularProgressIndicator(),
            );
          }),
    );
  }

  /// The webview only loads the scanner page bundled with this package, which only needs the camera,
  /// so the camera permission is allowed directly without showing the permission dialog every time
  Future<WebviewPermissionDecision> onPermissionRequested(
      String url, WebviewPermissionKind kind, bool isUserInitiated) async {
    if (kind == WebviewPermissionKind.camera) {
      return WebviewPermissionDecision.allow;
    }

    return WebviewPermissionDecision.deny;
  }

  String getAssetFileUrl({required String asset}) {
    final assetsDirectory = p.join(p.dirname(Platform.resolvedExecutable),
        'data', 'flutter_assets', asset);
    return Uri.file(assetsDirectory).toString();
  }

  /// Scan type that is read by the scanner page to decide the scan box shape
  String get scanTypeParam {
    switch (widget.scanType) {
      case ScanType.qr:
        return "qr";
      case ScanType.barcode:
        return "barcode";
      case ScanType.defaultMode:
        return "default";
    }
  }

  Future<bool> initPlatformState() async {
    String? barcodeNumber;

    try {
      await controller.initialize();
      await controller.loadUrl(
          "${getAssetFileUrl(asset: PackageConstant.barcodeFilePath)}?type=$scanTypeParam&debug=${widget.isShowDebugInfo ? 1 : 0}");

      /// Listen to web to receive barcode
      webMessageSubscription = controller.webMessage.listen((event) {
        if (event['methodName'] == "successCallback") {
          if (event['data'] is String &&
              event['data'].isNotEmpty &&
              barcodeNumber == null) {
            barcodeNumber = event['data'];
            widget.onScanned(barcodeNumber!);
          }
        }
      });
    } catch (e) {
      rethrow;
    }
    return true;
  }
}
