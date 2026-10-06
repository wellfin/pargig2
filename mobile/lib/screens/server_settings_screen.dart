import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../config.dart';
import '../state/auth_state.dart';

class ServerSettingsScreen extends StatefulWidget {
  const ServerSettingsScreen({super.key});

  @override
  State<ServerSettingsScreen> createState() => _ServerSettingsScreenState();
}

class _ServerSettingsScreenState extends State<ServerSettingsScreen> {
  late final TextEditingController _ctrl;
  bool _testing = false;
  bool _saving = false;
  String? _testResult;
  bool _testOk = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: AppConfig.apiBase);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final url = _ctrl.text.trim().replaceAll(RegExp(r'/+$'), '');
    try {
      final r = await http
          .get(Uri.parse('$url/api'))
          .timeout(const Duration(seconds: 6));
      if (r.statusCode == 200 && r.body.contains('Pargig API')) {
        setState(() {
          _testResult = '✓ Connected — ${r.body}';
          _testOk = true;
        });
      } else {
        setState(() {
          _testResult =
              'Reached ${r.statusCode}, but response did not look like Pargig backend.';
          _testOk = false;
        });
      }
    } catch (e) {
      setState(() {
        _testResult = 'Could not reach server: $e';
        _testOk = false;
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final newBase = _ctrl.text.trim();
    final oldBase = AppConfig.apiBase;
    await AppConfig.setApiBase(newBase);

    // If the host actually changed, the existing JWT is invalid (signed by
    // a different backend). Force a logout so the user re-authenticates.
    if (oldBase != AppConfig.apiBase) {
      await ApiClient.setToken(null);
      if (mounted) {
        await context.read<AuthState>().logout();
      }
    }

    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Saved. Using ${AppConfig.apiBase}'),
        backgroundColor: AppColors.green,
      ),
    );
    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }

  // Restores the production backend in one tap. Saves as well as filling
  // the box — leaving it unsaved is how someone ends up staring at the
  // right URL on screen while the app still talks to the old one.
  Future<void> _reset() async {
    setState(() {
      _ctrl.text = AppConfig.defaultApiBase;
      _testResult = null;
    });
    await _save();
  }

  Widget _preset(String label, String value) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: () => setState(() => _ctrl.text = value),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unsaved =
        _ctrl.text.trim().replaceAll(RegExp(r'/+$'), '') != AppConfig.apiBase;

    return Scaffold(
      appBar: AppBar(title: const Text('Server settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Backend API URL',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE6E8EE)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                const Icon(
                  Icons.dns_outlined,
                  size: 20,
                  color: Color(0xFF6A7282),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF0F172A),
                    ),
                    decoration: const InputDecoration(
                      isCollapsed: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                      hintText: 'http://192.168.1.11:5014',
                      hintStyle: TextStyle(
                        color: Color(0x800F172A),
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Currently saved: ${AppConfig.apiBase}',
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 14),
          const Text(
            'Quick presets',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _preset('Android emulator', 'http://10.0.2.2:5014'),
              _preset('iOS simulator', 'http://127.0.0.1:5014'),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'For a real phone on Wi-Fi, type your laptop\'s LAN IP, e.g. http://192.168.x.x:5014',
            style: TextStyle(fontSize: 11, color: AppColors.muted),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: _testing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.network_check),
                  label: Text(_testing ? 'Testing…' : 'Test connection'),
                  onPressed: _testing ? null : _test,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save),
                  label: Text(_saving ? 'Saving…' : 'Save'),
                  onPressed: _saving ? null : _save,
                ),
              ),
            ],
          ),
          if (_testResult != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (_testOk ? AppColors.green : AppColors.red).withValues(
                  alpha: 0.1,
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: (_testOk ? AppColors.green : AppColors.red).withValues(
                    alpha: 0.3,
                  ),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _testOk ? Icons.check_circle : Icons.error_outline,
                    color: _testOk ? AppColors.green : AppColors.red,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _testResult!,
                      style: TextStyle(
                        color: _testOk ? AppColors.green : AppColors.red,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          TextButton.icon(
            onPressed: _reset,
            icon: const Icon(Icons.refresh),
            label: Text('Reset to default (${AppConfig.defaultApiBase})'),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tips',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                SizedBox(height: 6),
                Text(
                  '• On a physical phone, your phone and laptop must be on the same Wi-Fi.\n'
                  '• Find your laptop\'s LAN IP with "ipconfig" (Windows) or "ifconfig" (Mac/Linux).\n'
                  '• Saving a new URL signs you out — you\'ll need to log in again.\n'
                  '• Use "Test connection" first to confirm the backend is reachable.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.muted,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          if (unsaved) ...[
            const SizedBox(height: 12),
            const Center(
              child: Text(
                '• unsaved changes',
                style: TextStyle(color: AppColors.red, fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
