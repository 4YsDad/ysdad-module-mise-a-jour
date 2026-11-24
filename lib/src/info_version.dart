import 'dart:convert';

/// Contenu du fichier JSON de version hébergé.
///
/// ```json
/// {
///   "latestVersionCode": 2028,
///   "versionName": "28",
///   "versionLabel": "28",
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
    this.storeUrl,
    this.versionLabel,
    this.notes = '',
    this.minVersionCode,
    this.sha256,
  });

  /// Dernier versionCode Android publié.
  final int latestVersionCode;

  /// Nom lisible de la version (ex. « 1.0.0 (28) »).
  final String versionName;

  /// Libellé court affiché à l'utilisateur (ex. « 30 »). Facultatif :
  /// sinon [versionName] est utilisé.
  final String? versionLabel;

  /// Texte affiché : « 30 » dans « Nouvelle version 30 disponible ».
  String get libelle {
    final l = versionLabel?.trim();
    if (l != null && l.isNotEmpty) return l;
    return versionName;
  }

  /// Adresse de téléchargement de l'APK (vide en mode magasin).
  final String apkUrl;

  /// Page du magasin (ex. Google Play). Utilisée en mode magasin : le module
  /// ouvre cette page au lieu de télécharger un APK.
  final String? storeUrl;

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
    final store = json['storeUrl'];
    final aApk = url is String && url.isNotEmpty;
    final aStore = store is String && store.isNotEmpty;
    if (latest == null || (!aApk && !aStore)) {
      throw const FormatException(
          'JSON de version invalide : latestVersionCode et apkUrl '
          '(ou storeUrl) sont requis.');
    }
    final notes = json['notes'];
    return InfoVersion(
      latestVersionCode: latest,
      versionName: (json['versionName'] ?? '$latest').toString(),
      apkUrl: aApk ? url : '',
      storeUrl: aStore ? store : null,
      versionLabel: json['versionLabel']?.toString(),
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

/// Libellé court d'une version installée, pour afficher « version 30 »
/// plutôt que « 1.0.0 (2030) ».
///
/// * Si [versionName] est un simple nombre (« 30 ») ou commence par « v »,
///   il est utilisé tel quel.
/// * Sinon, le numéro de build est utilisé ; les décalages ajoutés par
///   `--split-per-abi` (1000, 2000, 4000) sont retirés (2030 → 30).
String libelleVersion(String versionName, String buildNumber) {
  final nom = versionName.trim();
  if (RegExp(r'^v?\.?\s*\d+$', caseSensitive: false).hasMatch(nom)) {
    return nom.replaceAll(RegExp(r'^v\.?\s*', caseSensitive: false), '');
  }
  final build = int.tryParse(buildNumber.trim());
  if (build == null || build <= 0) return nom;
  return '${build >= 1000 ? build % 1000 : build}';
}
