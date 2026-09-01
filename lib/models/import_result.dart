/// Resultado de una importación masiva de lecturas.
///
/// Inmutable: se construye al terminar y se pasa a la UI tal cual. La UI
/// lee los contadores y la lista de errores para armar el resumen visual.
class ImportResult {
  const ImportResult({
    required this.totalProcessed,
    required this.totalImported,
    required this.totalDuplicates,
    required this.totalNsfw,
    required this.totalErrors,
    required this.totalSkipped,
    required this.importedByExtension,
    required this.errors,
    required this.elapsed,
    this.limitReached = false,
  });

  /// URLs que pasaron el parseo y se intentaron procesar.
  final int totalProcessed;

  /// Títulos importados con éxito (guardados en la BD).
  final int totalImported;

  /// Títulos que ya existían en la biblioteca/historial.
  final int totalDuplicates;

  /// Títulos enviados a la Zona +18 (están incluidos en [totalImported]).
  final int totalNsfw;

  /// Links que fallaron (extensión no disponible, sitio caído, etc).
  final int totalErrors;

  /// Fragmentos descartados en el parseo (no eran URLs válidas).
  final int totalSkipped;

  /// Desglose por extensión: nombre de la extensión → cantidad importada.
  final Map<String, int> importedByExtension;

  /// Detalle de cada error individual.
  final List<ImportError> errors;

  /// Cuánto tardó toda la importación.
  final Duration elapsed;

  /// True si se llegó al tope de URLs y quedaron sin procesar.
  final bool limitReached;
}

/// Un link individual que falló, con su motivo.
class ImportError {
  const ImportError({required this.url, required this.reason});

  final String url;
  final String reason;
}
