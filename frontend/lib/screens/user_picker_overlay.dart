import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api.dart';
import 'dashboard_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Public helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Show the profile picker as a full-screen dialog on top of the current route.
/// [onSuccess] is called after a successful login so the caller can navigate/refresh.
Future<void> showUserPicker(
  BuildContext context,
  ApiService apiService, {
  required VoidCallback onSuccess,
  bool canCancel = true,
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: canCancel,
    barrierLabel: 'picker',
    barrierColor: Colors.transparent,
    pageBuilder: (ctx, anim, _) => _UserPickerPage(
      apiService: apiService,
      onSuccess: onSuccess,
      canCancel: canCancel,
      animation: anim,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal overlay page
// ─────────────────────────────────────────────────────────────────────────────

class _UserPickerPage extends StatefulWidget {
  final ApiService apiService;
  final VoidCallback onSuccess;
  final bool canCancel;
  final Animation<double> animation;

  const _UserPickerPage({
    required this.apiService,
    required this.onSuccess,
    required this.canCancel,
    required this.animation,
  });

  @override
  State<_UserPickerPage> createState() => _UserPickerPageState();
}

class _UserPickerPageState extends State<_UserPickerPage> {
  List<Map<String, dynamic>> _profiles = [];
  bool _loading = true;
  String? _fetchError;

  int _focusedIndex = 0;
  String? _selectedUsername;
  String? _selectedUserId;

  // Password login
  final _passCtrl = TextEditingController();
  final _passFocus = FocusNode();
  bool _loggingIn = false;
  String? _loginError;
  bool _obscure = true;
  bool _rememberPassword = false;

  // PIN login
  final _pinCtrl = TextEditingController();
  final _pinFocus = FocusNode();
  bool _isPinMode = false;   // true = show PIN field instead of password
  bool _pinFailed = false;   // true = PIN was tried and failed → show fallback

  @override
  void initState() {
    super.initState();
    _loadProfiles();
    // Pre-tick "kom ihåg lösenord" if saved credentials exist
    final saved = widget.apiService.loadRememberedLogin();
    if (saved != null) _rememberPassword = true;
  }

  @override
  void dispose() {
    _passCtrl.dispose();
    _passFocus.dispose();
    _pinCtrl.dispose();
    _pinFocus.dispose();
    super.dispose();
  }

  Future<void> _loadProfiles() async {
    try {
      final data = await widget.apiService.fetchProfiles();
      if (mounted) {
        setState(() {
          _profiles = data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _loading = false;
          if (_profiles.isEmpty) _fetchError = 'Inga användare hittades';
        });
        // Auto-fill saved password if only one profile / matching username
        final saved = widget.apiService.loadRememberedLogin();
        if (saved != null) {
          _passCtrl.text = saved['password']!;
        }
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _fetchError = e.toString(); });
    }
  }

  // ── Login methods ────────────────────────────────────────────────────────

  Future<void> _loginWithPin(String userId) async {
    final pin = _pinCtrl.text.trim();
    if (pin.isEmpty) { _pinFocus.requestFocus(); return; }
    setState(() { _loggingIn = true; _loginError = null; });
    try {
      await widget.apiService.loginWithPin(userId, pin);
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onSuccess();
    } catch (_) {
      if (mounted) setState(() { _loggingIn = false; _loginError = 'Fel PIN'; _pinFailed = true; });
    }
  }

  Future<void> _loginAs(String username) async {
    final password = _passCtrl.text;
    if (password.isEmpty) { _passFocus.requestFocus(); return; }
    setState(() { _loggingIn = true; _loginError = null; });
    try {
      await widget.apiService.login(username, password);
      if (!mounted) return;
      if (_rememberPassword) {
        await widget.apiService.saveRememberedLogin(username, password);
      } else {
        await widget.apiService.clearRememberedLogin();
      }
      Navigator.of(context).pop();
      widget.onSuccess();
    } catch (_) {
      if (mounted) setState(() { _loggingIn = false; _loginError = 'Fel lösenord'; });
    }
  }

  void _selectProfile(int index) {
    final profile = _profiles[index];
    final username = profile['username'] as String? ?? '?';
    final userId   = profile['id'] as String? ?? '';
    final hasPin   = (profile['has_pin'] as int? ?? 0) == 1;

    setState(() {
      _focusedIndex = index;
      _selectedUsername = username;
      _selectedUserId   = userId;
      _passCtrl.clear();
      _pinCtrl.clear();
      _loginError = null;
      _pinFailed  = false;
      _isPinMode  = hasPin;
    });

    Future.delayed(const Duration(milliseconds: 80), () {
      if (!mounted) return;
      if (hasPin) {
        _pinFocus.requestFocus();
      } else {
        _passFocus.requestFocus();
      }
    });
  }

  void _switchToPasswordMode() {
    setState(() { _isPinMode = false; _pinFailed = false; _loginError = null; });
    Future.delayed(const Duration(milliseconds: 80), () {
      if (mounted) _passFocus.requestFocus();
    });
  }

  // ── Keyboard ─────────────────────────────────────────────────────────────

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (_selectedUsername != null) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        setState(() { _selectedUsername = null; _loginError = null; _isPinMode = false; _pinFailed = false; });
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter) {
        if (_isPinMode && !_pinFailed) {
          _loginWithPin(_selectedUserId!);
        } else {
          _loginAs(_selectedUsername!);
        }
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      setState(() => _focusedIndex = (_focusedIndex - 1 + _profiles.length) % _profiles.length);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      setState(() => _focusedIndex = (_focusedIndex + 1) % _profiles.length);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (_profiles.isNotEmpty) _selectProfile(_focusedIndex);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape && widget.canCancel) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // Deterministic avatar color from username
  static Color _avatarColor(String username) {
    const palette = [
      Color(0xFF8A5BFF), Color(0xFF5B8AFF), Color(0xFF5BFFB5),
      Color(0xFFFF5B8A), Color(0xFFFFB55B), Color(0xFF5BD4FF),
      Color(0xFFD45BFF), Color(0xFF5BFF5B),
    ];
    int hash = 0;
    for (final c in username.codeUnits) hash = (hash * 31 + c) & 0x7FFFFFFF;
    return palette[hash % palette.length];
  }

  static String _initials(String username) {
    final parts = username.trim().split(RegExp(r'[\s_.-]+'));
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return username.substring(0, username.length.clamp(0, 2)).toUpperCase();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.animation,
      builder: (context, child) => Opacity(opacity: widget.animation.value, child: child),
      child: Focus(
        autofocus: true,
        onKeyEvent: _handleKey,
        child: Material(
          color: Colors.transparent,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Blurred backdrop
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF0A0714).withValues(alpha: 0.82),
                        const Color(0xFF150E2A).withValues(alpha: 0.88),
                      ],
                    ),
                  ),
                ),
              ),

              // Content
              Center(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // LOOM icon
                      Container(
                        width: 52, height: 52,
                        decoration: BoxDecoration(
                          color: const Color(0xFF8A5BFF).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFF8A5BFF).withValues(alpha: 0.25)),
                        ),
                        child: const Icon(Icons.play_circle_outline, color: Color(0xFF8A5BFF), size: 28),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Välj profil',
                        style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Använd ← → och Enter, eller klicka',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 12),
                      ),
                      const SizedBox(height: 40),

                      // Profile cards
                      if (_loading)
                        const CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(Color(0xFF8A5BFF)))
                      else if (_fetchError != null)
                        Text(_fetchError!, style: const TextStyle(color: Colors.redAccent))
                      else
                        _buildProfileRow(),

                      // Login step (PIN or password)
                      AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                        child: _selectedUsername != null
                            ? _buildLoginStep()
                            : const SizedBox.shrink(),
                      ),

                      if (widget.canCancel) ...[
                        const SizedBox(height: 32),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: TextButton.styleFrom(foregroundColor: Colors.white30),
                          child: const Text('Avbryt  (ESC)'),
                        ),
                      ],
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileRow() {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 20,
      runSpacing: 20,
      children: List.generate(_profiles.length, (i) {
        final profile = _profiles[i];
        final username  = profile['username'] as String? ?? '?';
        final isFocused = i == _focusedIndex && _selectedUsername == null;
        final isSelected = _selectedUsername == username;
        final color = _avatarColor(username);
        final avatarPath = profile['avatar_path'] as String?;
        final avatarUrl  = (avatarPath != null && avatarPath.isNotEmpty)
            ? '${widget.apiService.baseUrl}$avatarPath?t=${DateTime.now().millisecondsSinceEpoch ~/ 60000}'
            : null;
        final hasPin = (profile['has_pin'] as int? ?? 0) == 1;

        return GestureDetector(
          onTap: () => _selectProfile(i),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _focusedIndex = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 110,
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
              decoration: BoxDecoration(
                color: (isFocused || isSelected)
                    ? color.withValues(alpha: 0.12)
                    : Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: (isFocused || isSelected) ? color.withValues(alpha: 0.7) : Colors.white.withValues(alpha: 0.07),
                  width: (isFocused || isSelected) ? 2 : 1,
                ),
                boxShadow: (isFocused || isSelected)
                    ? [BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 18, spreadRadius: 1)]
                    : [],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Avatar circle with image or initials
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width:  (isFocused || isSelected) ? 64 : 58,
                    height: (isFocused || isSelected) ? 64 : 58,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(alpha: 0.2),
                      border: Border.all(
                        color: color.withValues(alpha: (isFocused || isSelected) ? 0.8 : 0.4),
                        width: (isFocused || isSelected) ? 2.5 : 1.5,
                      ),
                    ),
                    child: ClipOval(
                      child: avatarUrl != null
                          ? Image.network(
                              avatarUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _buildInitialsAvatar(username, color, isFocused || isSelected),
                            )
                          : _buildInitialsAvatar(username, color, isFocused || isSelected),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: (isFocused || isSelected) ? Colors.white : Colors.white70,
                      fontSize: 13,
                      fontWeight: (isFocused || isSelected) ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    profile['role'] as String? ?? '',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 10),
                  ),
                  if (hasPin) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8A5BFF).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF8A5BFF).withValues(alpha: 0.3)),
                      ),
                      child: const Text('PIN', style: TextStyle(color: Color(0xFFB593FF), fontSize: 9, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildInitialsAvatar(String username, Color color, bool large) {
    return Center(
      child: Text(
        _initials(username),
        style: TextStyle(color: color, fontSize: large ? 20 : 18, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildLoginStep() {
    final username = _selectedUsername!;
    final userId   = _selectedUserId!;
    final color    = _avatarColor(username);

    // Show PIN input first (if user has PIN and PIN hasn't failed yet)
    if (_isPinMode && !_pinFailed) {
      return _buildPinStep(userId, username, color);
    }
    return _buildPasswordStep(username, color);
  }

  Widget _buildPinStep(String userId, String username, Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 28, 0, 0),
      child: Column(
        children: [
          Text(
            'PIN-kod för $username',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: 300,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _pinCtrl,
                    focusNode: _pinFocus,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
                    autofocus: false,
                    style: const TextStyle(color: Colors.white, fontSize: 15, letterSpacing: 4),
                    onSubmitted: (_) => _loginWithPin(userId),
                    contextMenuBuilder: (ctx, state) =>
                        AdaptiveTextSelectionToolbar.editableText(editableTextState: state),
                    decoration: InputDecoration(
                      hintText: '4–8 siffror',
                      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.25), letterSpacing: 1),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: color.withValues(alpha: 0.3))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: color, width: 1.5)),
                      prefixIcon: const Icon(Icons.pin_outlined, color: Colors.white38, size: 18),
                      errorText: _loginError,
                      errorStyle: const TextStyle(color: Colors.redAccent, fontSize: 11),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _loginButton(color, () => _loginWithPin(userId)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: () => setState(() { _selectedUsername = null; _loginError = null; _isPinMode = false; _pinFailed = false; }),
                style: TextButton.styleFrom(foregroundColor: Colors.white24),
                child: const Text('← Välj annan profil', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _switchToPasswordMode,
                style: TextButton.styleFrom(foregroundColor: Colors.white38),
                child: const Text('Logga in med lösenord istället', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordStep(String username, Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 28, 0, 0),
      child: Column(
        children: [
          Text(
            _pinFailed ? 'Lösenord för $username (PIN misslyckades)' : 'Lösenord för $username',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: 300,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _passCtrl,
                    focusNode: _passFocus,
                    obscureText: _obscure,
                    autofocus: false,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    onSubmitted: (_) => _loginAs(username),
                    contextMenuBuilder: (ctx, state) =>
                        AdaptiveTextSelectionToolbar.editableText(editableTextState: state),
                    decoration: InputDecoration(
                      hintText: 'Ange lösenord',
                      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.25)),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: color.withValues(alpha: 0.3))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: color, width: 1.5)),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                          color: Colors.white38, size: 18,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                      errorText: _loginError,
                      errorStyle: const TextStyle(color: Colors.redAccent, fontSize: 11),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _loginButton(color, () => _loginAs(username)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Kom ihåg lösenord + navigation row
          SizedBox(
            width: 300,
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => setState(() => _rememberPassword = !_rememberPassword),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 18, height: 18,
                        child: Checkbox(
                          value: _rememberPassword,
                          onChanged: (v) => setState(() => _rememberPassword = v ?? false),
                          activeColor: const Color(0xFF8A5BFF),
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text('Kom ihåg lösenord',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12)),
                    ],
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() { _selectedUsername = null; _loginError = null; _isPinMode = false; _pinFailed = false; }),
                  style: TextButton.styleFrom(foregroundColor: Colors.white24, padding: EdgeInsets.zero),
                  child: const Text('← Välj annan profil', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
          if (_loginError != null) ...[
            const SizedBox(height: 8),
            Text(
              'Glömt lösenord? Kontakta en admin för återställning.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _loginButton(Color color, VoidCallback onTap) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 50, height: 50,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: _loggingIn
          ? Center(child: SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(color))))
          : IconButton(
              icon: Icon(Icons.arrow_forward_rounded, color: color),
              onPressed: onTap,
            ),
    );
  }
}
