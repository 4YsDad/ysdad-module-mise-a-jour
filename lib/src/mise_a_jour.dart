import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'info_version.dart';

/// Résultat d'une vérification.
enum ResultatVerification {
  /// L'appli est à jour.
  aJour,

  /// Une nouvelle version est disponible (l'avis a été montré).
  disponible,

  /// La vérification a échoué (réseau, JSON invalide…).
  erreur,

  /// Vérification sautée (trop récente, avis reporté, plateforme non Android).
  ignoree,
}

/// Avis de mise à jour automatique Ysdad.
///
/// Utilisation minimale :
/// ```dart
/// final navigatorKey = GlobalKey<NavigatorState>();
/// YsdadMiseAJour.configurer(
///   urlVersion: Uri.parse('https://monsite.web.app/version/mon-appli.json'),
///   navigatorKey: navigatorKey,
///   nomAppli: 'Mon appli',
/// );
/// YsdadMiseAJour.demarrer(); // vérifie à l'ouverture et à la reprise
/// ```
class YsdadMiseAJour {
  YsdadMiseAJour._();

  static const MethodChannel _canal = MethodChannel('ysdad_mise_a_jour');
  static const String _cleDerniereVerif = 'ysdad_maj_derniere_verif_ms';

  static Uri? _urlVersion;
  static GlobalKey<NavigatorState>? _navigatorKey;
  static Duration _intervalle = const Duration(hours: 4);
  static String _nomAppli = 'l’appli';
  static int Function(int versionCode)? _normaliser;
  static void Function(String message)? _journal;

  static AppLifecycleListener? _ecouteur;
  static bool _reporteCetteSession = false;
  static bool _avisOuvert = false;
  static bool _verificationEnCours = false;

  /// Configure le module. À appeler une fois, avant [demarrer].
  ///
  /// * [urlVersion] : adresse du JSON de version (voir [InfoVersion]).
  /// * [navigatorKey] : la clé passée à `MaterialApp(navigatorKey: …)`,
  ///   pour afficher les dialogues sans contexte.
  /// * [intervalle] : délai minimal entre deux vérifications à la reprise.
  /// * [normaliserVersionCode] : facultatif, transforme le versionCode lu
  ///   sur l'appareil avant la comparaison (ex. `(c) => c % 1000`).
  static void configurer({
    required Uri urlVersion,
    required GlobalKey<NavigatorState> navigatorKey,
    Duration intervalle = const Duration(hours: 4),
    String nomAppli = 'l’appli',
    int Function(int versionCode)? normaliserVersionCode,
    void Function(String message)? journal,
  }) {
    _urlVersion = urlVersion;
    _navigatorKey = navigatorKey;
    _intervalle = intervalle;
    _nomAppli = nomAppli;
    _normaliser = normaliserVersionCode;
    _journal = journal;
  }

  /// Vrai si le module peut installer un APK sur cette plateforme.
  static bool get estSupporte =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Lance la vérification à l'ouverture (sans bloquer) et à chaque reprise
  /// de l'appli, au plus une fois par [intervalle].
  static void demarrer() {
    if (!estSupporte || _urlVersion == null) return;
    _ecouteur ??= AppLifecycleListener(
      onResume: () => unawaited(_verifierAuto(ouverture: false)),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Laisse l'appli s'afficher avant d'aller sur le réseau.
      Future<void>.delayed(
          const Duration(seconds: 2), () => _verifierAuto(ouverture: true));
    });
  }

  /// Arrête l'écoute de la reprise de l'appli.
  static void arreter() {
    _ecouteur?.dispose();
    _ecouteur = null;
  }

  /// Vérification déclenchée par l'utilisateur (bouton « Vérifier les mises
  /// à jour »). Affiche toujours un retour : avis, « à jour » ou erreur.
  static Future<ResultatVerification> verifierManuellement(
      BuildContext context) async {
    final messager = ScaffoldMessenger.maybeOf(context);
    if (!estSupporte) {
      messager?.showSnackBar(const SnackBar(
          content: Text(
              'La mise à jour automatique est offerte sur Android seulement.')));
      return ResultatVerification.ignoree;
    }
    messager?.showSnackBar(const SnackBar(
        content: Text('Recherche de mises à jour…'),
        duration: Duration(seconds: 2)));
    try {
      final info = await lireInfo();
      final installe = await versionCodeInstalle();
      await _noterVerification();
      messager?.hideCurrentSnackBar();
      if (info.estPlusRecenteQue(installe)) {
        await _montrerAvis(info, installe);
        return ResultatVerification.disponible;
      }
      final pkg = await PackageInfo.fromPlatform();
      messager?.showSnackBar(SnackBar(
          content: Text(
              '$_nomAppli est à jour (version ${pkg.version} (${pkg.buildNumber})).')));
      return ResultatVerification.aJour;
    } catch (e) {
      _log('Vérification manuelle échouée : $e');
      messager?.hideCurrentSnackBar();
      messager?.showSnackBar(const SnackBar(
          content: Text(
              'Impossible de vérifier les mises à jour. Vérifiez votre connexion Internet.')));
      return ResultatVerification.erreur;
    }
  }

  /// Lit le JSON de version hébergé (sans cache).
  static Future<InfoVersion> lireInfo() async {
    final base = _urlVersion;
    if (base == null) {
      throw StateError('YsdadMiseAJour.configurer() n’a pas été appelé.');
    }
    final url = base.replace(queryParameters: {
      ...base.queryParameters,
      '_': DateTime.now().millisecondsSinceEpoch.toString(),
    });
    final rep = await http.get(url, headers: const {
      'Cache-Control': 'no-cache',
      'Pragma': 'no-cache',
    }).timeout(const Duration(seconds: 15));
    if (rep.statusCode != 200) {
      throw HttpException('HTTP ${rep.statusCode}', uri: url);
    }
    return InfoVersion.parse(_utf8Decode(rep.bodyBytes));
  }

  /// versionCode Android installé (après [normaliserVersionCode]).
  static Future<int> versionCodeInstalle() async {
    int code = 0;
    try {
      final pkg = await PackageInfo.fromPlatform();
      code = int.tryParse(pkg.buildNumber) ?? 0;
    } catch (_) {}
    if (code == 0 && estSupporte) {
      try {
        code = (await _canal.invokeMethod<int>('versionCode')) ?? 0;
      } catch (_) {}
    }
    return _normaliser?.call(code) ?? code;
  }

  // ---------------------------------------------------------------------------

  static Future<ResultatVerification> _verifierAuto(
      {required bool ouverture}) async {
    if (_verificationEnCours || _avisOuvert) {
      return ResultatVerification.ignoree;
    }
    _verificationEnCours = true;
    try {
      if (!ouverture) {
        final prefs = await SharedPreferences.getInstance();
        final derniere = prefs.getInt(_cleDerniereVerif) ?? 0;
        final ecoule = DateTime.now().millisecondsSinceEpoch - derniere;
        if (ecoule < _intervalle.inMilliseconds) {
          return ResultatVerification.ignoree;
        }
      }
      final info = await lireInfo();
      final installe = await versionCodeInstalle();
      await _noterVerification();
      _log('Installé : $installe, publié : ${info.latestVersionCode}');
      if (!info.estPlusRecenteQue(installe)) return ResultatVerification.aJour;
      final obligatoire = info.estObligatoirePour(installe);
      if (_reporteCetteSession && !obligatoire) {
        return ResultatVerification.ignoree;
      }
      await _montrerAvis(info, installe);
      return ResultatVerification.disponible;
    } catch (e) {
      _log('Vérification automatique échouée : $e');
      return ResultatVerification.erreur;
    } finally {
      _verificationEnCours = false;
    }
  }

  static Future<void> _noterVerification() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
        _cleDerniereVerif, DateTime.now().millisecondsSinceEpoch);
  }

  static BuildContext? get _contexte => _navigatorKey?.currentContext;

  static Future<void> _montrerAvis(InfoVersion info, int installe) async {
    final ctx = _contexte;
    if (ctx == null || _avisOuvert) return;
    final obligatoire = info.estObligatoirePour(installe);
    _avisOuvert = true;
    bool? accepte;
    try {
      accepte = await showDialog<bool>(
        context: ctx,
        barrierDismissible: !obligatoire,
        builder: (context) => _AvisMiseAJour(
          info: info,
          obligatoire: obligatoire,
          nomAppli: _nomAppli,
        ),
      );
    } finally {
      _avisOuvert = false;
    }
    if (accepte == true) {
      await _mettreAJour(info, obligatoire: obligatoire);
    } else if (!obligatoire) {
      _reporteCetteSession = true; // reviendra à la prochaine ouverture
    }
  }

  static Future<void> _mettreAJour(InfoVersion info,
      {required bool obligatoire}) async {
    final ctx = _contexte;
    if (ctx == null) return;
    final fichier = await showDialog<File?>(
      context: ctx,
      barrierDismissible: false,
      builder: (context) => _Telechargement(info: info),
    );
    if (fichier == null) {
      if (obligatoire) await _montrerAvis(info, -1);
      return;
    }
    await _installer(fichier, info, obligatoire: obligatoire);
  }

  static Future<void> _installer(File fichier, InfoVersion info,
      {required bool obligatoire}) async {
    var permis = await _peutInstaller();
    if (!permis) {
      final ctx = _contexte;
      if (ctx == null || !ctx.mounted) return;
      final ouvrir = await showDialog<bool>(
        context: ctx,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Autoriser l’installation'),
          content: Text(
            'Pour installer la mise à jour, Android doit permettre à '
            '$_nomAppli d’installer des applis.\n\n'
            'Dans le réglage qui va s’ouvrir, activez « Autoriser cette '
            'source », puis revenez ici avec la flèche Retour.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Ouvrir le réglage'),
            ),
          ],
        ),
      );
      if (ouvrir != true) return;
      final retour = Completer<void>();
      final ecoute = AppLifecycleListener(onResume: () {
        if (!retour.isCompleted) retour.complete();
      });
      try {
        await _canal.invokeMethod<bool>('ouvrirReglageInstallation');
        await retour.future.timeout(const Duration(minutes: 10));
      } catch (_) {
      } finally {
        ecoute.dispose();
      }
      permis = await _peutInstaller();
      if (!permis) {
        final c = _contexte;
        if (c != null && c.mounted) {
          ScaffoldMessenger.maybeOf(c)?.showSnackBar(const SnackBar(
              content: Text(
                  'Autorisation non accordée. Réessayez avec « Vérifier les mises à jour ».')));
        }
        return;
      }
    }
    try {
      await _canal.invokeMethod<bool>('installerApk', {'chemin': fichier.path});
    } catch (e) {
      _log('Installeur : $e');
      final c = _contexte;
      if (c != null && c.mounted) {
        ScaffoldMessenger.maybeOf(c)?.showSnackBar(const SnackBar(
            content: Text('Impossible d’ouvrir l’installeur Android.')));
      }
    }
  }

  static Future<bool> _peutInstaller() async {
    try {
      return (await _canal.invokeMethod<bool>('peutInstaller')) ?? false;
    } catch (_) {
      return false;
    }
  }

  static void _log(String m) {
    _journal?.call(m);
    if (kDebugMode) debugPrint('[ysdad_mise_a_jour] $m');
  }
}

String _utf8Decode(List<int> octets) =>
    const Utf8Decoder(allowMalformed: true).convert(octets);

/// Dossier des APK téléchargés (déclaré dans le FileProvider du module).
Future<Directory> _dossierMaj() async {
  final base = await getTemporaryDirectory();
  final d = Directory('${base.path}/ysdad_maj');
  if (!await d.exists()) await d.create(recursive: true);
  return d;
}

class _AvisMiseAJour extends StatelessWidget {
  const _AvisMiseAJour({
    required this.info,
    required this.obligatoire,
    required this.nomAppli,
  });

  final InfoVersion info;
  final bool obligatoire;
  final String nomAppli;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: !obligatoire,
      child: AlertDialog(
        icon: const Icon(Icons.system_update_rounded, size: 36),
        title: Text('Nouvelle version ${info.versionName} disponible'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (obligatoire)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Cette mise à jour est nécessaire pour continuer à '
                      'utiliser $nomAppli.',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                if (info.notes.trim().isNotEmpty) ...[
                  Text('Nouveautés', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 6),
                  Text(info.notes.trim()),
                ] else
                  const Text('Une nouvelle version est prête à installer.'),
              ],
            ),
          ),
        ),
        actions: [
          if (!obligatoire)
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Plus tard'),
            ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.download_rounded),
            label: const Text('Mettre à jour'),
          ),
        ],
      ),
    );
  }
}

class _Telechargement extends StatefulWidget {
  const _Telechargement({required this.info});

  final InfoVersion info;

  @override
  State<_Telechargement> createState() => _TelechargementState();
}

class _TelechargementState extends State<_Telechargement> {
  final http.Client _client = http.Client();
  double? _progression;
  int _recu = 0;
  int? _total;
  String? _erreur;
  bool _annule = false;

  @override
  void initState() {
    super.initState();
    unawaited(_telecharger());
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  Future<void> _telecharger() async {
    setState(() {
      _erreur = null;
      _progression = null;
      _recu = 0;
    });
    IOSink? sortie;
    try {
      final dossier = await _dossierMaj();
      final cible =
          File('${dossier.path}/maj-${widget.info.latestVersionCode}.apk');
      final marque = File('${cible.path}.ok');
      if (await cible.exists() && await marque.exists()) {
        if (mounted) Navigator.of(context).pop(cible);
        return;
      }
      // Nettoie les anciens téléchargements.
      await for (final f in dossier.list()) {
        try {
          await f.delete();
        } catch (_) {}
      }
      final partiel = File('${cible.path}.part');
      // « identity » : pas de compression, pour que la taille annoncée
      // corresponde aux octets reçus (sinon la progression est fausse).
      final requete = http.Request('GET', Uri.parse(widget.info.apkUrl))
        ..headers['Accept-Encoding'] = 'identity';
      final rep =
          await _client.send(requete).timeout(const Duration(seconds: 30));
      if (rep.statusCode != 200) {
        throw HttpException('HTTP ${rep.statusCode}');
      }
      _total = rep.contentLength;
      sortie = partiel.openWrite();
      var dernierAffichage = DateTime.now();
      await for (final morceau in rep.stream) {
        if (_annule) throw const _Annulation();
        sortie.add(morceau);
        _recu += morceau.length;
        final maintenant = DateTime.now();
        if (maintenant.difference(dernierAffichage).inMilliseconds > 100 &&
            mounted) {
          dernierAffichage = maintenant;
          setState(() {
            _progression = (_total != null && _total! > 0)
                ? (_recu / _total!).clamp(0.0, 1.0)
                : null;
          });
        }
      }
      await sortie.flush();
      await sortie.close();
      sortie = null;
      if (_total != null && _total! > 0 && _recu < _total!) {
        throw const HttpException('Téléchargement incomplet');
      }
      final attendu = widget.info.sha256;
      if (attendu != null && attendu.isNotEmpty) {
        final empreinte =
            (await sha256.bind(partiel.openRead()).first).toString();
        if (empreinte != attendu) {
          await partiel.delete();
          throw const FormatException('Empreinte du fichier invalide');
        }
      }
      await partiel.rename(cible.path);
      await marque.writeAsString('ok');
      if (mounted) Navigator.of(context).pop(cible);
    } on _Annulation {
      await sortie?.close();
    } catch (e) {
      await sortie?.close();
      if (!mounted || _annule) return;
      setState(() => _erreur = 'Le téléchargement a échoué. Vérifiez votre '
          'connexion Internet et réessayez.');
    }
  }

  String _mo(int octets) => (octets / (1024 * 1024)).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final pourcent = _progression == null
        ? null
        : (_progression! * 100).clamp(0, 100).round();
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(_erreur == null
            ? 'Téléchargement de la version ${widget.info.versionName}'
            : 'Téléchargement interrompu'),
        content: _erreur != null
            ? Text(_erreur!)
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(value: _progression),
                  const SizedBox(height: 12),
                  Text(_total != null && _total! > 0
                      ? '${pourcent ?? 0} %  ·  ${_mo(_recu)} Mo sur ${_mo(_total!)} Mo'
                      : '${_mo(_recu)} Mo reçus'),
                  const SizedBox(height: 4),
                  const Text(
                      'L’installeur Android s’ouvrira à la fin du téléchargement.'),
                ],
              ),
        actions: [
          TextButton(
            onPressed: () {
              _annule = true;
              _client.close();
              Navigator.of(context).pop(null);
            },
            child: const Text('Annuler'),
          ),
          if (_erreur != null)
            FilledButton(
              onPressed: _telecharger,
              child: const Text('Réessayer'),
            ),
        ],
      ),
    );
  }
}

class _Annulation implements Exception {
  const _Annulation();
}
