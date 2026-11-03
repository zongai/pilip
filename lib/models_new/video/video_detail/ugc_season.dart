import 'package:PiliPlus/models_new/video/video_detail/section.dart';

class UgcSeason {
  int? id;
  String? title;
  String? cover;
  int? mid;
  List<SectionItem>? sections;

  UgcSeason({
    this.id,
    this.title,
    this.cover,
    this.mid,
    this.sections,
  });

  static int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v');
  }

  factory UgcSeason.fromJson(Map<String, dynamic> json) => UgcSeason(
    // 部分接口 id 为字符串/num，严格 as int? 会丢掉
    id: _asInt(json['id'] ?? json['season_id']),
    title: json['title'] as String?,
    cover: json['cover'] as String?,
    mid: _asInt(json['mid']),
    sections: (json['sections'] as List<dynamic>?)
        ?.map((e) => SectionItem.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}
