import 'package:flutter_test/flutter_test.dart';
import 'package:pargig/config.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _oldServer = 'http://52.66.245.202';
const _newServer = 'http://3.110.101.117';

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

  test('an install pinned to the retired server is moved across', () async {
    // The case that matters: every phone that already opened the app has
    // the old address written to disk, and would otherwise keep calling
    // a machine that no longer answers.
    SharedPreferences.setMockInitialValues({'api_base': _oldServer});
    await AppConfig.load();
    expect(AppConfig.apiBase, _newServer);

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('api_base'),
      _newServer,
      reason: 'the move must be written back, not re-done every launch',
    );
  });

  test('the retired server is matched by host, not exact string', () async {
    SharedPreferences.setMockInitialValues({
      'api_base': 'http://52.66.245.202:5014',
    });
    await AppConfig.load();
    expect(AppConfig.apiBase, _newServer);
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
    await AppConfig.setApiBase('http://3.110.101.117/');
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
