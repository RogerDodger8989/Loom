part of '../settings_screen.dart';

extension KontoTabExtension on _SettingsScreenState {
  // ─────────────────────────────────────────────
  //  Category: Konto (steg 8)
  // ─────────────────────────────────────────────
  Widget _buildAvatarDisplay({required double radius, required String initials}) {
    if (_avatarImageBytes == null) {
      if (_avatarUrl != null) {
        return ClipOval(
          child: Image.network(
            _avatarUrl!,
            width: radius * 2, height: radius * 2, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => CircleAvatar(
              radius: radius,
              backgroundColor: const Color(0xFF8A5BFF).withValues(alpha: 0.15),
              child: Text(initials, style: TextStyle(color: const Color(0xFFB593FF), fontSize: radius * 0.65, fontWeight: FontWeight.bold)),
            ),
          ),
        );
      }
      return CircleAvatar(
        radius: radius,
        backgroundColor: const Color(0xFF8A5BFF).withValues(alpha: 0.15),
        child: Text(initials,
            style: TextStyle(color: const Color(0xFFB593FF),
                fontSize: radius * 0.65, fontWeight: FontWeight.bold)),
      );
    }
    final size = radius * 2;
    final factor = size / 180.0;
    return ClipOval(
      child: SizedBox(
        width: size, height: size,
        child: OverflowBox(
          maxWidth: double.infinity, maxHeight: double.infinity,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..translate(_avatarOffset.dx * factor, _avatarOffset.dy * factor)
              ..scale(_avatarScale),
            child: Image.memory(_avatarImageBytes!, width: size, height: size, fit: BoxFit.cover),
          ),
        ),
      ),
    );
  }

  Future<Uint8List> _cropAvatar(Uint8List bytes, double scale, Offset offset) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final img = frame.image;

    const size = 180.0;
    final iW = img.width.toDouble();
    final iH = img.height.toDouble();

    // Scale the image to cover the 180×180 canvas (same as BoxFit.cover)
    final coverScale = max(size / iW, size / iH);
    final drawW = iW * coverScale;
    final drawH = iH * coverScale;
    final drawX = (size - drawW) / 2;
    final drawY = (size - drawH) / 2;

    // Compute the visible rectangle in IMAGE pixel coordinates directly.
    // The preview uses: T(90+dx,90+dy) * S(scale) * T(-90,-90) applied to drawn space.
    // The inverse maps output (cx,cy) → drawn (cx-90-dx)/scale+90.
    // Then drawn → image via  (drawn - drawOrigin) / coverScale.
    final drawnLeft   = (0.0  - size/2 - offset.dx) / scale + size/2;
    final drawnTop    = (0.0  - size/2 - offset.dy) / scale + size/2;
    final drawnRight  = (size - size/2 - offset.dx) / scale + size/2;
    final drawnBottom = (size - size/2 - offset.dy) / scale + size/2;

    final srcLeft   = (drawnLeft   - drawX) / coverScale;
    final srcTop    = (drawnTop    - drawY) / coverScale;
    final srcRight  = (drawnRight  - drawX) / coverScale;
    final srcBottom = (drawnBottom - drawY) / coverScale;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.clipRect(const Rect.fromLTWH(0, 0, size, size));

    canvas.drawImageRect(
      img,
      Rect.fromLTRB(srcLeft, srcTop, srcRight, srcBottom),
      const Rect.fromLTWH(0, 0, size, size),
      Paint()..filterQuality = FilterQuality.high,
    );

    final picture = recorder.endRecording();
    final result = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await result.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<void> _pickAvatar() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return;
    final bytes = result.files.single.bytes!;

    double scale = 1.0;
    Offset offset = Offset.zero;
    Offset? panStart;
    Offset offsetAtPanStart = Offset.zero;
    final valueNotifier = ValueNotifier<int>(0);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDs) => AlertDialog(
          backgroundColor: const Color(0xFF15102A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
          title: const Text('Välj profilbild', style: TextStyle(color: Colors.white)),
          content: SizedBox(
            width: 360,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Zooma och flytta bilden för att välja utsnitt.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12)),
              const SizedBox(height: 20),
              // Preview med ring
              Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Cirkulär klipp
                    ClipOval(
                      child: SizedBox(
                        width: 180, height: 180,
                        child: GestureDetector(
                          onScaleStart: (d) {
                            panStart = d.focalPoint;
                            offsetAtPanStart = offset;
                          },
                          onScaleUpdate: (d) {
                            setDs(() {
                              scale = (scale * d.scale).clamp(0.5, 4.0);
                              if (panStart != null) {
                                offset = offsetAtPanStart + (d.focalPoint - panStart!);
                              }
                            });
                          },
                          child: ValueListenableBuilder<int>(
                            valueListenable: valueNotifier,
                            builder: (_, __, ___) => Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.identity()
                                ..translate(offset.dx, offset.dy)
                                ..scale(scale),
                              child: Image.memory(bytes, fit: BoxFit.cover,
                                  width: 180, height: 180),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Ring overlay
                    IgnorePointer(
                      child: Container(
                        width: 184, height: 184,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF8A5BFF), width: 3),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Zoom-slider
              Row(children: [
                const Icon(Icons.zoom_out, color: Colors.white38, size: 18),
                Expanded(
                  child: StatefulBuilder(
                    builder: (_, ss) => SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: const Color(0xFF8A5BFF),
                        inactiveTrackColor: Colors.white12,
                        thumbColor: const Color(0xFFB593FF),
                        overlayColor: const Color(0xFF8A5BFF).withValues(alpha: 0.12),
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      ),
                      child: Slider(
                        value: scale,
                        min: 0.5, max: 4.0,
                        onChanged: (v) { setDs(() => scale = v); },
                      ),
                    ),
                  ),
                ),
                const Icon(Icons.zoom_in, color: Colors.white38, size: 18),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Avbryt', style: TextStyle(color: Colors.white54))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8A5BFF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Välj bild'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;
    // Rendera det valda utsnittet till en 180×180 bild
    final croppedBytes = await _cropAvatar(bytes, scale, offset);
    // Spara croppade bytes i state — ingen transform behövs längre
    setState(() {
      _avatarImageBytes = croppedBytes;
      _avatarScale = 1.0;
      _avatarOffset = Offset.zero;
    });
    // Upload till backend
    try {
      // Evict stale cached avatar before uploading so all Image.network widgets
      // refetch the new image instead of serving the old cached version.
      if (_avatarUrl != null) {
        PaintingBinding.instance.imageCache.evict(NetworkImage(_avatarUrl!));
      }
      await widget.apiService.uploadAvatar(croppedBytes);
      if (!mounted) return;
      final payload = widget.apiService.currentUserPayload;
      if (payload != null) {
        // Append timestamp to bust any remaining cache in widgets still holding the old URL.
        final ts = DateTime.now().millisecondsSinceEpoch;
        setState(() => _avatarUrl = '${widget.apiService.baseUrl}/api/avatars/${payload['id']}.jpg?t=$ts');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profilbild uppdaterad ✅'), backgroundColor: Color(0xFF8A5BFF)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunde inte ladda upp bild: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Widget _buildKonto() {
    final payload = widget.apiService.currentUserPayload;
    final username = payload?['username'] as String? ?? '—';
    final role = payload?['role'] as String? ?? '—';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // ── Inloggad som ──────────────────────
          _buildSection('Inloggad som', Icons.person_outline, [
            Row(children: [
              // Avatar med klick för uppladdning
              GestureDetector(
                onTap: _pickAvatar,
                child: Stack(
                  children: [
                    _buildAvatarDisplay(radius: 34, initials: username.isNotEmpty ? username[0].toUpperCase() : '?'),
                    Positioned(
                      right: 0, bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Color(0xFF8A5BFF),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.camera_alt, color: Colors.white, size: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(username, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: role == 'Admin'
                        ? Colors.amber.withValues(alpha: 0.12)
                        : const Color(0xFF8A5BFF).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: role == 'Admin'
                          ? Colors.amber.withValues(alpha: 0.4)
                          : const Color(0xFF8A5BFF).withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(role,
                      style: TextStyle(
                        color: role == 'Admin' ? Colors.amber : const Color(0xFFB593FF),
                        fontSize: 11, fontWeight: FontWeight.bold,
                      )),
                ),
                const SizedBox(height: 4),
                Text('Klicka på bilden för att byta profilbild',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11)),
              ]),
            ]),
          ]),
          const SizedBox(height: 16),

          // ── Profilinformation (auto-save) ─────
          _buildSection('Profilinformation', Icons.edit_outlined, [
            Row(children: [
              const Spacer(),
              if (_profileSaveStatus == 'saving')
                const SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Color(0xFFB593FF))))
              else if (_profileSaveStatus == 'saved')
                const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.check_circle, color: Colors.greenAccent, size: 14),
                  SizedBox(width: 4),
                  Text('Sparat', style: TextStyle(color: Colors.greenAccent, fontSize: 11)),
                ]),
            ]),
            const SizedBox(height: 4),
            _buildField('Fullständigt namn', _fullNameCtrl,
                hint: 'Ditt riktiga namn (valfritt)',
                onSave: _scheduleProfileSave),
            const SizedBox(height: 12),
            _buildField('Användarnamn', _newUsernameEditCtrl,
                hint: 'Ditt användarnamn',
                onSave: _scheduleProfileSave),
          ]),
          const SizedBox(height: 16),

          // ── PIN-kod (auto-save vid korrekt indata) ─
          _buildSection('PIN-kod', Icons.pin_outlined, [
            Text('PIN-koden visas vid profilval i startskärmen.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12, height: 1.5)),
            const SizedBox(height: 12),
            _buildField('PIN-kod (4–8 siffror)', _pinCtrl,
                hint: 'Ange ny PIN — sparas automatiskt när den är giltig',
                onSave: _schedulePin),
            const SizedBox(height: 10),
            ExcludeFocusTraversal(
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _removePin,
                  icon: const Icon(Icons.no_encryption_outlined, size: 14, color: Colors.redAccent),
                  label: const Text('Ta bort PIN', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 16),

          // ── Byt lösenord (behöver bekräftelse → behåller knapp) ──
          _buildSection('Byt lösenord', Icons.lock_outline, [
            _buildField('Nuvarande lösenord', _currentPassCtrl, obscure: true, noAutoSave: true),
            const SizedBox(height: 12),
            _buildField('Nytt lösenord', _newPassCtrl, obscure: true, noAutoSave: true),
            const SizedBox(height: 12),
            _buildField('Bekräfta nytt lösenord', _confirmPassCtrl, obscure: true, noAutoSave: true),
            const SizedBox(height: 16),
            ExcludeFocusTraversal(
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8A5BFF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _isChangingPassword ? null : _changeOwnPassword,
                  icon: _isChangingPassword
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)))
                      : const Icon(Icons.lock_reset),
                  label: Text(_isChangingPassword ? 'Sparar...' : 'Byt lösenord',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Future<void> _saveProfile() async {
    final fullName = _fullNameCtrl.text.trim();
    final newUsername = _newUsernameEditCtrl.text.trim();
    if (fullName.isEmpty && newUsername.isEmpty) return;
    setState(() => _isSavingProfile = true);
    try {
      await widget.apiService.updateOwnProfile(
        fullName: fullName.isNotEmpty ? fullName : null,
        newUsername: newUsername.isNotEmpty ? newUsername : null,
      );
      if (!mounted) return;
      _fullNameCtrl.clear();
      _newUsernameEditCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil uppdaterad ✅'), backgroundColor: Color(0xFF8A5BFF)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fel: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _isSavingProfile = false);
    }
  }

  Future<void> _savePin() async {
    final pin = _pinCtrl.text.trim();
    if (pin.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ange en PIN-kod'), backgroundColor: Colors.redAccent),
      );
      return;
    }
    if (pin.length < 4 || pin.length > 8 || !RegExp(r'^\d+$').hasMatch(pin)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN måste vara 4–8 siffror'), backgroundColor: Colors.redAccent),
      );
      return;
    }
    setState(() => _isSavingProfile = true);
    try {
      await widget.apiService.updateOwnProfile(pin: pin);
      if (!mounted) return;
      _pinCtrl.clear();
      setState(() => _hasPinSet = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN-kod satt ✅'), backgroundColor: Color(0xFF8A5BFF)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fel: $e'), backgroundColor: Colors.redAccent));
    } finally {
      if (mounted) setState(() => _isSavingProfile = false);
    }
  }

  Future<void> _removePin() async {
    setState(() => _isSavingProfile = true);
    try {
      await widget.apiService.updateOwnProfile(pin: '');
      if (!mounted) return;
      setState(() => _hasPinSet = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN-kod borttagen'), backgroundColor: Color(0xFF8A5BFF)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fel: $e'), backgroundColor: Colors.redAccent));
    } finally {
      if (mounted) setState(() => _isSavingProfile = false);
    }
  }

  Future<void> _changeOwnPassword() async {
    final current = _currentPassCtrl.text.trim();
    final newPw = _newPassCtrl.text.trim();
    final confirm = _confirmPassCtrl.text.trim();

    if (current.isEmpty || newPw.isEmpty || confirm.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fyll i alla fält'), backgroundColor: Colors.redAccent),
      );
      return;
    }
    if (newPw != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lösenorden matchar inte'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    setState(() => _isChangingPassword = true);
    try {
      await widget.apiService.updateOwnPassword(current, newPw);
      if (!mounted) return;
      _currentPassCtrl.clear();
      _newPassCtrl.clear();
      _confirmPassCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lösenord bytt! ✅'), backgroundColor: Color(0xFF8A5BFF)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fel: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _isChangingPassword = false);
    }
  }

}
