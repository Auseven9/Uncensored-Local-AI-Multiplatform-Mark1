import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../theme/app_colors.dart';
import '../services/chat_storage_service.dart';
import '../services/search_service.dart';

/// Configure web search for the LLM — provider-agnostic.
///
/// Linkup ships as a one-field preset (just paste the key). "Custom" exposes
/// every knob so ANY search API with ANY key can be wired without a code
/// change (it maps onto the generic request builder in [SearchService]). The
/// key + config persist as JSON under the `search_config` setting; the Test
/// button runs a REAL search so you see it work before leaving.
class WebSearchScreen extends StatefulWidget {
  const WebSearchScreen({super.key});

  @override
  State<WebSearchScreen> createState() => _WebSearchScreenState();
}

class _WebSearchScreenState extends State<WebSearchScreen> {
  ChatStorageService get _storage => Get.find<ChatStorageService>();
  SearchService get _search => Get.find<SearchService>();

  late String _provider; // 'linkup' | 'custom'
  late String _method; // 'POST' | 'GET'

  final _endpoint = TextEditingController();
  final _apiKey = TextEditingController();
  final _authHeader = TextEditingController();
  final _authPrefix = TextEditingController();
  final _queryField = TextEditingController();
  final _resultsPath = TextEditingController();
  final _titleField = TextEditingController();
  final _urlField = TextEditingController();
  final _snippetField = TextEditingController();
  final _extraParams = TextEditingController();

  bool _obscureKey = true;
  bool _testing = false;
  String _testResult = '';

  @override
  void initState() {
    super.initState();
    _loadFrom(_currentConfig());
  }

  SearchConfig _currentConfig() {
    final raw = _storage.searchConfigJson;
    if (raw.trim().isEmpty) return SearchConfig.linkup;
    try {
      return SearchConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return SearchConfig.linkup;
    }
  }

  void _loadFrom(SearchConfig c) {
    _provider = c.provider == 'linkup' ? 'linkup' : 'custom';
    _method = c.method.toUpperCase() == 'GET' ? 'GET' : 'POST';
    _endpoint.text = c.endpoint;
    _apiKey.text = c.apiKey;
    _authHeader.text = c.authHeader;
    _authPrefix.text = c.authPrefix;
    _queryField.text = c.queryField;
    _resultsPath.text = c.resultsPath;
    _titleField.text = c.titleField;
    _urlField.text = c.urlField;
    _snippetField.text = c.snippetField;
    _extraParams.text =
        c.extraParams.isEmpty ? '' : jsonEncode(c.extraParams);
  }

  @override
  void dispose() {
    for (final c in [
      _endpoint,
      _apiKey,
      _authHeader,
      _authPrefix,
      _queryField,
      _resultsPath,
      _titleField,
      _urlField,
      _snippetField,
      _extraParams,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// When the user flips to the Linkup preset, fill the provider fields from
  /// the preset but KEEP whatever key they've already typed.
  void _applyLinkupPreset() {
    final key = _apiKey.text;
    _loadFrom(SearchConfig.linkup.copyWith(apiKey: key));
    setState(() => _provider = 'linkup');
  }

  SearchConfig _buildConfig() {
    Map<String, dynamic> extra = const {};
    final raw = _extraParams.text.trim();
    if (raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) extra = decoded.cast<String, dynamic>();
      } catch (_) {
        // Left invalid → treated as no extra params; surfaced on save.
      }
    }
    return SearchConfig(
      provider: _provider,
      endpoint: _endpoint.text.trim(),
      apiKey: _apiKey.text.trim(),
      method: _method,
      authHeader: _authHeader.text.trim(),
      authPrefix: _authPrefix.text,
      queryField: _queryField.text.trim().isEmpty ? 'q' : _queryField.text.trim(),
      extraParams: extra,
      resultsPath: _resultsPath.text.trim(),
      titleField: _titleField.text.trim().isEmpty ? 'name' : _titleField.text.trim(),
      urlField: _urlField.text.trim().isEmpty ? 'url' : _urlField.text.trim(),
      snippetField:
          _snippetField.text.trim().isEmpty ? 'content' : _snippetField.text.trim(),
    );
  }

  bool _save({bool quiet = false}) {
    // Validate the extraParams JSON up front so a typo doesn't silently drop.
    final raw = _extraParams.text.trim();
    if (raw.isNotEmpty) {
      try {
        jsonDecode(raw);
      } catch (_) {
        Get.snackbar('Invalid JSON',
            'Extra params must be a JSON object, e.g. {"depth":"standard"}',
            snackPosition: SnackPosition.BOTTOM);
        return false;
      }
    }
    _storage.searchConfigJson = jsonEncode(_buildConfig().toJson());
    if (!quiet) {
      Get.snackbar('Saved', 'Web search configuration updated.',
          snackPosition: SnackPosition.BOTTOM);
    }
    return true;
  }

  Future<void> _test() async {
    if (!_save(quiet: true)) return;
    setState(() {
      _testing = true;
      _testResult = 'Searching…';
    });
    final resp = await _search.search('site reliability engineering', maxResults: 3);
    if (!mounted) return;
    setState(() {
      _testing = false;
      if (resp.ok) {
        final lines = resp.results
            .map((r) => '• ${r.title.isEmpty ? r.url : r.title}')
            .join('\n');
        _testResult = 'OK — ${resp.results.length} result(s):\n$lines';
      } else {
        _testResult = 'Failed: ${resp.error}';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isCustom = _provider == 'custom';
    final testOk = _testResult.startsWith('OK');
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bgPanel,
        title: const Text('Web Search', style: TextStyle(fontSize: 16)),
        elevation: 0,
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: () => _save(),
            child: const Text('Save',
                style: TextStyle(color: AppColors.accent, fontSize: 14)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Give the on-device LLM a web search tool. Your key is stored only '
            'on this device. Linkup is pre-filled — paste your key and Test. '
            'Pick Custom to point at any search API.',
            style: TextStyle(color: context.textM, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 20),

          // Provider
          _label(context, 'Provider'),
          const SizedBox(height: 6),
          Row(
            children: [
              _providerChip(context, 'linkup', 'Linkup'),
              const SizedBox(width: 8),
              _providerChip(context, 'custom', 'Custom'),
            ],
          ),
          const SizedBox(height: 18),

          // API key (always)
          _label(context, 'API key'),
          const SizedBox(height: 6),
          TextField(
            controller: _apiKey,
            obscureText: _obscureKey,
            style: TextStyle(color: context.text, fontSize: 14),
            decoration: _dec(context, 'paste your key').copyWith(
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureKey
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 18,
                  color: context.textM,
                ),
                onPressed: () => setState(() => _obscureKey = !_obscureKey),
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Custom fields
          if (isCustom) ...[
            _label(context, 'Endpoint'),
            const SizedBox(height: 6),
            TextField(
              controller: _endpoint,
              style: TextStyle(color: context.text, fontSize: 14),
              decoration: _dec(context, 'https://api.example.com/search'),
            ),
            const SizedBox(height: 14),
            _label(context, 'HTTP method'),
            const SizedBox(height: 6),
            Row(
              children: [
                _methodChip(context, 'POST'),
                const SizedBox(width: 8),
                _methodChip(context, 'GET'),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                    child: _field(context, 'Auth header', _authHeader,
                        'Authorization')),
                const SizedBox(width: 10),
                Expanded(
                    child: _field(
                        context, 'Auth prefix', _authPrefix, 'Bearer ')),
              ],
            ),
            const SizedBox(height: 14),
            _field(context, 'Query field', _queryField, 'q'),
            const SizedBox(height: 14),
            _field(context, 'Extra params (JSON)', _extraParams,
                '{"depth":"standard"}'),
            const SizedBox(height: 14),
            _field(context, 'Results path (dot-path)', _resultsPath, 'results'),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                    child: _field(context, 'Title field', _titleField, 'name')),
                const SizedBox(width: 10),
                Expanded(child: _field(context, 'URL field', _urlField, 'url')),
                const SizedBox(width: 10),
                Expanded(
                    child: _field(
                        context, 'Snippet field', _snippetField, 'content')),
              ],
            ),
            const SizedBox(height: 18),
          ],

          // Test
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _testing ? null : _test,
              icon: _testing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.travel_explore_rounded, size: 18),
              label: Text(_testing ? 'Testing…' : 'Save & Test search'),
              style: OutlinedButton.styleFrom(
                foregroundColor: context.text,
                side: BorderSide(color: context.border),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          if (_testResult.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (testOk ? AppColors.green : AppColors.red)
                    .withValues(alpha: 0.10),
                border: Border.all(
                    color: (testOk ? AppColors.green : AppColors.red)
                        .withValues(alpha: 0.35)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                _testResult,
                style: TextStyle(
                    fontSize: 12, height: 1.4, color: context.text),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _providerChip(BuildContext context, String value, String label) {
    final sel = _provider == value;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (value == 'linkup') {
            _applyLinkupPreset();
          } else {
            setState(() => _provider = 'custom');
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: sel
                ? AppColors.accent.withValues(alpha: 0.15)
                : context.bgPanel,
            border: Border.all(
                color: sel ? AppColors.accent : context.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: sel ? AppColors.accent : context.textM,
              fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _methodChip(BuildContext context, String value) {
    final sel = _method == value;
    return GestureDetector(
      onTap: () => setState(() => _method = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color:
              sel ? AppColors.accent.withValues(alpha: 0.15) : context.bgPanel,
          border: Border.all(color: sel ? AppColors.accent : context.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          value,
          style: TextStyle(
            color: sel ? AppColors.accent : context.textM,
            fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _field(BuildContext context, String label,
      TextEditingController controller, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(context, label),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          style: TextStyle(color: context.text, fontSize: 14),
          decoration: _dec(context, hint),
        ),
      ],
    );
  }

  Widget _label(BuildContext context, String text) => Text(
        text,
        style: TextStyle(
            color: context.textM, fontSize: 12, fontWeight: FontWeight.w600),
      );

  InputDecoration _dec(BuildContext context, String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: context.textD, fontSize: 13),
        isDense: true,
        filled: true,
        fillColor: context.bgInput,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: context.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: context.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.accent),
        ),
      );
}
