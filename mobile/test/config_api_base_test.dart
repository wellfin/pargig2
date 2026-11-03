import 'package:flutter_test/flutter_test.dart';
import 'package:pargig/config.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Every server the app has been pointed at. Each must keep releasing
// installs pinned to it, or phones that have not opened the app since
// that build stay stranded on a dead address.
const _retiredServers = ['http://52.66.245.202', 'http://3.110.101.117'];
const _newServer = 'http://3.111.232.213';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the production default is the new server', () {
    expect(AppConfig.defaultApiBase, _newServer);
  });

  test('a fresh install lands on the new server and saves it', () async {
    SharedPreferences.setMockInitialValues({});
    await AppConfig.load();
    expect(AppConfig.apiBase, _newServer);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('api_base'), _newServer);
  });

  test('an install pinned to ANY retired server is moved across', () async {
    // The case that matters: every phone that already opened the app has
    // whichever address was current then written to disk, and would
    // otherwise keep calling a machine that no longer answers.
    for (final old in _retiredServers) {
      SharedPreferences.setMockInitialValues({'api_base': old});
      await AppConfig.load();
      expect(AppConfig.apiBase, _newServer, reason: 'stranded on $old');

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('api_base'),
        _newServer,
        reason: 'the move must be written back, not re-done every launch',
      );
    }
  });

  test('a retired server is matched by host, not exact string', () async {
    for (final old in _retiredServers) {
      SharedPreferences.setMockInitialValues({'api_base': '$old:5014'});
      await AppConfig.load();
      expect(AppConfig.apiBase, _newServer, reason: 'stranded on $old:5014');
    }
  });

  test('a deliberate override is left alone', () async {
    SharedPreferences.setMockInitialValues({
      'api_base': 'http://192.168.1.11:5014',
    });
    await AppConfig.load();
    expect(AppConfig.apiBase, 'http://192.168.1.11:5014');
  });

  test('setting the new server by hand persists it', () async {
    SharedPreferences.setMockInitialValues({});
    await AppConfig.setApiBase('http://3.111.232.213/');
    // Trailing slash stripped, so apiUrl cannot end up with a double one.
    expect(AppConfig.apiBase, _newServer);
    expect(AppConfig.apiUrl, '$_newServer/api');
  });

  test('clearing the override falls back to the new server', () async {
    SharedPreferences.setMockInitialValues({'api_base': 'http://10.0.0.5'});
    await AppConfig.setApiBase('');
    expect(AppConfig.apiBase, _newServer);
  });
}
