import 'dart:convert' show jsonDecode;
import 'dart:io' show Platform;

import 'package:PiliPlus/http/browser_ua.dart';
import 'package:PiliPlus/main.dart';
import 'package:PiliPlus/plugin/linux_webview.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class GeetestWebviewDialog extends StatefulWidget {
  const GeetestWebviewDialog(this.gt, this.challenge, {super.key});

  final String gt;
  final String challenge;

  @override
  State<GeetestWebviewDialog> createState() => _GeetestWebviewDialogState();

  static Future<Map<String, dynamic>?> geetest(String gt, String challenge) {
    final ctx = Get.context;
    if (ctx == null || !ctx.mounted) {
      return Future.value(null);
    }
    return showDialog<Map<String, dynamic>>(
      context: ctx,
      barrierDismissible: true,
      builder: (context) => GeetestWebviewDialog(gt, challenge),
    );
  }
}

class _GeetestWebviewDialogState extends State<GeetestWebviewDialog> {
  static const _geetestJsUri =
      'https://static.geetest.com/static/js/fullpage.0.0.0.js';
  static const _geetestConfigUri = 'https://api.geetest.com/gettype.php';

  // 使用 bilibili 域名作为 base，避免 about:blank 下脚本/接口被拦
  static final WebUri _baseUri = WebUri('https://www.bilibili.com/');

  String? _statusText;

  static String _buildHtml(String gt, String challenge) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final js =
        'var C,S,T,t;'
        'T=()=>{if(C&&S&&!t){try{'
        'document.getElementById("E").style.display="none";'
        't=Geetest(C).onSuccess(()=>R("success",t.getValidate())).onError(o=>R("error",o)).onClose(o=>R("close",o));'
        't.onReady(()=>t.verify())'
        '}catch(e){document.getElementById("E").style.display="flex";'
        'document.getElementById("E").textContent="验证初始化失败: "+e;R("error",String(e))}}};'
        'geetest_$ts=(d)=>{'
        'if(!d||d.status!="success"){'
        'document.getElementById("E").style.display="flex";'
        'document.getElementById("E").textContent="验证配置失败";'
        'R("error",JSON.stringify(d));return};'
        'C=Object.assign({gt:"$gt",challenge:"$challenge",offline:false,new_captcha:true,product:"bind",width:"100%",https:true,protocol:"https://"},d.data);T()'
        '};'
        'G=()=>{S=1;T()};'
        'E=()=>{var e=document.getElementById("E");e.style.display="flex";e.textContent="验证码加载失败，请检查网络后重试";R("error","geetest script load failed")}';

    return '<!DOCTYPE html><html><head>'
        '<meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">'
        '</head>'
        '<style>'
        'html,body{margin:0;padding:0;width:100%;height:100%;background:transparent}'
        '#E{position:fixed;inset:0;display:none;align-items:center;justify-content:center;'
        'color:#c62828;font-size:14px;padding:16px;text-align:center;background:rgba(255,255,255,0.92)}'
        '</style>'
        '<body><div id="E">正在加载验证…</div>'
        '<script>'
        '${Platform.isLinux ? "R=(n,o)=>window.webkit.messageHandlers.msgToNative.postMessage(n+':'+JSON.stringify(o))" : "R=(n,o)=>{try{window.flutter_inappwebview.callHandler(n,o)}catch(e){console.log(e)}}"};$js'
        '</script>'
        '<script src="$_geetestJsUri" onload="G()" onerror="E()"></script>'
        '<script src="$_geetestConfigUri?gt=$gt&callback=geetest_$ts" onerror="E()"></script>'
        '</body></html>';
  }

  void _onError(dynamic args) {
    debugPrint('geetest error: $args');
    if (mounted) {
      setState(() {
        _statusText = '验证失败，请关闭后重试';
      });
    }
  }

  Widget _buildWebView() {
    final html = _buildHtml(widget.gt, widget.challenge);
    return InAppWebView(
      webViewEnvironment: webViewEnvironment,
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        forceDark: ForceDark.AUTO,
        useHybridComposition: true,
        useShouldOverrideUrlLoading: true,
        userAgent: BrowserUa.mob,
        mixedContentMode: .MIXED_CONTENT_ALWAYS_ALLOW,
        // 极验需要 DOM Storage；过度禁用会导致空白
        domStorageEnabled: true,
        databaseEnabled: true,
        cacheEnabled: true,
        thirdPartyCookiesEnabled: true,
        clearCache: false,
        incognito: false,
        allowFileAccess: false,
        allowsLinkPreview: false,
        geolocationEnabled: false,
        horizontalScrollBarEnabled: false,
        verticalScrollBarEnabled: false,
        overScrollMode: .NEVER,
        // iOS 过大 zoom 会导致内容跑出可视区看起来像空白
        pageZoom: 1,
        supportZoom: false,
      ),
      initialData: InAppWebViewInitialData(
        data: html,
        baseUrl: _baseUri,
        mimeType: 'text/html',
        encoding: 'utf-8',
      ),
      onWebViewCreated: (ctr) {
        ctr
          ..addJavaScriptHandler(
            handlerName: 'success',
            callback: (args) {
              if (args.isNotEmpty) {
                if (args[0] case Map data) {
                  Get.back(result: Map<String, dynamic>.from(data));
                  return;
                }
              }
              debugPrint('geetest invalid result: $args');
            },
          )
          ..addJavaScriptHandler(
            handlerName: 'error',
            callback: (args) => _onError(args),
          )
          ..addJavaScriptHandler(
            handlerName: 'close',
            callback: (args) => Get.back(),
          );
      },
      onReceivedError: (controller, request, error) {
        debugPrint('geetest load error: ${error.description}');
        if (mounted) {
          setState(() {
            _statusText = '页面加载失败：${error.description}';
          });
        }
      },
      onConsoleMessage: (controller, msg) {
        if (msg.messageLevel == ConsoleMessageLevel.ERROR) {
          debugPrint('geetest console: ${msg.message}');
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isLinux) {
      final html = _buildHtml(widget.gt, widget.challenge);
      return AlertDialog(
        title: const Text('安全验证'),
        content: SizedBox(
          width: 300,
          height: 400,
          child: LinuxWebview(
            initialHtml: html,
            userAgent: BrowserUa.mob,
            incognito: true,
            onWebMessageReceived: (msg) {
              final msgStr = msg.toString();
              if (msgStr.startsWith('success:')) {
                final dataStr = msgStr.substring('success:'.length);
                try {
                  final data = jsonDecode(dataStr);
                  Get.back(result: data is Map ? Map<String, dynamic>.from(data as Map) : data);
                } catch (e) {
                  debugPrint('geetest decode error: $e');
                }
              } else if (msgStr.startsWith('error:')) {
                debugPrint('geetest error: $msgStr');
              } else if (msgStr.startsWith('close:')) {
                Get.back();
              }
            },
          ),
        ),
      );
    }

    final size = MediaQuery.sizeOf(context);
    final dialogW = size.width < 420 ? size.width * 0.92 : 380.0;
    final dialogH = size.height < 560 ? size.height * 0.55 : 420.0;

    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('安全验证')),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: Get.back,
            tooltip: '关闭',
          ),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      content: SizedBox(
        width: dialogW,
        height: dialogH,
        child: Stack(
          children: [
            Positioned.fill(child: _buildWebView()),
            if (_statusText != null)
              Positioned.fill(
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _statusText!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
