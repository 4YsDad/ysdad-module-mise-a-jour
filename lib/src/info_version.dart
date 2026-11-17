import 'dart:convert';

/// Contenu du fichier JSON de version hébergé.
///
/// ```json
/// {
///   "latestVersionCode": 2028,
///   "versionName": "1.0.0 (28)",
///   "apkUrl": "https://exemple.web.app/dl/xxxx/appli-v28.apk",
///   "notes": "Nouveautés en français",
///   "minVersionCode": 0,
///   "sha256": "facultatif"
/// }
/// ```
class InfoVersion {
  const InfoVersion({
    required this.latestVersionCode,
    required this.versionName,
    required this.apkUrl,
    this.notes = '',
    this.minVersionCode,
    this.sha256,
  });

  /// Dernier versionCode Android publié.
  final int latestVersionCode;

  /// Nom lisible de la version (ex. « 1.0.0 (28) »).
  final String versionName;

  /// Adresse de téléchargement de l'APK.
  final String apkUrl;

  /// Nouveautés, en français. Les sauts de ligne sont conservés.
  final String notes;

  /// Si le versionCode installé est plus bas, la mise à jour est obligatoire.
  final int? minVersionCode;

  /// Empreinte SHA-256 (hexadécimale) de l'APK, vérifiée si présente.
  final String? sha256;

  factory InfoVersion.fromJson(Map<String, dynamic> json) {
    int? entier(Object? v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v.trim());
      return null;
    }

    final latest = entier(json['latestVersionCode']);
    final url = json['apkUrl'];
    if (latest == null || url is! String || url.isEmpty) {
      throw const FormatException(
          'JSON de version invalide : latestVersionCode et apkUrl sont requis.');
    }
    final notes = json['notes'];
    return InfoVersion(
      latestVersionCode: latest,
      versionName: (json['versionName'] ?? '$latest').toString(),
      apkUrl: url,
      notes: notes is List ? notes.join('\n') : (notes ?? '').toString(),
      minVersionCode: entier(json['minVersionCode']),
      sha256: (json['sha256'] as String?)?.trim().toLowerCase(),
    );
  }

  factory InfoVersion.parse(String source) =>
      InfoVersion.fromJson(jsonDecode(source) as Map<String, dynamic>);

  /// Une version plus récente que [installe] est-elle disponible ?
  bool estPlusRecenteQue(int installe) => latestVersionCode > installe;

  /// La mise à jour est-elle obligatoire pour [installe] ?
  bool estObligatoirePour(int installe) =>
      minVersionCode != null && installe < minVersionCode!;
}
