import 'package:get/get.dart';
import 'package:prismhub/models/index.dart';
import 'package:prismhub/data/services/database_service.dart';

class HomePageController extends GetxController {
  final RxList<History> resents = <History>[].obs;
  // All favorited types mixed together (Home shows one "Favoritos" section,
  // not one per type — the History page's Favoritos tab still lets you see
  // where each one came from).
  final RxList<Favorite> favorites = <Favorite>[].obs;

  @override
  void onInit() {
    onRefresh();
    super.onInit();
  }

  refreshHistory() async {
    // Fetch first, THEN swap — clearing before the await let the "no
    // history" empty state flash on screen for every refresh (including
    // the one that fires on every visit to Home), even when there was
    // data the whole time.
    final data = await DatabaseService.getHistorysByType();
    resents.value = data;
  }

  onRefresh() async {
    // Kick off both independent reads before awaiting either — this runs
    // history and favorites queries concurrently instead of back-to-back,
    // which was doubling the wait every time Home reloads (e.g. every time
    // you back out of a reader/player — see reader_controller.dart and
    // video_controller.dart, both call this on close).
    final historyFuture = DatabaseService.getHistorysByType();
    final favoritesFuture = DatabaseService.getFavoritesByType(limit: 20);
    resents.value = await historyFuture;
    favorites.value = await favoritesFuture;
  }
}
