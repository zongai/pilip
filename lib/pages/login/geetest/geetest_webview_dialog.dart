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
  // 官方 gt 初始化脚本（兼容性优于 fullpage.0.0.0）
  static const _gtJsUri = 'https://static.geetest.com/static/js/gt.0.4.9.js';
  // 备用
  static const _fullpageJsUri =
      'https://static.geetest.com/static/js/fullpage.0.0.0.js';
  static const _geetestConfigUri = 'https://api.geetest.com/gettype.php';

  static final WebUri _baseUri = WebUri('https://passport.bilibili.com/');

  String? _statusText;

  /// 桌面端用 PC UA，移动端用 mob；错误 UA 会导致极验拒绝
  static String get _userAgent =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux
          ? BrowserUa.pc
          : BrowserUa.mob;

  static String _buildHtml(String gt, String challenge) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    // 桌面 WebView2 上 bind 弹层常不可见，改用 float 内嵌展示
    final product = (Platform.isWindows || Platform.isMacOS) ? 'float' : 'bind';

    final bridge = Platform.isLinux
        ? "R=(n,o)=>window.webkit.messageHandlers.msgToNative.postMessage(n+':'+JSON.stringify(o))"
        : "R=(n,o)=>{try{window.flutter_inappwebview.callHandler(n,o)}catch(e){console.error(e)}}";

    final js = '''
var C,S,t;
function showErr(msg){
  var e=document.getElementById("E");
  e.style.display="flex";
  e.textContent=msg||"验证失败";
}
function hideErr(){document.getElementById("E").style.display="none"}
function startGeetest(){
  if(!C||!S||t)return;
  hideErr();
  try{
    if(typeof initGeetest==="function"){
      initGeetest(Object.assign({},C,{
        gt:"$gt",
        challenge:"$challenge",
        offline:false,
        new_captcha:true,
        product:"$product",
        width:"100%",
        https:true
      }), function(captchaObj){
        t=captchaObj;
        captchaObj.onSuccess(function(){
          var r=captchaObj.getValidate();
          if(r)R("success",r); else R("error","empty validate");
        });
        captchaObj.onError(function(o){R("error",o);showErr("验证出错，请关闭后重试")});
        captchaObj.onClose(function(){R("close",{})});
        var box=document.getElementById("captcha");
        if(box)captchaObj.appendTo("#captcha");
        if("$product"==="bind")captchaObj.onReady(function(){captchaObj.verify()});
      });
    } else if(typeof Geetest==="function"){
      t=Geetest(Object.assign({},C,{
        gt:"$gt",challenge:"$challenge",offline:false,new_captcha:true,
        product:"$product",width:"100%",https:true,protocol:"https://"
      }));
      t.onSuccess(function(){R("success",t.getValidate())});
      t.onError(function(o){R("error",o);showErr("验证出错")});
      t.onClose(function(){R("close",{})});
      t.onReady(function(){if("$product"==="bind")t.verify()});
    } else {
      showErr("验证脚本未加载");
      R("error","Geetest not defined");
    }
  }catch(e){
    showErr("验证初始化失败: "+e);
    R("error",String(e));
  }
}
geetest_$ts=function(d){
  if(!d||d.status!="success"){
    showErr("验证配置失败");
    R("error",JSON.stringify(d));
    return;
  }
  C=d.data||{};
  startGeetest();
};
function G(){S=1;startGeetest()}
function E(){showErr("验证码脚本加载失败，请检查网络");R("error","script load failed")}
''';

    return '''<!DOCTYPE html><html><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<style>
html,body{margin:0;padding:0;width:100%;height:100%;background:#fff}
#captcha{width:100%;min-height:200px;padding:8px;box-sizing:border-box}
#E{position:fixed;inset:0;display:none;align-items:center;justify-content:center;
color:#c62828;font-size:14px;padding:16px;text-align:center;background:rgba(255,255,255,0.95);z-index:9999}
</style></head>
<body>
<div id="captcha"></div>
<div id="E">正在加载验证…</div>
<script>$bridge;$js</script>
<script src="$_gtJsUri" onload="G()" onerror="loadFullpage()"></script>
<script>
function loadFullpage(){
  var s=document.createElement("script");
  s.src="$_fullpageJsUri";
  s.onload=G;
  s.onerror=E;
  document.body.appendChild(s);
}
</script>
<script src="$_geetestConfigUri?gt=$gt&callback=geetest_$ts" onerror="E()"></script>
</body></html>''';
  }

  void _onError(dynamic args) {
    debugPrint('geetest error: $args');
    if (!mounted) return;
    String msg = '验证失败，请关闭后重试';
    if (args is List && args.isNotEmpty) {
      final a = args.first;
      if (a is String && a.isNotEmpty) {
        msg = a.length > 80 ? '验证失败，请关闭后重试' : a;
      } else if (a is Map) {
        msg = a['msg']?.toString() ?? a['error']?.toString() ?? msg;
      }
    }
    setState(() => _statusText = msg);
  }

  Widget _buildWebView() {
    final html = _buildHtml(widget.gt, widget.challenge);
    return InAppWebView(
      webViewEnvironment: webViewEnvironment,
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        javaScriptCanOpenWindowsAutomatically: true,
        supportMultipleWindows: true,
        forceDark: .OFF,
        useHybridComposition: true,
        useShouldOverrideUrlLoading: true,
        userAgent: _userAgent,
        mixedContentMode: .MIXED_CONTENT_ALWAYS_ALLOW,
        // 极验依赖 localStorage / cookie
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
        verticalScrollBarEnabled: true,
        overScrollMode: .NEVER,
        pageZoom: 1,
        supportZoom: false,
        transparentBackground: false,
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
                final raw = args[0];
                if (raw is Map) {
                  Get.back(result: Map<String, dynamic>.from(raw));
                  return;
                }
              }
              debugPrint('geetest invalid result: $args');
              _onError(['返回结果无效']);
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
        // 忽略子资源错误，只关心主文档
        if (request.isForMainFrame == true && mounted) {
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
          width: 320,
          height: 420,
          child: LinuxWebview(
            initialHtml: html,
            userAgent: _userAgent,
            incognito: false,
            onWebMessageReceived: (msg) {
              final msgStr = msg.toString();
              if (msgStr.startsWith('success:')) {
                final dataStr = msgStr.substring('success:'.length);
                try {
                  final data = jsonDecode(dataStr);
                  Get.back(
                    result: data is Map
                        ? Map<String, dynamic>.from(data as Map)
                        : data,
                  );
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
    final dialogW = size.width < 420 ? size.width * 0.92 : 400.0;
    final dialogH = size.height < 560 ? size.height * 0.6 : 480.0;

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
                  color: Theme.of(context)
                      .colorScheme
                      .surface
                      .withValues(alpha: 0.95),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _statusText!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: () {
                              setState(() => _statusText = null);
                              // 关闭重开由用户点登录重试
                              Get.back();
                            },
                            child: const Text('关闭'),
                          ),
                        ],
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
