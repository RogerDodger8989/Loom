part of '../settings_screen.dart';

extension NotifieringarTabExtension on _SettingsScreenState {
  // ─────────────────────────────────────────────
  //  Category: Notifieringar
  // ─────────────────────────────────────────────
  Widget _buildNotifieringar() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // ── Discord ──────────────────────────────
          _buildSection('Discord', Icons.forum_outlined, [
            _buildField('Webhook-URL', _discordWebhookCtrl),
            const SizedBox(height: 8),
            Text(
              'Skapa en Incoming Webhook i Discord-kanalens inställningar och klistra in URL:en ovan.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11, height: 1.5),
            ),
            const SizedBox(height: 14),
            _buildTestButton(
              label: 'Skicka testmeddelande',
              icon: Icons.send_outlined,
              color: const Color(0xFF5865F2),
              isTesting: _isTestingDiscord,
              result: _discordTestResult,
              onTap: _testDiscord,
            ),
          ]),
          const SizedBox(height: 16),
          // ── E-post (SMTP) ────────────────────────
          _buildSection('E-post via SMTP', Icons.email_outlined, [
            Row(children: [
              Expanded(flex: 3, child: _buildField('SMTP-server (host)', _smtpHostCtrl)),
              const SizedBox(width: 12),
              Expanded(child: _buildField('Port', _smtpPortCtrl)),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _buildField('Användarnamn', _smtpUserCtrl)),
              const SizedBox(width: 12),
              Expanded(child: _buildField('Lösenord', _smtpPassCtrl, obscure: true)),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _buildField('Avsändaradress (From)', _smtpFromCtrl)),
              const SizedBox(width: 12),
              Expanded(child: _buildField('Mottagaradress (To)', _smtpToCtrl)),
            ]),
            const SizedBox(height: 14),
            _buildTestButton(
              label: 'Skicka testmejl',
              icon: Icons.mail_outline,
              color: const Color(0xFF8A5BFF),
              isTesting: _isTestingEmail,
              result: _emailTestResult,
              onTap: _testEmail,
            ),
          ]),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildTestButton({
    required String label,
    required IconData icon,
    required Color color,
    required bool isTesting,
    required bool? result,
    required VoidCallback onTap,
  }) {
    return Row(
      children: [
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: color.withValues(alpha: 0.12),
            foregroundColor: color,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: color.withValues(alpha: 0.3)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
          onPressed: isTesting ? null : onTap,
          icon: isTesting
              ? SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(color)))
              : Icon(icon, size: 16),
          label: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ),
        if (result != null) ...[
          const SizedBox(width: 12),
          Icon(
            result ? Icons.check_circle : Icons.error_outline,
            color: result ? Colors.greenAccent : Colors.redAccent,
            size: 20,
          ),
          const SizedBox(width: 6),
          Text(
            result ? 'Skickat!' : 'Misslyckades',
            style: TextStyle(
              color: result ? Colors.greenAccent : Colors.redAccent,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  // ─────────────────────────────────────────────
  //  Logging helpers
  // ─────────────────────────────────────────────
  void _startLogPolling() {
    _logPollTimer?.cancel();
    _fetchLogs(); // immediate first fetch
    _logPollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _fetchLogs());
  }

  void _stopLogPolling() {
    _logPollTimer?.cancel();
    _logPollTimer = null;
  }

  Future<void> _fetchLogs() async {
    if (_logPaused) return;
    try {
      final data = await widget.apiService.fetchLogs(sinceId: _lastLogId > 0 ? _lastLogId : null);
      final entries = (data['entries'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (!mounted || entries.isEmpty) return;
      setState(() {
        _logEntries.addAll(entries);
        if (_logEntries.length > 1000) {
          _logEntries.removeRange(0, _logEntries.length - 1000);
        }
        _lastLogId = entries.last['id'] as int;
      });
      if (_logAutoScroll) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_logScrollCtrl.hasClients) {
            _logScrollCtrl.animateTo(
              _logScrollCtrl.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } catch (_) {}
  }

  void _clearLogs() => setState(() { _logEntries.clear(); _lastLogId = 0; });

  Future<void> _testDiscord() async {
    setState(() { _isTestingDiscord = true; _discordTestResult = null; });
    try {
      await _saveSettings();
      final res = await widget.apiService.testDiscordWebhook();
      if (!mounted) return;
      setState(() => _discordTestResult = res['success'] == true);
      if (res['success'] != true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Discord-fel: ${res['error'] ?? 'Okänt fel'}'),
          backgroundColor: Colors.redAccent,
        ));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _discordTestResult = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Fel: $e'),
        backgroundColor: Colors.redAccent,
      ));
    } finally {
      if (mounted) setState(() => _isTestingDiscord = false);
    }
  }

  Future<void> _testEmail() async {
    setState(() { _isTestingEmail = true; _emailTestResult = null; });
    try {
      await _saveSettings();
      final res = await widget.apiService.testEmail();
      if (!mounted) return;
      setState(() => _emailTestResult = res['success'] == true);
      if (res['success'] != true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('E-postfel: ${res['error'] ?? 'Okänt fel'}'),
          backgroundColor: Colors.redAccent,
        ));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _emailTestResult = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Fel: $e'),
        backgroundColor: Colors.redAccent,
      ));
    } finally {
      if (mounted) setState(() => _isTestingEmail = false);
    }
  }

}
