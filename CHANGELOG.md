## 1.2.0

* Mode magasin (`modeMagasin: true` et champ `storeUrl` du JSON) pour les
  applis distribuées par Google Play : « Mettre à jour » ouvre la fiche du
  magasin, aucun APK n'est téléchargé. `apkUrl` devient facultatif si
  `storeUrl` est présent.

## 1.1.0

* Libellé court de version : champ `versionLabel` du JSON et fonction
  `libelleVersion` (« version 30 » au lieu de « 1.0.0 (2030) »).

## 1.0.0

* Première version : JSON de version, avis en français, téléchargement avec
  progression, installeur Android (FileProvider), autorisation « sources
  inconnues », report « Plus tard », vérification à la reprise, mise à jour
  obligatoire (`minVersionCode`), empreinte SHA-256 facultative.
