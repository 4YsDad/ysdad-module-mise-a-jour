import 'package:flutter_test/flutter_test.dart';
import 'package:ysdad_mise_a_jour/ysdad_mise_a_jour.dart';

void main() {
  test('lit le JSON et compare les versions', () {
    final info = InfoVersion.parse('''
      {"latestVersionCode": 2028, "versionName": "1.0.0 (28)",
       "apkUrl": "https://x/app.apk", "notes": "Bonjour é", "minVersionCode": 2000}
    ''');
    expect(info.versionName, '1.0.0 (28)');
    expect(info.estPlusRecenteQue(2027), isTrue);
    expect(info.estPlusRecenteQue(2028), isFalse);
    expect(info.estObligatoirePour(1999), isTrue);
    expect(info.estObligatoirePour(2027), isFalse);
  });

  test('notes en liste et versionCode en texte', () {
    final info = InfoVersion.fromJson({
      'latestVersionCode': '30',
      'apkUrl': 'https://x/a.apk',
      'notes': ['Un', 'Deux'],
    });
    expect(info.latestVersionCode, 30);
    expect(info.notes, 'Un\nDeux');
    expect(info.estObligatoirePour(1), isFalse);
  });

  test('refuse un JSON incomplet', () {
    expect(() => InfoVersion.fromJson({'versionName': 'x'}),
        throwsFormatException);
  });

  test('libellé court', () {
    expect(libelleVersion('30', '2030'), '30');
    expect(libelleVersion('1.0.0', '2029'), '29');
    expect(libelleVersion('1.0.0', '28'), '28');
    expect(libelleVersion('v. 31', '2031'), '31');
    final info = InfoVersion.fromJson({
      'latestVersionCode': 2030,
      'versionName': '1.0.0',
      'versionLabel': '30',
      'apkUrl': 'https://x/a.apk'
    });
    expect(info.libelle, '30');
  });

  test('mode magasin : storeUrl sans apkUrl', () {
    final info = InfoVersion.fromJson({
      'latestVersionCode': 6,
      'storeUrl': 'https://play.google.com/store/apps/details?id=a.b',
    });
    expect(info.apkUrl, '');
    expect(info.storeUrl, contains('play.google.com'));
  });
}
