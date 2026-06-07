import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api.dart';
import 'dashboard_screen.dart';
import 'user_picker_overlay.dart';

class LoginScreen extends StatefulWidget {
  final ApiService apiService;
  const LoginScreen({super.key, required this.apiService});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  List<Map<String, dynamic>> _profiles = [];
  bool _loading = true;
  String? _fetchError;

  int _focusedIndex = 0;
  String? _selectedUsername;
  final _passCtrl = TextEditingController();
  final _passFocus = FocusNode();
  bool _loggingIn = false;
  String? _loginError;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  @override
  void dispose() {
    _passCtrl.dispose();
    _passFocus.dispose();
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
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _fetchError = e.toString(); });
    }
  }

  Future<void> _loginAs(String username) async {
    final password = _passCtrl.text;
    if (password.isEmpty) { _passFocus.requestFocus(); return; }
    setState(() { _loggingIn = true; _loginError = null; });
    try {
      await widget.apiService.login(username, password);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => DashboardScreen(apiService: widget.apiService)),
      );
    } catch (_) {
      if (mounted) setState(() { _loggingIn = false; _loginError = 'Fel lösenord'; });
    }
  }

  void _selectProfile(int index) {
    setState(() {
      _focusedIndex = index;
      _selectedUsername = _profiles[index]['username'] as String?;
      _passCtrl.clear();
      _loginError = null;
    });
    Future.delayed(const Duration(milliseconds: 80), () {
      if (mounted) _passFocus.requestFocus();
    });
  }

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

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_profiles.isEmpty) return KeyEventResult.ignored;

    if (_selectedUsername != null) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        setState(() { _selectedUsername = null; _loginError = null; });
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter) {
        _loginAs(_selectedUsername!);
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
      _selectProfile(_focusedIndex);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0714),
      body: Focus(
        autofocus: true,
        onKeyEvent: _handleKey,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background — subtle radial glow
            Positioned.fill(
              child: CustomPaint(painter: _GlowPainter()),
            ),

            Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Logo
                    Container(
                      width: 60, height: 60,
                      decoration: BoxDecoration(
                        color: const Color(0xFF8A5BFF).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF8A5BFF).withValues(alpha: 0.3)),
                      ),
                      child: const Icon(Icons.play_circle_outline, color: Color(0xFF8A5BFF), size: 32),
                    ),
                    const SizedBox(height: 18),
                    const Text('LOOM',
                        style: TextStyle(color: Colors.white, fontSize: 28,
                            fontWeight: FontWeight.bold, letterSpacing: 7)),
                    const SizedBox(height: 6),
                    Text('Välj profil',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 14)),
                    const SizedBox(height: 8),
                    Text('← → och Enter, eller klicka',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.2), fontSize: 11)),
                    const SizedBox(height: 44),

                    // ── Profile cards ──────────────────────────────────────
                    if (_loading)
                      const CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation(Color(0xFF8A5BFF)),
                      )
                    else if (_fetchError != null)
                      Text(_fetchError!, style: const TextStyle(color: Colors.redAccent))
                    else
                      _buildProfileRow(),

                    // ── Password step ─────────────────────────────────────
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      child: _selectedUsername != null
                          ? _buildPasswordStep()
                          : const SizedBox.shrink(),
                    ),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
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
        final username = _profiles[i]['username'] as String? ?? '?';
        final isFocused = i == _focusedIndex && _selectedUsername == null;
        final isSelected = _selectedUsername == username;
        final color = _avatarColor(username);

        return GestureDetector(
          onTap: () => _selectProfile(i),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _focusedIndex = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 120,
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 14),
              decoration: BoxDecoration(
                color: (isFocused || isSelected)
                    ? color.withValues(alpha: 0.1)
                    : Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: (isFocused || isSelected)
                      ? color.withValues(alpha: 0.65)
                      : Colors.white.withValues(alpha: 0.07),
                  width: (isFocused || isSelected) ? 2 : 1,
                ),
                boxShadow: (isFocused || isSelected)
                    ? [BoxShadow(color: color.withValues(alpha: 0.2), blurRadius: 20, spreadRadius: 2)]
                    : [],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: (isFocused || isSelected) ? 68 : 60,
                    height: (isFocused || isSelected) ? 68 : 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(alpha: 0.18),
                      border: Border.all(
                        color: color.withValues(alpha: (isFocused || isSelected) ? 0.85 : 0.4),
                        width: (isFocused || isSelected) ? 2.5 : 1.5,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        _initials(username),
                        style: TextStyle(
                          color: color,
                          fontSize: (isFocused || isSelected) ? 22 : 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: (isFocused || isSelected) ? Colors.white : Colors.white70,
                      fontSize: 14,
                      fontWeight: (isFocused || isSelected) ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _profiles[i]['role'] as String? ?? '',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.28), fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildPasswordStep() {
    final username = _selectedUsername!;
    final color = _avatarColor(username);

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 32, 0, 0),
      child: Column(
        children: [
          Text(
            'Lösenord för $username',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 14),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: 320,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _passCtrl,
                    focusNode: _passFocus,
                    obscureText: _obscure,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    onSubmitted: (_) => _loginAs(username),
                    contextMenuBuilder: (ctx, state) =>
                        AdaptiveTextSelectionToolbar.editableText(editableTextState: state),
                    decoration: InputDecoration(
                      hintText: 'Ange lösenord',
                      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.22)),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: color.withValues(alpha: 0.3)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: color, width: 1.8),
                      ),
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
                SizedBox(
                  width: 52,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color.withValues(alpha: 0.2),
                      foregroundColor: color,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      side: BorderSide(color: color.withValues(alpha: 0.5)),
                      padding: EdgeInsets.zero,
                      elevation: 0,
                    ),
                    onPressed: _loggingIn ? null : () => _loginAs(username),
                    child: _loggingIn
                        ? SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(color),
                            ),
                          )
                        : Icon(Icons.arrow_forward_rounded, color: color, size: 22),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => setState(() { _selectedUsername = null; _loginError = null; }),
            style: TextButton.styleFrom(foregroundColor: Colors.white24),
            child: const Text('← Välj annan profil', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

// Subtle purple radial glow for the login background
class _GlowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = RadialGradient(
        center: Alignment.topCenter,
        radius: 1.4,
        colors: [
          const Color(0xFF8A5BFF).withValues(alpha: 0.12),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(_) => false;
}
