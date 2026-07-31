import 'package:isar/isar.dart';
import 'package:prismhub/models/extension.dart';

part 'history.g.dart';

@collection
class History {
  Id id = Isar.autoIncrement;
  @Index(name: 'package&url', composite: [CompositeIndex('url')])
  late String package;
  late String url;
  // 截图，保存封面地址
  String? cover;
  @Enumerated(EnumType.name)
  late ExtensionType type;
  // 不同线路
  late int episodeGroupId;
  // 不同线路下的集数
  late int episodeId;
  // 显示的标题
  late String title;
  // 进度标题
  late String episodeTitle;
  // 当前剧集/章节进度
  late String progress;
  // 当前章节/剧集总进度
  late String totalProgress;
  DateTime date = DateTime.now();
  // Zona +18: true si este ítem se guardó desde una extensión 100% NSFW o
  // desde la opción "adultos" de un filtro de una extensión mixta (ver
  // ExtensionFilter.adultOption). Determina si aparece en el Continuar
  // normal de Home o solo dentro de la Zona +18.
  bool isNsfw = false;
}
