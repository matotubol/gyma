import 'package:flutter/material.dart';
import '../api_key_store.dart';

class ApiKeyScreen extends StatefulWidget {
  const ApiKeyScreen({super.key});
  @override
  State<ApiKeyScreen> createState() => _ApiKeyScreenState();
}

class _ApiKeyScreenState extends State<ApiKeyScreen> {
  final _input = TextEditingController();
  final _keys = ApiKeyStore();
  bool _saved = false;
  bool _busy = true;
  String? _message;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
      final saved = await _keys.hasKey();
      if (mounted) setState(() => _saved = saved);
    } catch (_) {
      if (mounted) setState(() => _message = 'Could not access Keychain. Unlock your iPhone and try again.');
    } finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  void dispose() { _input.dispose(); super.dispose(); }
  Future<void> _save() async {
    final value = _input.text.trim();
    if (!value.startsWith('sk-') || value.length < 20) {
      setState(() => _message = 'Paste your OpenAI API key.');
      return;
    }
    setState(() => _busy = true);
    try {
      await _keys.save(value);
      _input.clear();
      if (mounted) setState(() { _saved = true; _message = 'API key saved in Keychain.'; });
    } catch (_) {
      if (mounted) setState(() => _message = 'Could not save the key. Please try again.');
    } finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _remove() async {
    setState(() => _busy = true);
    try {
      await _keys.remove();
      _input.clear();
      if (mounted) setState(() { _saved = false; _message = 'API key removed from this device.'; });
    } catch (_) {
      if (mounted) setState(() => _message = 'Could not remove the key. Please try again.');
    } finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('OpenAI settings')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      const Icon(Icons.key_outlined, size: 40),
      const SizedBox(height: 16),
      Text('Your personal AI coach', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      const Text('Connect directly to OpenAI with your own API key. No server or computer is needed. AI requests use your OpenAI API credits.'),
      const SizedBox(height: 12),
      const Text('Your key is stored in this iPhone’s Keychain. It is excluded from workout backups and sent only to OpenAI. Workout tracking works without a key or internet.'),
      const SizedBox(height: 24),
      Text(_saved ? 'An API key is saved on this device.' : 'No API key saved yet.'),
      const SizedBox(height: 12),
      TextField(controller: _input, obscureText: true, autocorrect: false, enableSuggestions: false,
        decoration: InputDecoration(labelText: _saved ? 'Replacement API key' : 'OpenAI API key', hintText: 'Paste your key here')),
      const SizedBox(height: 16),
      FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Please wait…' : 'Save API key')),
      if (_saved) TextButton(onPressed: _busy ? null : _remove, child: const Text('Remove saved key')),
      if (_message != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(_message!)),
    ]),
  );
}
