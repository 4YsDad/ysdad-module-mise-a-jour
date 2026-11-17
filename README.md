# ysdad_mise_a_jour — Avis de mise à jour automatique (module Ysdad)

Module Flutter réutilisable pour les applis Android de Ysdad distribuées par APK
(hors Play Store). À l’ouverture et au retour dans l’appli, il lit un petit
fichier JSON hébergé ; si une version plus récente existe, il affiche :

> **Nouvelle version X disponible** — les nouveautés — **Plus tard** / **Mettre à jour**

*Mettre à jour* télécharge l’APK avec une barre de progression, puis ouvre
l’installeur Android. Si Android n’autorise pas encore l’appli à installer des
applis (« sources inconnues »), le module explique quoi faire et ouvre le bon
réglage, puis reprend l’installation au retour.

*Plus tard* cache l’avis jusqu’à la prochaine ouverture de l’appli.

## Installation

```yaml
dependencies:
  ysdad_mise_a_jour:
    git:
      url: https://github.com/4YsDad/ysdad-module-mise-a-jour.git
      ref: main
```

Rien à ajouter dans le manifeste de l’appli : le module déclare lui-même la
permission `REQUEST_INSTALL_PACKAGES` et son propre `FileProvider`
(autorité `<applicationId>.ysdadmaj.fileprovider`).

## Utilisation

```dart
import 'package:ysdad_mise_a_jour/ysdad_mise_a_jour.dart';

final navigatorKey = GlobalKey<NavigatorState>();

void main() {
  YsdadMiseAJour.configurer(
    urlVersion: Uri.parse('https://monsite.web.app/version/mon-appli.json'),
    navigatorKey: navigatorKey,          // la même que MaterialApp
    nomAppli: 'Mon appli',
    intervalle: const Duration(hours: 4), // au plus une vérif. aux 4 h à la reprise
  );
  runApp(MaterialApp(navigatorKey: navigatorKey, home: ...));
  YsdadMiseAJour.demarrer(); // ne bloque pas l’ouverture
}

// Bouton dans les réglages ou l’écran À propos :
ListTile(
  leading: const Icon(Icons.system_update),
  title: const Text('Vérifier les mises à jour'),
  onTap: () => YsdadMiseAJour.verifierManuellement(context),
);
```

`verifierManuellement` donne toujours un retour : l’avis, « … est à jour » ou
un message d’erreur réseau.

## Le fichier JSON de version

```json
{
  "latestVersionCode": 2028,
  "versionName": "28",
  "versionLabel": "28",
  "apkUrl": "https://monsite.web.app/dl/<jeton>/mon-appli-v28.apk",
  "notes": "Ce qui change, en français.\nUne ligne par nouveauté.",
  "minVersionCode": 0,
  "sha256": "empreinte hexadécimale facultative de l’APK"
}
```

| Champ | Rôle |
|---|---|
| `latestVersionCode` | versionCode Android de la dernière version publiée (obligatoire). |
| `versionName` | Nom de la version. |
| `versionLabel` | Facultatif : libellé court affiché (« Nouvelle version 28 disponible »). Sinon `versionName`. |
| `apkUrl` | Adresse de l’APK (obligatoire). |
| `notes` | Nouveautés (texte ou liste de lignes). |
| `minVersionCode` | Facultatif : sous ce versionCode, la mise à jour est **obligatoire** (pas de bouton Plus tard). |
| `sha256` | Facultatif : l’APK téléchargé est vérifié avant l’installation. |

**Attention au versionCode** avec `flutter build apk --split-per-abi` :
Flutter ajoute 1000 (armeabi-v7a), 2000 (arm64-v8a) ou 4000 (x86_64) au
numéro de build. Mettez dans le JSON le versionCode réel de l’APK publié
(ex. `2028` pour `--build-number 28` en arm64), ou passez
`normaliserVersionCode: (c) => c % 1000` et publiez le numéro de build seul.

Hébergez le JSON avec un cache court, par exemple dans `firebase.json` :

```json
{ "source": "/version/**", "headers": [{ "key": "Cache-Control", "value": "no-cache, max-age=0" }] }
```

et l’APK avec `Content-Type: application/vnd.android.package-archive` et
`Content-Disposition: attachment`.

## Publier une nouvelle version

1. Monter le numéro de build, construire et signer l’APK **avec la même clé**
   (sinon Android refuse la mise à jour).
2. Déposer l’APK sous un nouveau chemin (`dl/<jeton>/appli-vNN.apk`).
3. Mettre à jour le JSON (`latestVersionCode`, `versionName`, `apkUrl`,
   `notes`) puis déployer.

## Autres plateformes

* **Play Store** : le Play Store interdit l’installation d’APK hors magasin.
  Pour une appli publiée sur le Play Store, n’appelez pas `demarrer()` ;
  utilisez plutôt le paquet [`in_app_update`](https://pub.dev/packages/in_app_update) :
  ```dart
  final info = await InAppUpdate.checkForUpdate();
  if (info.updateAvailability == UpdateAvailability.updateAvailable) {
    await InAppUpdate.performImmediateUpdate(); // ou startFlexibleUpdate()
  }
  ```
  (Ce paquet n’est pas inclus ici pour ne pas alourdir les applis APK.)
* **Web** : le module ne fait rien sur le web (`estSupporte` est faux). Pour
  une PWA, comparez le même JSON à la version embarquée puis rechargez la page
  (`web.window.location.reload()`), comme dans Ciné-surveillance (`version.json`).
* **iOS** : non pris en charge (installation hors App Store impossible).

## API

| Élément | Description |
|---|---|
| `YsdadMiseAJour.configurer(...)` | URL du JSON, clé du navigateur, nom de l’appli, intervalle, normalisation. |
| `YsdadMiseAJour.demarrer()` | Vérifie 2 s après l’ouverture puis à chaque reprise (au plus une fois par intervalle). |
| `YsdadMiseAJour.verifierManuellement(context)` | Vérification immédiate avec retour à l’écran. |
| `YsdadMiseAJour.lireInfo()` | Lit le JSON (`InfoVersion`). |
| `YsdadMiseAJour.versionCodeInstalle()` | versionCode installé (via `package_info_plus`). |
| `YsdadMiseAJour.arreter()` | Arrête l’écoute de la reprise. |
| `libelleVersion(versionName, buildNumber)` | Libellé court « 30 » (au lieu de « 1.0.0 (2030) ») pour afficher « version 30 ». |
