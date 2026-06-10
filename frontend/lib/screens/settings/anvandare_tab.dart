part of '../settings_screen.dart';

extension AnvandareTabExtension on _SettingsScreenState {
  // ─────────────────────────────────────────────
  //  Category: Användare (steg 7)
  // ─────────────────────────────────────────────
  Future<void> _loadUsers() async {
    if (_isLoadingUsers) return;
    setState(() => _isLoadingUsers = true);
    try {
      final list = await widget.apiService.fetchUsers();
      if (mounted) {
        setState(() => _users = list.cast<Map<String, dynamic>>());
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoadingUsers = false);
    }
  }

  Future<void> _createUser() async {
    final un = _newUsernameCtrl.text.trim();
    final pw = _newPasswordCtrl.text.trim();
    if (un.isEmpty || pw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fyll i användarnamn och lösenord'), backgroundColor: Colors.redAccent),
      );
      return;
    }
    setState(() => _isCreatingUser = true);
    try {
      await widget.apiService.createUser(un, pw, _newUserRole);
      if (!mounted) return;
      _newUsernameCtrl.clear();
      _newPasswordCtrl.clear();
      setState(() => _newUserRole = 'User');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Användare "$un" skapad!'), backgroundColor: const Color(0xFF8A5BFF)),
      );
      _loadUsers();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fel: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _isCreatingUser = false);
    }
  }

  Future<void> _showResetPasswordDialog(Map<String, dynamic> user) async {
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF15102A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        title: Text('Återställ lösenord — ${user['username']}',
            style: const TextStyle(color: Colors.white, fontSize: 15)),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: ctrl,
            obscureText: true,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            contextMenuBuilder: (ctx, state) =>
                AdaptiveTextSelectionToolbar.editableText(editableTextState: state),
            decoration: _inputDeco('Nytt lösenord...'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Avbryt', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8A5BFF),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              final pw = ctrl.text.trim();
              if (pw.isEmpty) return;
              Navigator.pop(ctx);
              try {
                await widget.apiService.updateUser(user['id'] as String, password: pw);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Lösenord återställt för ${user['username']}'), backgroundColor: const Color(0xFF8A5BFF)),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Fel: $e'), backgroundColor: Colors.redAccent),
                );
              }
            },
            child: const Text('Spara'),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditUserDialog(Map<String, dynamic> user) async {
    final uid = user['id'] as String;
    final fullNameCtrl = TextEditingController(text: user['full_name'] as String? ?? '');
    final usernameCtrl = TextEditingController(text: user['username'] as String? ?? '');
    final pinCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    // Prefill PIN field with stored plaintext so admin can see/edit it
    final existingPin = user['pin_plain'] as String? ?? '';
    pinCtrl.text = existingPin;
    bool savingEdit = false;
    bool showPin = false;
    bool showPass = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDs) => AlertDialog(
          backgroundColor: const Color(0xFF15102A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
          title: Row(children: [
            _buildUserAvatar(user, user['role'] as String? ?? 'User', user['username'] as String? ?? '?', radius: 16),
            const SizedBox(width: 10),
            Text('Redigera — ${user['username']}',
                style: const TextStyle(color: Colors.white, fontSize: 15)),
          ]),
          content: SizedBox(
            width: 400,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: usernameCtrl,
                style: const TextStyle(color: Colors.white),
                contextMenuBuilder: (ctx, state) =>
                    AdaptiveTextSelectionToolbar.editableText(editableTextState: state),
                decoration: _inputDeco('Användarnamn'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: fullNameCtrl,
                style: const TextStyle(color: Colors.white),
                contextMenuBuilder: (ctx, state) =>
                    AdaptiveTextSelectionToolbar.editableText(editableTextState: state),
                decoration: _inputDeco('Fullständigt namn (valfritt)'),
              ),
              const SizedBox(height: 14),
              // PIN — visa nuvarande + kan redigera
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('PIN-kod (4–8 siffror)',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11)),
                const SizedBox(height: 6),
                TextField(
                  controller: pinCtrl,
                  keyboardType: TextInputType.number,
                  obscureText: !showPin,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
                  style: const TextStyle(color: Colors.white, letterSpacing: 3),
                  contextMenuBuilder: (ctx, state) =>
                      AdaptiveTextSelectionToolbar.editableText(editableTextState: state),
                  decoration: _inputDeco('Lämna tomt för att ta bort PIN').copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(showPin ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          color: Colors.white38, size: 18),
                      onPressed: () => setDs(() => showPin = !showPin),
                    ),
                    prefixIcon: const Icon(Icons.pin_outlined, color: Colors.white30, size: 16),
                    hintText: existingPin.isNotEmpty ? 'Nuvarande: ${existingPin.length} siffror' : 'Ingen PIN satt',
                  ),
                ),
                if (existingPin.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 4),
                    child: Text('Nuvarande PIN är förifylld',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 10)),
                  ),
              ]),
              const SizedBox(height: 14),
              // Nytt lösenord (admin kan byta)
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Nytt lösenord (lämna tomt = ingen ändring)',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11)),
                const SizedBox(height: 6),
                TextField(
                  controller: passwordCtrl,
                  obscureText: !showPass,
                  style: const TextStyle(color: Colors.white),
                  contextMenuBuilder: (ctx, state) =>
                      AdaptiveTextSelectionToolbar.editableText(editableTextState: state),
                  decoration: _inputDeco('').copyWith(
                    hintText: 'Nytt lösenord...',
                    suffixIcon: IconButton(
                      icon: Icon(showPass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          color: Colors.white38, size: 18),
                      onPressed: () => setDs(() => showPass = !showPass),
                    ),
                    prefixIcon: const Icon(Icons.lock_outline, color: Colors.white30, size: 16),
                  ),
                ),
              ]),
            ]),
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Colors.white24),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Avbryt'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8A5BFF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: savingEdit ? null : () async {
                setDs(() => savingEdit = true);
                final newUsername = usernameCtrl.text.trim();
                final fullName = fullNameCtrl.text.trim();
                final pin = pinCtrl.text.trim();
                final password = passwordCtrl.text;
                try {
                  await widget.apiService.updateUser(uid,
                    username: newUsername.isNotEmpty ? newUsername : null,
                    fullName: fullName,
                    // empty pin field = remove PIN, changed pin = update, same as existing = no change
                    pin: pin != existingPin ? pin : null,
                    password: password.isNotEmpty ? password : null,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  _loadUsers();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Användare uppdaterad ✅'), backgroundColor: Color(0xFF8A5BFF)),
                  );
                } catch (e) {
                  setDs(() => savingEdit = false);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Fel: $e'), backgroundColor: Colors.redAccent),
                  );
                }
              },
              child: savingEdit
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)))
                  : const Text('Spara'),
            ),
          ],
        ),
      ),
    );
    fullNameCtrl.dispose();
    usernameCtrl.dispose();
    pinCtrl.dispose();
    passwordCtrl.dispose();
  }

  // Determinstic avatar color (same palette as user_picker_overlay)
  static Color _userAvatarColor(String username) {
    const palette = [
      Color(0xFF8A5BFF), Color(0xFF5B8AFF), Color(0xFF5BFFB5),
      Color(0xFFFF5B8A), Color(0xFFFFB55B), Color(0xFF5BD4FF),
      Color(0xFFD45BFF), Color(0xFF5BFF5B),
    ];
    int hash = 0;
    for (final c in username.codeUnits) hash = (hash * 31 + c) & 0x7FFFFFFF;
    return palette[hash % palette.length];
  }

  static String _userInitials(String username) {
    final parts = username.trim().split(RegExp(r'[\s_.-]+'));
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return username.substring(0, username.length.clamp(0, 2)).toUpperCase();
  }

  Widget _buildUserAvatar(Map<String, dynamic> user, String role, String username, {double radius = 20}) {
    final color = _userAvatarColor(username);
    final avatarPath = user['avatar_path'] as String?;
    final avatarUrl = (avatarPath != null && avatarPath.isNotEmpty)
        ? '${widget.apiService.baseUrl}$avatarPath?t=${DateTime.now().millisecondsSinceEpoch ~/ 60000}'
        : null;
    return CircleAvatar(
      radius: radius,
      backgroundColor: color.withValues(alpha: 0.2),
      backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
      child: avatarUrl == null
          ? Text(
              _userInitials(username),
              style: TextStyle(color: color, fontSize: radius * 0.6, fontWeight: FontWeight.bold),
            )
          : null,
    );
  }

  Widget _buildAnvandare() {
    final callerPayload = widget.apiService.currentUserPayload;
    final isAdmin = callerPayload?['role'] == 'Admin';

    if (!isAdmin) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 48, color: Colors.white12),
            const SizedBox(height: 16),
            const Text('Kräver Admin-rättigheter',
                style: TextStyle(color: Colors.white54, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text('Kontakta en administratör för att hantera användare.',
                style: TextStyle(color: Colors.white24, fontSize: 13)),
          ],
        ),
      );
    }

    if (_users.isEmpty && !_isLoadingUsers) {
      Future.microtask(_loadUsers);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // ── Befintliga användare ──────────────
          _buildSection('Användare', Icons.group_outlined, [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${_users.length} användare',
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
                IconButton(
                  onPressed: _isLoadingUsers ? null : _loadUsers,
                  icon: _isLoadingUsers
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Color(0xFF8A5BFF))))
                      : const Icon(Icons.refresh, color: Colors.white38, size: 18),
                  tooltip: 'Uppdatera',
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_users.isEmpty && !_isLoadingUsers)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 24),
                alignment: Alignment.center,
                child: const Text('Inga användare hittades', style: TextStyle(color: Colors.white24)),
              )
            else
              ..._users.map((u) => _buildUserListItem(u, callerPayload?['id'] as String?)),
          ]),
          const SizedBox(height: 16),
          // ── Skapa ny användare ────────────────
          _buildSection('Lägg till användare', Icons.person_add_outlined, [
            _buildField('Användarnamn', _newUsernameCtrl),
            const SizedBox(height: 12),
            _buildField('Lösenord', _newPasswordCtrl, obscure: true),
            const SizedBox(height: 12),
            _buildDropdown('Roll', _newUserRole, ['User', 'Admin'],
                (v) => setState(() => _newUserRole = v ?? 'User')),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8A5BFF),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _isCreatingUser ? null : _createUser,
                icon: _isCreatingUser
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)))
                    : const Icon(Icons.add),
                label: Text(_isCreatingUser ? 'Skapar...' : 'Skapa användare',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildUserListItem(Map<String, dynamic> user, String? callerId) {
    final uid    = user['id'] as String;
    final username = user['username'] as String;
    final role   = user['role'] as String;
    final isSelf = uid == callerId;
    final hasPin = (user['has_pin'] as int? ?? 0) == 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          _buildUserAvatar(user, role, username, radius: 18),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(username,
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                if (isSelf) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('Du', style: TextStyle(color: Colors.white38, fontSize: 10)),
                  ),
                ],
              ]),
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: role == 'Admin'
                      ? Colors.amber.withValues(alpha: 0.1)
                      : const Color(0xFF8A5BFF).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: role == 'Admin'
                        ? Colors.amber.withValues(alpha: 0.3)
                        : const Color(0xFF8A5BFF).withValues(alpha: 0.3),
                  ),
                ),
                child: Text(role,
                    style: TextStyle(
                      color: role == 'Admin' ? Colors.amber : const Color(0xFFB593FF),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    )),
              ),
              if (hasPin) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8A5BFF).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF8A5BFF).withValues(alpha: 0.3)),
                  ),
                  child: const Text('PIN ✓', style: TextStyle(color: Color(0xFFB593FF), fontSize: 9, fontWeight: FontWeight.bold)),
                ),
              ],
            ]),
          ),
          // Toggle roll
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white38, size: 20),
            color: const Color(0xFF15102A),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'edit',
                child: Row(children: [
                  Icon(Icons.edit_outlined, size: 16, color: Colors.white54),
                  SizedBox(width: 8),
                  Text('Redigera (namn, PIN)', style: TextStyle(color: Colors.white, fontSize: 13)),
                ]),
              ),
              PopupMenuItem(
                value: 'role',
                child: Row(children: [
                  Icon(role == 'Admin' ? Icons.person_outline : Icons.admin_panel_settings_outlined,
                      size: 16, color: Colors.white54),
                  const SizedBox(width: 8),
                  Text(role == 'Admin' ? 'Ändra till User' : 'Ändra till Admin',
                      style: const TextStyle(color: Colors.white, fontSize: 13)),
                ]),
              ),
              const PopupMenuItem(
                value: 'reset',
                child: Row(children: [
                  Icon(Icons.lock_reset, size: 16, color: Colors.white54),
                  SizedBox(width: 8),
                  Text('Återställ lösenord', style: TextStyle(color: Colors.white, fontSize: 13)),
                ]),
              ),
              if (hasPin)
                const PopupMenuItem(
                  value: 'remove_pin',
                  child: Row(children: [
                    Icon(Icons.pin_outlined, size: 16, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('Ta bort PIN', style: TextStyle(color: Colors.orange, fontSize: 13)),
                  ]),
                ),
              if (!isSelf)
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(children: [
                    Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                    SizedBox(width: 8),
                    Text('Ta bort', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
                  ]),
                ),
            ],
            onSelected: (action) async {
              if (action == 'edit') {
                await _showEditUserDialog(user);
              } else if (action == 'role') {
                final newRole = role == 'Admin' ? 'User' : 'Admin';
                try {
                  await widget.apiService.updateUser(uid, role: newRole);
                  _loadUsers();
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Fel: $e'), backgroundColor: Colors.redAccent),
                  );
                }
              } else if (action == 'reset') {
                await _showResetPasswordDialog(user);
              } else if (action == 'remove_pin') {
                try {
                  await widget.apiService.updateUser(uid, pin: '');
                  _loadUsers();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('PIN borttagen för $username'), backgroundColor: const Color(0xFF8A5BFF)),
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Fel: $e'), backgroundColor: Colors.redAccent),
                  );
                }
              } else if (action == 'delete') {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: const Color(0xFF15102A),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    title: const Text('Ta bort användare', style: TextStyle(color: Colors.white)),
                    content: Text('Är du säker på att du vill ta bort "$username"?',
                        style: const TextStyle(color: Colors.white70)),
                    actions: [
                      OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: Colors.white24),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Avbryt'),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Ta bort'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  try {
                    await widget.apiService.deleteUser(uid);
                    _loadUsers();
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Fel: $e'), backgroundColor: Colors.redAccent),
                    );
                  }
                }
              }
            },
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  Stub for coming-soon categories
  // ─────────────────────────────────────────────
  Widget _buildStub(String title, IconData icon, String description) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: Colors.white12),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(color: Colors.white54, fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SizedBox(
            width: 360,
            child: Text(description,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white24, fontSize: 13, height: 1.5)),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  Helper widgets
  // ─────────────────────────────────────────────
  Widget _buildAutoSaveIndicator() {
    if (_autoSaveStatus == 'saving') {
      return Row(mainAxisSize: MainAxisSize.min, children: const [
        SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white38))),
        SizedBox(width: 6),
        Text('Sparar...', style: TextStyle(color: Colors.white38, fontSize: 12)),
      ]);
    }
    if (_autoSaveStatus == 'saved') {
      return const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.check_circle_outline, size: 14, color: Color(0xFF00E676)),
        SizedBox(width: 6),
        Text('Sparat', style: TextStyle(color: Color(0xFF00E676), fontSize: 12)),
      ]);
    }
    return const SizedBox.shrink();
  }

}
