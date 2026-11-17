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
}
