import 'package:isar/isar.dart';
import 'package:prismhub/models/extension.dart';

part 'history.g.dart';

/// Punto del USUARIO dentro de lo que ya salió.
///
/// Es un eje INDEPENDIENTE de si la obra terminó (ver [History.seriesFinished]):
/// algo puede estar finalizado —ya no publica más— y seguir en `pending` porque
/// al usuario le faltan capítulos. Meter las dos cosas en un solo estado
/// obligaría a elegir cuál gana y perdería información.
enum WatchState {
  /// Empezado y con capítulos/episodios por delante. Estado inicial: se pone
  /// solo al abrir el primero.
  pending,

  /// Al día: se vio el último que había. Sale de "Continuar" hasta que aparezca
  /// algo nuevo.
  completed,
}

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

  // ── Seguimiento ───────────────────────────────────────────────────────────
  //
  // Campos NUEVOS (base v3), todos con valor por defecto a propósito: Isar
  // completa con ese valor los registros guardados antes de que existieran, así
  // que no hace falta recorrer y reescribir el historial de nadie. Un historial
  // viejo queda como `pending` y sin novedades, que es justo lo correcto.

  /// Ver [WatchState]. Solo tiene sentido en contenido por capítulos: en una
  /// película queda en `pending` y no se muestra en ningún lado.
  @Enumerated(EnumType.name)
  WatchState watchState = WatchState.pending;

  /// La OBRA terminó de publicarse. Lo marca el usuario en el Detalle, porque
  /// no todas las extensiones informan el estado y las que lo hacen no usan el
  /// mismo vocabulario.
  bool seriesFinished = false;

  /// Cuántos capítulos/episodios tenía la obra la última vez que se miró. Es la
  /// referencia contra la que se detecta que salió algo nuevo.
  ///
  /// En 0 significa "todavía no se contó": la primera comprobación solo guarda
  /// el número, sin anunciar nada. Sin esa salvedad, al estrenar la función
  /// todo el historial viejo aparecería como novedad de golpe.
  int knownEpisodeCount = 0;

  /// Nombre del capítulo/episodio nuevo detectado, para mostrarlo en la
  /// tarjeta. `null` = sin novedades. Se limpia al abrir el ítem.
  String? newEpisodeLabel;

  /// Cuándo se comprobó por última vez si había algo nuevo. Evita repetir la
  /// consulta a la extensión más de una vez cada N horas: es una petición de
  /// red por obra y sin freno vuelve lento el Home.
  DateTime? lastCheckedAt;

  /// Atajo de lectura: hay algo nuevo esperando.
  @ignore
  bool get hasNewEpisode => newEpisodeLabel != null;
}
