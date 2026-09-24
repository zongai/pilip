import 'dart:async';

import 'package:PiliPlus/common/widgets/dialog/dialog.dart';
import 'package:PiliPlus/common/widgets/dialog/report_member.dart';
import 'package:PiliPlus/grpc/bilibili/app/im/v1.pb.dart';
import 'package:PiliPlus/grpc/im.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/msg.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models_new/msg/im_user_infos/datum.dart';
import 'package:PiliPlus/models_new/msg/msg_dnd/uid_setting.dart';
import 'package:PiliPlus/models_new/msg/session_ss/data.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/global_data.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/widgets.dart' show Text;
import 'package:get/get.dart';

class WhisperLinkSettingController extends GetxController {
  WhisperLinkSettingController({
    required this.talkerUid,
  });

  final int talkerUid;
  RxBool isPinned = false.obs;
  late final sessionId = SessionId(
    privateId: PrivateId(talkerUid: Int64(talkerUid)),
  );

  @override
  void onInit() {
    super.onInit();
    getUserInfo();
    getSessionSs();
    getMsgDnd();
    getIsPinned();
  }

  final Rx<LoadingState<List<ImUserInfosData>?>> userState =
      LoadingState<List<ImUserInfosData>?>.loading().obs;
  final Rx<LoadingState<SessionSsData>> sessionSs =
      LoadingState<SessionSsData>.loading().obs;
  final Rx<LoadingState<List<UidSetting>?>> msgDnd =
      LoadingState<List<UidSetting>?>.loading().obs;

  Future<void> getUserInfo() async {
    userState.value = await MsgHttp.imUserInfos(uids: talkerUid.toString());
  }

  Future<void> getSessionSs() async {
    sessionSs.value = await MsgHttp.getSessionSs(talkerUid: talkerUid);
  }

  Future<void> getMsgDnd() async {
    msgDnd.value = await MsgHttp.getMsgDnd(uidsStr: talkerUid);
  }

  Future<void> getIsPinned() async {
    final res = await ImGrpc.sessionUpdate(sessionId: sessionId);
    if (res case Success(:final response)) {
      isPinned.value = response.session.isPinned;
    }
  }

  void setPush(bool isPush) {
    if (isPush) {
      showConfirmDialog(
        context: Get.context!,
        title: const Text('确认关闭内容推送吗？'),
        content: const Text('若关闭此开关，你将不再收到该账号的图文消息与稿件推送，但通知类消息不受影响'),
        onConfirm: () => _setPush(isPush),
      );
      return;
    }
    _setPush(isPush);
  }

  Future<void> _setPush(bool isPush) async {
    int setting = isPush ? 1 : 0;
    final res = await MsgHttp.setPushSs(
      setting: setting,
      talkerUid: talkerUid,
    );
    if (res.isSuccess) {
      sessionSs
        ..value.data.pushSetting = setting
        ..refresh();
    } else {
      res.toast();
    }
  }

  Future<void> setPin() async {
    final res = isPinned.value
        ? await ImGrpc.unpinSession(sessionId: sessionId)
        : await ImGrpc.pinSession(sessionId: sessionId);
    if (res.isSuccess) {
      isPinned.toggle();
    } else {
      res.toast();
    }
  }

  Future<void> setMute(bool isMuted) async {
    int setting = isMuted ? 0 : 1;
    final res = await MsgHttp.setMsgDnd(
      uid: Accounts.main.mid,
      setting: setting,
      dndUid: talkerUid,
    );
    if (res.isSuccess) {
      msgDnd
        ..value.data!.first.setting = setting
        ..refresh();
    } else {
      res.toast();
    }
  }

  /// 黑名单：完全本地，无需登录
  Future<void> setBlock(bool isBlocked) async {
    if (isBlocked) {
      Pref.removeBlackMid(talkerUid);
      if (sessionSs.value case Success(:final response)) {
        sessionSs
          ..value = Success(response..followStatus = null)
          ..refresh();
      }
    } else {
      showConfirmDialog(
        context: Get.context!,
        title: const Text('确认加入黑名单'),
        content: const Text('加入黑名单后，将在本地隐藏该用户相关内容（无需登录，不与官方同步）'),
        onConfirm: () async {
          Pref.setBlackMid(talkerUid);
          if (sessionSs.value case Success(:final response)) {
            sessionSs
              ..value = Success(response..followStatus = 128)
              ..refresh();
          }
        },
      );
    }
  }

  bool get isLocalBlocked => GlobalData().blackMids.contains(talkerUid);

  void report() => showMemberReportDialog(
    Get.context!,
    name: userState.value.dataOrNull?.firstOrNull?.name,
    mid: talkerUid,
  );
}
